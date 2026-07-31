# frozen_string_literal: true

module AiAssistant
  # 工作报告生成器 -- 基于用户行为数据生成日报/周报/月报
  #
  # 内部通过 AiAssistant::Client 统一调用 AI，对外不暴露服务商细节。
  class ReportGenerator
    # ========== 常量 ==========
    REPORT_TYPES = %w[daily weekly monthly].freeze

    attr_reader :user, :report_type, :timezone, :provider_id, :period_offset

    # period_offset: 0 = 当前周期, -1 = 上一周期（昨日/上周/上月）
    def initialize(user, report_type:, timezone: nil, provider_id: nil, period_offset: nil)
      @user          = user
      @report_type   = report_type.to_s
      @timezone      = timezone || Setting.user_format_time_zone(user) rescue 'UTC'
      @provider_id   = provider_id
      @period_offset = (period_offset || 0).to_i

      raise ArgumentError, "Invalid report type: #{report_type}" unless REPORT_TYPES.include?(@report_type)
    end

    # 生成 issue 的完整 URL 链接
    def issue_url(issue_id)
      "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue_id}"
    end

    # 生成 Markdown 格式的 issue 链接: [#ID](url)
    def issue_link(issue_id)
      "[##{issue_id}](#{issue_url(issue_id)})"
    end

    # 收集用户行为数据（所有 issue 相关数据仅包含指派给当前用户的任务）
    def collect_data
      range = time_range

      {
        user_name:           user.name,
        report_type:         report_type,
        period:              "#{range.begin.to_date} ~ #{range.end.to_date}",
        period_label:        period_label,
        time_entries:        fetch_time_entries(range),
        issues_assigned:     fetch_issues_assigned(range),
        issue_change_history: fetch_issue_change_history(range),
        issues_closed:       fetch_issues_closed(range),
        comments:            fetch_comments(range),
        wiki_updates:        fetch_wiki_updates(range),
        projects:            user_projects,
        status_summary:      fetch_status_summary,
        overdue_issues:      fetch_overdue_issues
      }
    end

    # 生成报告（通过统一 AI 客户端）
    def generate
      data = collect_data

      system_prompt = build_system_prompt
      user_prompt   = build_user_prompt(data)

      messages = [
        { role: 'system', content: system_prompt },
        { role: 'user',   content: user_prompt }
      ]

      # 使用统一 API，自动处理服务商解析
      result = AiAssistant.chat_messages(
        messages,
        provider:    provider,
        temperature: 0.3,
        max_tokens:  8192
      )

      if result[:error]
        { error: result[:error] }
      else
        # 保存生成的报告
        record = AiMessage.create!(
          user:          user,
          ai_provider:   provider,
          conversation_id: "report_#{SecureRandom.uuid}",
          role:          'assistant',
          content:       result[:content],
          model:         result[:model],
          tokens_used:   result[:tokens_used],
          report_type:   report_type
        )

        {
          content:     result[:content],
          message_id:  record.id,
          tokens_used: result[:tokens_used]
        }
      end
    end

    private

    def provider
      @provider ||= resolve_provider
    end

    def resolve_provider
      return AiProvider.enabled.ordered.first if provider_id.blank?

      AiProvider.enabled.find_by(id: provider_id) || AiProvider.enabled.ordered.first
    end

    def time_range
      tz_offset = ActiveSupport::TimeZone.new(timezone)&.utc_offset || 0
      now  = Time.current
      base = now

      case report_type
      when 'daily'   then base = now + period_offset.days
      when 'weekly'  then base = now + (period_offset * 7).days
      when 'monthly' then base = now + period_offset.months
      end

      case report_type
      when 'daily'
        start_time = base.beginning_of_day - tz_offset
        end_time   = base.end_of_day - tz_offset
      when 'weekly'
        start_time = base.beginning_of_week - tz_offset
        end_time   = base.end_of_week - tz_offset
      when 'monthly'
        start_time = base.beginning_of_month - tz_offset
        end_time   = base.end_of_month - tz_offset
      end

      start_time..end_time
    end

    # ---- 数据采集方法 (不变) ----

    def fetch_time_entries(range)
      TimeEntry.where(user_id: user.id)
               .where(spent_on: range.begin.to_date..range.end.to_date)
               .includes(:project, :issue, :activity)
               .order(spent_on: :desc)
               .map do |entry|
        {
          date:     entry.spent_on.to_s,
          hours:    entry.hours,
          project:  entry.project&.name,
          issue:    entry.issue&.subject,
          activity: entry.activity&.name,
          comments: entry.comments
        }
      end
    end

    def fetch_issues_assigned(range)
      Issue.where(assigned_to_id: user.id)
           .where(created_on: range)
           .includes(:project, :tracker, :status, :priority, :fixed_version)
           .order(created_on: :desc)
           .map do |issue|
        {
          id: issue.id, subject: issue.subject, project: issue.project&.name,
          tracker: issue.tracker&.name, status: issue.status&.name,
          priority: issue.priority&.name, done_ratio: issue.done_ratio,
          due_date: issue.due_date&.to_s, fixed_version: issue.fixed_version&.name,
          created: issue.created_on.to_s
        }
      end
    end

    def fetch_issue_change_history(range)
      assigned_issue_ids = Issue.where(assigned_to_id: user.id).pluck(:id)
      journals = Journal.where(journalized_type: 'Issue')
                        .where(journalized_id: assigned_issue_ids)
                        .where(created_on: range)
                        .includes(:issue, :user)
                        .order(created_on: :asc)

      grouped = journals.group_by(&:journalized_id)

      grouped.transform_values do |jls|
        issue = jls.first.issue
        {
          issue_id: issue&.id, subject: issue&.subject, project: issue&.project&.name,
          tracker: issue&.tracker&.name, status: issue&.status&.name,
          priority: issue&.priority&.name, done_ratio: issue&.done_ratio,
          due_date: issue&.due_date&.to_s, fixed_version: issue&.fixed_version&.name,
          created_on: issue&.created_on&.to_s,
          timeline: jls.map { |j| format_journal_entry(j) }
        }
      end
    rescue StandardError
      {}
    end

    def format_journal_entry(journal)
      entry = {
        time:  journal.created_on.strftime('%Y-%m-%d %H:%M'),
        user:  journal.user&.name,
        notes: journal.notes.presence
      }
      details = journal.visible_details.map { |d| format_detail(d) }.compact
      entry[:changes] = details if details.any?
      entry
    end

    DETAIL_LABELS = {
      'status_id' => '状态', 'priority_id' => '优先级', 'assigned_to_id' => '指派人',
      'fixed_version_id' => '版本', 'done_ratio' => '完成度', 'start_date' => '开始日期',
      'due_date' => '截止日期', 'estimated_hours' => '预估工时', 'subject' => '标题',
      'description' => '描述', 'tracker_id' => '类型', 'project_id' => '项目',
      'category_id' => '分类', 'parent_id' => '父任务'
    }.freeze

    def format_detail(detail)
      label = DETAIL_LABELS[detail.prop_key] || detail.prop_key
      old_v = resolve_detail_value(detail.prop_key, detail.old_value)
      new_v = resolve_detail_value(detail.prop_key, detail.value)
      old_v = old_v.presence || '(空)'
      new_v = new_v.presence || '(空)'

      if detail.prop_key == 'done_ratio'
        old_v = "#{old_v}%" unless old_v == '(空)'
        new_v = "#{new_v}%" unless new_v == '(空)'
      end

      old_v = old_v.truncate(50) if old_v.length > 50
      new_v = new_v.truncate(50) if new_v.length > 50

      "#{label}: #{old_v} → #{new_v}"
    end

    def resolve_detail_value(prop_key, value)
      return value if value.blank?

      case prop_key
      when 'fixed_version_id' then Version.find_by(id: value)&.name || value
      when 'status_id'        then IssueStatus.find_by(id: value)&.name || value
      when 'priority_id'      then IssuePriority.find_by(id: value)&.name || value
      when 'assigned_to_id'   then User.find_by(id: value)&.name || value
      when 'tracker_id'       then Tracker.find_by(id: value)&.name || value
      when 'project_id'       then Project.find_by(id: value)&.name || value
      when 'category_id'      then IssueCategory.find_by(id: value)&.name || value
      when 'author_id'        then User.find_by(id: value)&.name || value
      else value
      end
    end

    def fetch_issues_closed(range)
      Issue.where(assigned_to_id: user.id)
           .where(status_id: IssueStatus.where(is_closed: true).pluck(:id))
           .where(closed_on: range)
           .includes(:project, :tracker, :priority)
           .order(closed_on: :desc)
           .map do |issue|
        {
          id: issue.id, subject: issue.subject, project: issue.project&.name,
          tracker: issue.tracker&.name, priority: issue.priority&.name,
          closed: issue.closed_on.to_s
        }
      end
    end

    def fetch_comments(range)
      Journal.where(user_id: user.id)
             .where(created_on: range)
             .where.not(notes: [nil, ''])
             .includes(:journalized)
             .order(created_on: :desc)
             .map do |journal|
        {
          content: journal.notes,
          target:  journal_type_label(journal),
          created: journal.created_on.to_s
        }
      end
    end

    def fetch_wiki_updates(range)
      WikiContent::Version
        .joins('INNER JOIN wiki_contents ON wiki_contents.id = wiki_content_versions.wiki_content_id')
        .joins('INNER JOIN wiki_pages ON wiki_pages.id = wiki_contents.page_id')
        .joins('INNER JOIN wikis ON wikis.id = wiki_pages.wiki_id')
        .where(wiki_content_versions: { author_id: user.id })
        .where(wiki_content_versions: { updated_on: range })
        .select('wiki_content_versions.*, wiki_pages.title as page_title, wiki_pages.project_id')
        .order(updated_on: :desc)
        .map { |v| { page: v.page_title, updated: v.updated_on.to_s } }
    rescue StandardError
      []
    end

    def user_projects
      user.projects.active.pluck(:name)
    end

    def fetch_status_summary
      Issue.where(assigned_to_id: user.id)
           .where(status_id: IssueStatus.where(is_closed: false).pluck(:id))
           .group(:status_id)
           .count
           .transform_keys { |sid| IssueStatus.find_by(id: sid)&.name || "Status##{sid}" }
    rescue StandardError
      {}
    end

    def fetch_overdue_issues
      Issue.where(assigned_to_id: user.id)
           .where(status_id: IssueStatus.where(is_closed: false).pluck(:id))
           .where('due_date IS NOT NULL AND due_date < ?', Date.current)
           .includes(:project, :tracker, :status, :priority, :fixed_version)
           .order(due_date: :asc)
           .map do |issue|
        {
          id: issue.id, subject: issue.subject, project: issue.project&.name,
          status: issue.status&.name, priority: issue.priority&.name,
          done_ratio: issue.done_ratio, due_date: issue.due_date&.to_s,
          fixed_version: issue.fixed_version&.name
        }
      end
    rescue StandardError
      []
    end

    def journal_type_label(journal)
      case journal.journalized_type
      when 'Issue'    then "问题 ##{journal.journalized_id}"
      when 'WikiPage' then 'Wiki 页面'
      when 'Document' then '文档'
      when 'News'     then '新闻'
      else "#{journal.journalized_type} ##{journal.journalized_id}"
      end
    end

    # ---- Prompt 构建 ----

    def build_system_prompt
      app_name = Setting.app_title.presence || 'Redmine'
      prompt = GuardPrompt.guard_prefix_for(app_name) + <<~PROMPT
        You are a professional work report generator for #{app_name} project management system.
        Generate a well-structured #{report_type} work report based on the provided data.

        Report format guidelines:
        - Use clear headings: "## \u{1F4CA} #{report_type_label}工作报告"
        - Include sections: 工作总结, 时间分配, 问题跟进, 下周/下期计划
        - Use tables for numerical data when appropriate
        - Keep the tone professional and factual
        - Summarize key accomplishments and blockers
        - Total time entries hours
        - Highlight important issues
        - **Analyze issues by version (版本) grouping**: group overdue and in-progress issues by their version to give version-level progress insights
        - **Status & Progress**: Report on status distribution, average progress % per version, and highlight overdue items
        - **Due Date Analysis**: Pay attention to upcoming deadlines and overdue items, suggest priority adjustments
        - **Issue Links**: When referencing any issue/task by its ID, ALWAYS preserve the Markdown link format `[#ID](URL)` provided in the raw data. Do NOT convert issue links to plain `#ID` text.
        - Output in Markdown format
        - Use the user's language (Chinese by default unless data indicates otherwise)
      PROMPT

      custom_prompt = load_custom_system_prompt
      prompt = "#{custom_prompt.strip}\n\n#{prompt}" if custom_prompt.present?
      prompt
    end

    def load_custom_system_prompt
      Setting.plugin_redmine_ai_assistant.try(:[], 'system_prompt').presence
    end

    def build_user_prompt(data)
      <<~PROMPT
        Please generate a #{report_type} work report for user: #{data[:user_name]}
        Report period: #{data[:period]} (#{data[:period_label]})

        **IMPORTANT: All issue/task data below is filtered by "assigned to #{data[:user_name]}" only.**

        ## Raw Data

        ### Time Entries (#{data[:time_entries].length} records)
        #{format_time_entries(data[:time_entries])}

        ### Issues Assigned to You This Period (#{data[:issues_assigned].length} records)
        #{format_issues(data[:issues_assigned])}

        ### Issue Change History Timeline (Cross-Period Tracking)
        #{format_change_history(data[:issue_change_history])}

        **Note**: The timeline above shows issue changes that occurred during this report period.
        Some issues may have been created earlier but had updates/changes during this period.
        Use this timeline to understand the progress and evolution of each task.

        ### Issues Closed by You (#{data[:issues_closed].length} records)
        #{format_issues(data[:issues_closed])}

        ### Current Open Issue Status Summary
        #{format_status_summary(data[:status_summary])}

        ### Overdue Issues (past due date, not yet closed)
        #{format_overdue_issues(data[:overdue_issues])}

        ### Comments Made (#{data[:comments].length} records)
        #{format_comments(data[:comments])}

        ### Projects Involved
        #{data[:projects].join(', ')}

        Generate the report now with rich details from the change history timeline.
        **IMPORTANT**: Pay special attention to the status summary and overdue issues -- if there are overdue items across multiple versions,
        analyze them by version grouping and highlight the most critical blockers.
      PROMPT
    end

    def report_type_label
      case report_type
      when 'daily'   then '日报'
      when 'weekly'  then '周报'
      when 'monthly' then '月报'
      end
    end

    def period_label
      case report_type
      when 'daily'   then period_offset == 0 ? '今日' : '昨日'
      when 'weekly'  then period_offset == 0 ? '本周' : '上周'
      when 'monthly' then period_offset == 0 ? '本月' : '上月'
      end
    end

    # ---- 格式化方法 ----

    def format_change_history(history)
      return '(无变更记录)' if history.blank?

      lines = []
      history.each do |_issue_id, data|
        next if data.blank? || data[:timeline].blank?

        lines << ""
        lines << "---"
        lines << "**#{issue_link(data[:issue_id])} #{data[:subject]}**"
        lines << "  项目: #{data[:project]} | 类型: #{data[:tracker]} | 当前状态: #{data[:status]} | 优先级: #{data[:priority]}"
        lines << "  进度: #{data[:done_ratio]}% | 截止日期: #{data[:due_date] || '无'} | 版本: #{data[:fixed_version] || '无'} | 创建于: #{data[:created_on]}"

        data[:timeline].each do |entry|
          time_str = entry[:time]
          user_str = entry[:user] || '系统'
          lines << "  \u{1F4CD} #{time_str} by #{user_str}:"
          entry[:changes]&.each do |change|
            lines << "     \u2022 #{change}"
          end
          if entry[:notes].present?
            lines << "     \u{1F4AC} #{entry[:notes].truncate(150)}"
          end
        end
      end

      return '(无变更记录)' if lines.empty?
      lines.join("\n")
    end

    def format_time_entries(entries)
      return '(无)' if entries.empty?

      entries.map do |e|
        "- #{e[:date]} | #{e[:hours]}h | #{e[:project]} | #{e[:issue] || 'N/A'} | #{e[:activity]} #{e[:comments].present? ? "| #{e[:comments]}" : ''}"
      end.join("\n")
    end

    def format_issues(issues)
      return '(无)' if issues.empty?

      issues.map do |i|
        due_str = i[:due_date] ? " 截止:#{i[:due_date]}" : ""
        ver_str = i[:fixed_version] ? " 版本:#{i[:fixed_version]}" : ""
        "- #{issue_link(i[:id])} #{i[:subject]} [#{i[:tracker]}] [#{i[:status]}] [#{i[:priority]}] 进度:#{i[:done_ratio]}%#{due_str}#{ver_str} (#{i[:project]})"
      end.join("\n")
    end

    def format_comments(comments)
      return '(无)' if comments.empty?

      comments.first(20).map do |c|
        "- #{c[:created]}: #{c[:content].truncate(200)} (#{c[:target]})"
      end.join("\n")
    end

    def format_status_summary(status_summary)
      return '(无)' if status_summary.blank?

      total = status_summary.values.sum
      lines = ["总未关闭任务数: #{total}"]
      status_summary.each do |status_name, count|
        pct = total > 0 ? (count.to_f / total * 100).round(1) : 0
        lines << "  - #{status_name}: #{count} (#{pct}%)"
      end
      lines.join("\n")
    end

    def format_overdue_issues(issues)
      return '(无逾期任务)' if issues.blank?

      issues.map do |i|
        ver_str = i[:fixed_version] ? " 版本:#{i[:fixed_version]}" : ""
        "- #{issue_link(i[:id])} #{i[:subject]} [#{i[:status]}] 进度:#{i[:done_ratio]}% 截止:#{i[:due_date]}#{ver_str} (#{i[:project]})"
      end.join("\n")
    end
  end
end
