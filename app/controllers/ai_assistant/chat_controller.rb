# frozen_string_literal: true

module AiAssistant
  class ChatController < ApplicationController
    before_action :require_login

    accept_api_auth :send_message, :history

    def send_message
      message = params[:message].to_s.strip
      conversation_id = params[:conversation_id].presence || SecureRandom.uuid

      if message.blank?
        render json: { error: 'Message is required' }, status: :bad_request
        return
      end

      # 服务端兜底预检：插件启用但 AI 服务尚未配置完成时，
      # 返回友好提示而不是让用户看到"内部错误"。
      unless ai_ready_for_user?
        render json: { error: l(:error_ai_not_configured_for_user) },
               status: :service_unavailable
        return
      end

      # 保存用户消息
      user_msg = AiMessage.create!(
        user:            User.current,
        conversation_id: conversation_id,
        role:            'user',
        content:         message
      )

      # 加载历史消息
      history = load_conversation_history(conversation_id)

      # 注入 Guard Prompt（只读约束）
      system_content = build_system_content(message, history)

      # 构建消息数组
      messages = build_messages(system_content, history, message)

      # 调用 AI（通过统一 API，自动处理服务商解析）
      provider = resolve_provider
      result   = AiAssistant.chat_messages(messages, provider: provider)

      if result[:error]
        render json: { error: result[:error] }, status: :service_unavailable
        return
      end

      # 保存 AI 回复
      assistant_msg = AiMessage.create!(
        user:            User.current,
        ai_provider:     provider,
        conversation_id: conversation_id,
        role:            'assistant',
        content:         result[:content],
        model:           result[:model],
        tokens_used:     result[:tokens_used]
      )

      render json: {
        conversation_id: conversation_id,
        message: {
          id:           assistant_msg.id,
          role:         'assistant',
          content:      result[:content],
          tokens_used:  result[:tokens_used]
        }
      }
    rescue StandardError => e
      Rails.logger.error "AI Chat Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render json: { error: "内部错误: #{e.message}" }, status: :internal_server_error
    end

    def history
      conversation_id = params[:conversation_id]

      unless conversation_id
        render json: { error: 'conversation_id is required' }, status: :bad_request
        return
      end

      messages = AiMessage.by_conversation(conversation_id)
                          .where(user_id: User.current.id)

      render json: {
        conversation_id: conversation_id,
        messages: messages.map { |m|
          {
            id:          m.id,
            role:        m.role,
            content:     m.content,
            created_at:  m.created_at,
            tokens_used: m.tokens_used
          }
        }
      }
    end

    def clear
      conversation_id = params[:conversation_id]

      if conversation_id.present?
        AiMessage.where(conversation_id: conversation_id, user_id: User.current.id).delete_all
      end

      render json: { success: true }
    end

    private

    # 任务/问题查询关键词（中英文）
    TASK_QUERY_KEYWORDS = %w[
      任务 我的任务 task tasks 指派 assign 我 待办 代办 todo
      问题 issue issues
      今天 今日 today 本周 本月 week month 今年 去年
      状态 status 优先级 priority 进度 progress
      报告 report reports 汇总 summary 总结 概括 详情 详细
      版本 version versions 截止 逾期 overdue 预计 计划
      统计 statistics count 所有 全部
    ].freeze

    def resolve_provider
      provider_id = Setting.plugin_redmine_ai_assistant.try(:[], 'default_provider_id')
      if provider_id.present?
        AiProvider.enabled.find_by(id: provider_id)
      end || AiProvider.enabled.ordered.first
    end

    # 检查 AI 是否对当前用户真正可用（仅校验：是否有启用的服务商且其 API key 已填写）。
    # API key 是管理员集中配置的，不应在每个用户气泡里泄露"未配置"等内部细节。
    def ai_ready_for_user?
      provider = resolve_provider
      return false if provider.nil?
      return false if provider.api_key.blank?

      true
    end

    def load_conversation_history(conversation_id)
      max_messages = (Setting.plugin_redmine_ai_assistant.try(:[], 'max_history_messages') || 20).to_i

      AiMessage.by_conversation(conversation_id)
               .where(user_id: User.current.id)
               .order(created_at: :desc)
               .limit(max_messages)
               .reverse
    end

    def build_system_content(message, history)
      # 基础系统提示
      base = "You are an AI assistant integrated with #{system_app_name}.\n" \
             "Current user: #{User.current.name}\n" \
             "Current time: #{Time.current}\n" \
             "You are in READ-ONLY mode. You MUST NOT generate any instructions, suggestions, or messages that imply you can modify, update, create, delete, or execute any action on data in the system. " \
             "NEVER proactively tell the user to reply with commands such as '进度改为100%', '状态改为已关闭', or '添加备注：...' as if you can perform those operations. " \
             "If the user explicitly asks to change data, explain that you are read-only and cannot execute actions; do not provide step-by-step command instructions. " \
             "When task or issue data is provided in the context above, you MUST answer the user's question based ONLY on that data. " \
             "Do not fall back to generic greetings or introductions when specific data is available. " \
             "When referencing issues/tasks by ID, always use Markdown link format `[#ID](URL)` so users can click to open them."

      # 注入管理员自定义系统提示词（优先级最高，放在最前面）
      custom_prompt = load_custom_system_prompt
      if custom_prompt.present?
        base = "#{custom_prompt.strip}\n\n#{base}"
      end

      # 检测是否需要注入 Guard Prompt（需同时检查 guard_prompt_enabled 开关）
      guard_enabled = Setting.plugin_redmine_ai_assistant.try(:[], 'guard_prompt_enabled')
      if guard_enabled != '0' &&
         (GuardPrompt.guard_needed?(message) ||
          history.any? { |m| m.role == 'user' && GuardPrompt.guard_needed?(m.content) })
        base = GuardPrompt.inject(base, message)
      end

      # 检测任务/报告类查询，注入真实 Redmine 数据
      if task_query?(message)
        task_context = build_task_context(message)
        base = "#{task_context}\n\n#{base}"
      else
        hint = task_keywords_hint
        base = "#{hint}\n\n#{base}"
      end

      base
    end

    # 加载管理员自定义系统提示词
    def load_custom_system_prompt
      Setting.plugin_redmine_ai_assistant.try(:[], 'system_prompt').presence
    end

    # 获取当前系统名称（优先使用 Setting.app_title，fallback 到 Redmine）
    def system_app_name
      Setting.app_title.presence || 'Redmine'
    end

    # 生成 issue 的完整 URL 链接
    def issue_url(issue_id)
      "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue_id}"
    end

    # 生成 Markdown 格式的 issue 链接: [#ID](url)
    def issue_link(issue_id)
      "[##{issue_id}](#{issue_url(issue_id)})"
    end

    # 判断是否为任务/报告类查询：命中关键词、包含 #ID、或指定了 <姓名/工号>
    def task_query?(message)
      return false if message.blank?

      lower = message.downcase
      keyword_matched = TASK_QUERY_KEYWORDS.any? { |kw| lower.include?(kw) }
      keyword_matched || extract_issue_ids(message).any? || extract_target_keyword(message).present?
    end

    # 生成任务关键词提示，在用户未触发任务查询时注入系统提示
    def task_keywords_hint
      <<~HINT
        ## Friendly Task Query Guidance
        The user's message did not trigger task data lookup. Help them understand how to access real system data:
        - Reference specific tasks by ID using `#ID` format (e.g., "#123", "#456"). The system will then fetch those tasks for you.
        - Use task-related keywords: 任务/task, 我的任务/my tasks, 待办/todo, 指派/assigned
        - Use report keywords: 报告/report, 汇总/summary, 总结/summarize, 日报/daily report, 周报/weekly report, 月报/monthly report
        - Use time keywords: 今天/today, 本周/this week, 本月/this month
        - Use status keywords: 状态/status, 优先级/priority, 进度/progress, 逾期/overdue, 截止/due
        Respond in a friendly, encouraging tone. Do NOT just say "I don't have data" — instead, guide the user on what they can type to get actionable task information.
      HINT
    end

    # 从消息中提取 #ID 任务编号（忽略已存在的 Markdown 链接 [#ID](url)）
    def extract_issue_ids(message)
      return [] if message.blank?

      message.scan(/(?:^|[\s])#(\d+)\b(?!\]\()/).flatten.map(&:to_i).uniq
    end

    # 构建任务上下文数据
    # - 若消息中包含 #ID，优先返回这些特定任务
    # - 若消息包含 <姓名/工号>，尝试解析指定指派人（仅管理员可查他人）
    # - 否则返回当前用户的任务列表
    # message 用于解析时间范围（如"今年"、"本月"、"近30天"）
    def build_task_context(message)
      current_user = User.current
      specific_ids = extract_issue_ids(message)
      target_keyword = extract_target_keyword(message)

      if specific_ids.any?
        build_specific_issue_context(specific_ids, current_user)
      elsif target_keyword
        build_target_user_context(target_keyword, current_user, message)
      else
        build_user_assigned_context(current_user, message)
      end
    end

    # 从消息中提取 <姓名/工号> 目标关键字（支持中文/英文尖括号）
    def extract_target_keyword(message)
      match = message.to_s.match(/[<＜]\s*([^>＞]+?)\s*[>＞]/)
      match ? match[1].strip : nil
    end

    # 按关键字查找用户：优先 login（工号）精确匹配，再按姓名（全名/名/姓）匹配
    def find_user_by_keyword(keyword)
      return nil if keyword.blank?

      kw = keyword.strip

      # 1. 登录名（工号/账号）精确匹配
      user = User.find_by(login: kw)
      return user if user

      # 2. 姓或名精确匹配
      candidates = User.where('firstname = ? OR lastname = ?', kw, kw).to_a

      # 3. 全名组合匹配（忽略空格，兼容 "姓+名" 与 "名+姓" 两种组合顺序，
      #    例如 lastname=邹 + firstname=悦 可被 <邹悦> 命中）
      if candidates.empty?
        compact = kw.tr(' ', '')
        # 用关键字中的字符做 LIKE 缩小候选集，再在 Ruby 中做全名组合比对
        char_patterns = compact.chars.reject(&:blank?).first(3)
        if char_patterns.any?
          cond = char_patterns.map { 'firstname LIKE ? OR lastname LIKE ?' }.join(' OR ')
          args = char_patterns.flat_map { |c| ["%#{c}%", "%#{c}%"] }
          User.where(cond, *args).limit(200).each do |u|
            next if u.firstname.blank? && u.lastname.blank?
            full_name     = "#{u.firstname}#{u.lastname}".tr(' ', '')
            full_name_rev = "#{u.lastname}#{u.firstname}".tr(' ', '')
            candidates << u if full_name == compact || full_name_rev == compact
          end
        end
      end

      candidates.uniq!
      candidates.size == 1 ? candidates.first : nil
    end

    # 构建指定指派人的上下文（含权限校验）
    def build_target_user_context(keyword, current_user, message)
      target_user = find_user_by_keyword(keyword)

      if target_user.nil?
        return <<~TEXT
          ## User Not Found

          No user matched "<#{keyword}>" (by login/employee ID or name). The requested assignee
          does not exist or the keyword is ambiguous.

          Politely inform the user (in Chinese) that the specified assignee was not found in the
          system, and suggest using the exact name or employee ID (e.g. <姓名> or <工号>).
          Do NOT fabricate any statistics.
        TEXT
      end

      unless target_user.id == current_user.id || current_user.admin?
        return <<~TEXT
          ## Permission Denied (非管理员无权查询他人任务统计)

          You were asked to generate task statistics for user "#{target_user.name}" (login: #{target_user.login}),
          but the current user "#{current_user.name}" (login: #{current_user.login}) is NOT an administrator.

          **FOCUS RULE (highest priority)**: The ONLY user being analyzed in this query is "#{target_user.name}".
          Earlier messages in the conversation may mention OTHER users (e.g. someone that did not exist
          in the system, or a previous test target) — IGNORE those completely. Do NOT mention, reference,
          compare with, or carry over statistics about any other user besides "#{target_user.name}".

          **POLICY (must follow)**: Only administrators may query other users' task statistics.
          Regular users can ONLY view statistics for themselves — querying anyone else is strictly
          forbidden by this system's data access policy.

          Required response (in Chinese, polite but firm). Use the EXACT name "#{target_user.name}"
          (login: #{target_user.login}) throughout — DO NOT substitute any other name:
          1. Apologize and decline: 「抱歉，您没有查看同事「#{target_user.name}」任务数据的权限。」
          2. Explain: 「根据系统权限策略，只有管理员可以查看他人的任务统计。普通用户只能查看自己的任务。」
          3. Offer the only allowed alternative: 「如需查看您自己的任务，请直接说『统计我今年内的所有任务』即可。」
          4. Suggest: 「如确有需要，请联系系统管理员协助查询。」

          **ABSOLUTELY DO NOT**:
          - Reveal any task counts, lists, or any information about "#{target_user.name}".
          - Estimate, infer, or fabricate ANY data about "#{target_user.name}".
          - Mention or substitute with ANY other user name (even one that appeared in earlier
          conversation turns). The forbidden user is EXACTLY "#{target_user.name}" and ONLY this name.
          - Provide workarounds, indirect clues, or partial disclosures.
          - Mention system internals (admin table, Role IDs, etc.).
        TEXT
      end

      build_user_assigned_context(target_user, message)
    end

    # 构建特定任务编号的上下文
    def build_specific_issue_context(issue_ids, user)
      issues = Issue.where(id: issue_ids)
                    .includes(:project, :tracker, :status, :priority, :fixed_version, :author, :assigned_to)
                    .order(updated_on: :desc)
                    .limit(20)

      lines = []
      lines << "## Real #{system_app_name.upcase} Data - Referenced Issues/Tasks\n"

      if issues.empty?
        lines << "**The referenced issue(s) #{issue_ids.map { |id| issue_link(id) }.join(', ')} were not found.**"
      else
        lines << "### Referenced Issues/Tasks:"
        issues.each do |i|
          due = i.due_date ? "Due: #{i.due_date}" : "No due date"
          ver = i.fixed_version ? "Version: #{i.fixed_version.name}" : nil
          assignee = i.assigned_to ? "Assignee: #{i.assigned_to.name}" : "Unassigned"
          extra = [due, "Progress: #{i.done_ratio}%", ver, assignee].compact.join(", ")
          overdue = (i.due_date && i.due_date < Date.current) ? " ⚠️OVERDUE" : ""
          lines << "  - #{issue_link(i.id)} [#{i.tracker&.name}] [#{i.status&.name}] [#{i.priority&.name}] #{i.subject}#{overdue} (Project: #{i.project&.name}, Author: #{i.author&.name}, #{extra})"
        end
      end

      lines << ""
      lines << "**CRITICAL RULE: Only reference the tasks listed above. If the referenced issue does not exist or is not listed, tell the user. NEVER invent, guess, or fabricate tasks that are not explicitly listed above.**"
      lines.join("\n")
    end

    # 构建当前用户的任务上下文数据
    #
    # - 若消息中包含时间范围（今年/本月/近30天等），统计该时间段内指派给用户的
    #   **所有状态**任务（含已关闭），并附带汇总统计与分布，供报告/总结类场景使用；
    # - 若未指定时间范围，则返回未关闭任务列表 + 最近关闭的任务。
    def build_user_assigned_context(user, message = nil)
      time_range = extract_time_range(message)
      scope = Issue.where(assigned_to_id: user.id)
      scope = scope.where(created_on: time_range) if time_range

      open_status_ids   = IssueStatus.where(is_closed: false).pluck(:id)
      closed_status_ids = IssueStatus.where(is_closed: true).pluck(:id)

      open_scope   = scope.where(status_id: open_status_ids)
      closed_scope = scope.where(status_id: closed_status_ids)

      total_count  = scope.count
      open_count   = open_scope.count
      closed_count = closed_scope.count

      # 逾期未关闭统计
      overdue_count = open_scope.where('due_date IS NOT NULL AND due_date < ?', Date.current).count

      # 分布统计
      status_distribution  = scope.joins(:status).group('issue_statuses.name').count
      project_distribution = scope.joins(:project).group('projects.name').count
      tracker_distribution = scope.joins(:tracker).group('trackers.name').count
      monthly_trend = scope.pluck(:created_on).compact
                           .group_by { |t| t.strftime('%Y-%m') }
                           .transform_values(&:count).sort.to_h

      # 详细列表
      open_issues = open_scope.includes(:project, :tracker, :status, :priority, :fixed_version)
                              .order(created_on: :desc)
                              .limit(50)

      closed_issues = closed_scope.includes(:project, :tracker, :status, :priority, :fixed_version)
                                  .order(Arel.sql('COALESCE(closed_on, updated_on) DESC'))
                                  .limit(30)

      lines = []
      period_label = time_range ? format_period_label(time_range) : 'All Time'
      lines << "## Real #{system_app_name.upcase} Data - Assigned Issues/Tasks for #{user.name}\n"

      # 汇总统计
      lines << "### Summary (Period: #{period_label})"
      lines << "- Total tasks: #{total_count}"
      lines << "- Open tasks: #{open_count}"
      lines << "- Closed tasks: #{closed_count}"
      lines << "- Overdue (open & past due date): #{overdue_count}"
      lines << ""

      # 状态分布
      unless status_distribution.empty?
        lines << "### Distribution by Status"
        status_distribution.sort_by { |_, c| -c }.each { |name, count| lines << "  - #{name}: #{count}" }
        lines << ""
      end

      # 项目分布
      unless project_distribution.empty?
        lines << "### Distribution by Project"
        project_distribution.sort_by { |_, c| -c }.each { |name, count| lines << "  - #{name}: #{count}" }
        lines << ""
      end

      # 类型分布
      unless tracker_distribution.empty?
        lines << "### Distribution by Tracker"
        tracker_distribution.sort_by { |_, c| -c }.each { |name, count| lines << "  - #{name}: #{count}" }
        lines << ""
      end

      # 每月创建趋势
      unless monthly_trend.empty?
        lines << "### Monthly Trend (created)"
        monthly_trend.each { |ym, count| lines << "  - #{ym}: #{count}" }
        lines << ""
      end

      # 打开任务明细
      if open_issues.any?
        lines << "### Open Issues Assigned to #{user.name} (#{open_issues.size} shown of #{open_count}):"
        open_issues.each do |i|
          due = i.due_date ? "Due: #{i.due_date}" : "No due date"
          ver = i.fixed_version ? "Version: #{i.fixed_version.name}" : nil
          extra = [due, "Progress: #{i.done_ratio}%", ver].compact.join(", ")
          overdue = (i.due_date && i.due_date < Date.current) ? " ⚠️OVERDUE" : ""
          lines << "  - #{issue_link(i.id)} [#{i.tracker&.name}] [#{i.status&.name}] [#{i.priority&.name}] #{i.subject}#{overdue} (Project: #{i.project&.name}, Created: #{i.created_on.to_date}, #{extra})"
        end
        lines << ""
      end

      # 最近关闭任务明细
      if closed_issues.any?
        lines << "### Recently Closed Issues (#{closed_issues.size} shown of #{closed_count}):"
        closed_issues.each do |i|
          ver = i.fixed_version ? "Version: #{i.fixed_version.name}" : nil
          extra = ["Closed: #{i.closed_on&.to_date || 'N/A'}", ver].compact.join(", ")
          lines << "  - #{issue_link(i.id)} [#{i.tracker&.name}] [#{i.status&.name}] #{i.subject} (Project: #{i.project&.name}, #{extra})"
        end
        lines << ""
      end

      # 空列表提示
      if total_count == 0
        lines << "**No issues/tasks assigned to #{user.name} in the specified period.**"
        lines << ""
      end

      lines << "**CRITICAL RULE: Only reference the tasks listed above for user #{user.name}. If the list shows no tasks, tell the user they have no assigned tasks. For any count/statistics, use the Summary numbers above as the ground truth. NEVER invent, guess, or fabricate tasks that are not explicitly listed above.**"
      lines << ""
      lines << "**FOCUS RULE: The ONLY user being analyzed in this query is #{user.name}. Do NOT mention, reference, compare with, or invent statistics about any other user (including ones that appeared in earlier conversation turns). If the user asks about someone else, politely say you can only report on #{user.name} in this turn.**"
      lines.join("\n")
    end

    # 从消息中提取时间范围（今年/去年/本月/上周/近N天/近N个月等）
    # 返回 Date Range 或 nil（未指定时间范围）
    def extract_time_range(message)
      return nil if message.blank?

      text = message.downcase
      today = Date.current

      if text =~ /今年|本年度|this year/
        today.beginning_of_year..today.end_of_year
      elsif text =~ /去年|last year/
        (today - 1.year).beginning_of_year..(today - 1.year).end_of_year
      elsif text =~ /本月|这个月|this month/
        today.beginning_of_month..today.end_of_month
      elsif text =~ /上月|上个月|last month/
        (today - 1.month).beginning_of_month..(today - 1.month).end_of_month
      elsif text =~ /本周|这周|this week/
        today.beginning_of_week..today.end_of_week
      elsif text =~ /上周|last week/
        (today - 1.week).beginning_of_week..(today - 1.week).end_of_week
      elsif text =~ /今天|今日|today/
        today..today
      elsif text =~ /昨天|昨日|yesterday/
        (today - 1.day)..(today - 1.day)
      elsif text =~ /近(\d+)天|最近(\d+)天|last (\d+) days/
        days = [$1, $2, $3].compact.map(&:to_i).first || 30
        (today - days.days)..today
      elsif text =~ /近(\d+)个月|最近(\d+)个月|近半年|半年内|last (\d+) months/
        months = [$1, $2, $3].compact.map(&:to_i).first
        months = 6 if months.nil? # 近半年
        (today - months.months)..today
      elsif text =~ /近(\d+)年|最近(\d+)年|last (\d+) years/
        years = [$1, $2, $3].compact.map(&:to_i).first || 1
        (today - years.years)..today
      end
    end

    # 格式化时间范围标签
    def format_period_label(range)
      "#{range.begin.to_date} ~ #{range.end.to_date}"
    end

    def build_messages(system_content, history, current_message)
      messages = [{ role: 'system', content: system_content }]

      history.each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      # 如果 history 中还没有包含当前消息（因为我们在前面已经单独保存了）
      already_included = history.any? { |m| m.content == current_message && m.role == 'user' }
      unless already_included
        messages << { role: 'user', content: current_message }
      end

      messages
    end
  end
end
