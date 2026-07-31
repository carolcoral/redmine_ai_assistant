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
      今天 今日 today 本周 本月 week month
      状态 status 优先级 priority 进度 progress
      报告 report reports 汇总 summary 总结 概括 详情 详细
      版本 version versions 截止 逾期 overdue 预计 计划
    ].freeze

    def resolve_provider
      provider_id = Setting.plugin_redmine_ai_assistant.try(:[], 'default_provider_id')
      if provider_id.present?
        AiProvider.enabled.find_by(id: provider_id)
      end || AiProvider.enabled.ordered.first
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

    # 判断是否为任务/报告类查询：命中关键词 或 包含 #ID
    def task_query?(message)
      return false if message.blank?

      lower = message.downcase
      keyword_matched = TASK_QUERY_KEYWORDS.any? { |kw| lower.include?(kw) }
      keyword_matched || extract_issue_ids(message).any?
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
    # 若消息中包含 #ID，优先返回这些特定任务；否则返回当前用户的任务列表
    def build_task_context(message)
      user = User.current
      specific_ids = extract_issue_ids(message)

      if specific_ids.any?
        build_specific_issue_context(specific_ids, user)
      else
        build_user_assigned_context(user)
      end
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
    def build_user_assigned_context(user)
      # 查询指派给当前用户的未关闭任务
      open_issues = Issue.where(assigned_to_id: user.id)
                        .where(status_id: IssueStatus.where(is_closed: false).pluck(:id))
                        .includes(:project, :tracker, :status, :priority, :fixed_version)
                        .order(due_date: :asc, created_on: :desc)
                        .limit(50)

      # 查询指派给当前用户今天更新的任务
      today_updated = Issue.where(assigned_to_id: user.id)
                          .where.not(status_id: IssueStatus.where(is_closed: false).pluck(:id))
                          .where(updated_on: Time.current.beginning_of_day..Time.current.end_of_day)
                          .includes(:project, :tracker, :status, :priority, :fixed_version)
                          .order(updated_on: :desc)
                          .limit(10)

      # 逾期任务统计
      overdue_count = open_issues.count { |i| i.due_date.present? && i.due_date < Date.current }

      lines = []

      lines << "## Real #{system_app_name.upcase} Data - Assigned Issues/Tasks for #{user.name}\n"

      if open_issues.empty?
        lines << "**No open issues/tasks assigned to #{user.name}.**"
      else
        lines << "### Open Issues Assigned to You (#{open_issues.count} total, #{overdue_count} overdue):"
        open_issues.each do |i|
          due = i.due_date ? "Due: #{i.due_date}" : "No due date"
          ver = i.fixed_version ? "Version: #{i.fixed_version.name}" : nil
          extra = [due, "Progress: #{i.done_ratio}%", ver].compact.join(", ")
          overdue = (i.due_date && i.due_date < Date.current) ? " ⚠️OVERDUE" : ""
          lines << "  - #{issue_link(i.id)} [#{i.tracker&.name}] [#{i.status&.name}] [#{i.priority&.name}] #{i.subject}#{overdue} (Project: #{i.project&.name}, #{extra})"
        end
      end

      unless today_updated.empty?
        lines << ""
        lines << "### Recently Resolved/Updated Today (assigned to you, #{today_updated.count} total):"
        today_updated.each do |i|
          ver = i.fixed_version ? "Version: #{i.fixed_version.name}" : nil
          extra = ["Progress: #{i.done_ratio}%", ver].compact.join(", ")
          lines << "  - #{issue_link(i.id)} [#{i.status&.name}] #{i.subject} (Project: #{i.project&.name}, #{extra})"
        end
      end

      lines << ""
      lines << "**CRITICAL RULE: Only reference the tasks listed above. If the list shows no tasks, tell the user they currently have no assigned tasks. NEVER invent, guess, or fabricate tasks that are not explicitly listed above.**"
      lines.join("\n")
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
