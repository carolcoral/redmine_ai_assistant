# frozen_string_literal: true

require 'csv'

module AiAssistant
  class StatsController < AdminController
    helper :sort
    include SortHelper

    before_action :compute_stats, only: [:index, :export]

    def index
    end

    def export
      respond_to do |format|
        format.csv { send_data generate_csv, filename: "ai_usage_stats_#{@today}.csv", type: 'text/csv; header=present' }
        format.pdf do
          pdf_data = generate_pdf
          send_data pdf_data, filename: "ai_usage_stats_#{@today}.pdf", type: 'application/pdf', disposition: 'attachment'
        end
      end
    end

    private

    def compute_stats
      # 时间范围边界
      @today        = Date.current
      @today_start  = @today.beginning_of_day
      @week_start   = @today.beginning_of_week.beginning_of_day
      @month_start  = @today.beginning_of_month.beginning_of_day

      base = AiMessage.where(role: 'assistant')

      # ========== 系统总统计 ==========
      @sys_total_calls   = base.count
      @sys_total_tokens  = base.sum(:tokens_used) || 0

      @sys_daily_calls   = base.where('created_at >= ?', @today_start).count
      @sys_daily_tokens  = base.where('created_at >= ?', @today_start).sum(:tokens_used) || 0

      @sys_weekly_calls  = base.where('created_at >= ?', @week_start).count
      @sys_weekly_tokens = base.where('created_at >= ?', @week_start).sum(:tokens_used) || 0

      @sys_monthly_calls = base.where('created_at >= ?', @month_start).count
      @sys_monthly_tokens = base.where('created_at >= ?', @month_start).sum(:tokens_used) || 0

      # ========== 用户维度统计 ==========
      user_rows = base.group(:user_id).pluck(
        Arel.sql('user_id'),
        Arel.sql('COUNT(*)'),
        Arel.sql('COALESCE(SUM(tokens_used), 0)'),
        Arel.sql('MAX(created_at)')
      )

      daily_rows = base.where('created_at >= ?', @today_start)
                       .group(:user_id)
                       .pluck(Arel.sql('user_id'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(tokens_used), 0)'))
      daily_map = daily_rows.each_with_object({}) { |(uid, c, t), h| h[uid] = [c, t] }

      weekly_rows = base.where('created_at >= ?', @week_start)
                        .group(:user_id)
                        .pluck(Arel.sql('user_id'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(tokens_used), 0)'))
      weekly_map = weekly_rows.each_with_object({}) { |(uid, c, t), h| h[uid] = [c, t] }

      monthly_rows = base.where('created_at >= ?', @month_start)
                         .group(:user_id)
                         .pluck(Arel.sql('user_id'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(tokens_used), 0)'))
      monthly_map = monthly_rows.each_with_object({}) { |(uid, c, t), h| h[uid] = [c, t] }

      user_ids = user_rows.map(&:first).uniq
      users_map = User.where(id: user_ids).index_by(&:id)

      @user_stats = user_rows.map do |uid, total_c, total_t, last_used|
        user = users_map[uid]
        d = daily_map[uid]   || [0, 0]
        w = weekly_map[uid]  || [0, 0]
        m = monthly_map[uid] || [0, 0]

        {
          user:           user,
          total_calls:    total_c,
          total_tokens:   total_t,
          daily_calls:    d[0],
          daily_tokens:   d[1],
          weekly_calls:   w[0],
          weekly_tokens:  w[1],
          monthly_calls:  m[0],
          monthly_tokens: m[1],
          last_used_at:   last_used
        }
      end

      sort_init 'total_calls', 'desc'
      sort_update %w(user total_calls total_tokens daily_calls daily_tokens weekly_calls weekly_tokens monthly_calls monthly_tokens last_used_at)

      sort_key  = @sort_criteria.first_key
      sort_asc  = @sort_criteria.first_asc?

      @user_stats = case sort_key
                    when 'user'
                      @user_stats.sort_by { |s| s[:user]&.name.to_s.downcase }
                    when 'last_used_at'
                      @user_stats.sort do |a, b|
                        va = a[:last_used_at]
                        vb = b[:last_used_at]
                        if va.nil? && vb.nil?
                          0
                        elsif va.nil?
                          1
                        elsif vb.nil?
                          -1
                        else
                          va <=> vb
                        end
                      end
                    else
                      @user_stats.sort_by { |s| s[sort_key.to_sym].to_i }
                    end

      @user_stats.reverse! unless sort_asc
    end

    def generate_csv
      headers = [
        l(:field_user),
        "#{l(:label_ai_stats_total)} #{l(:field_ai_calls)}",
        "#{l(:label_ai_stats_total)} tokens",
        "#{l(:label_ai_stats_today)} #{l(:field_ai_calls)}",
        "#{l(:label_ai_stats_today)} tokens",
        "#{l(:label_ai_stats_this_week)} #{l(:field_ai_calls)}",
        "#{l(:label_ai_stats_this_week)} tokens",
        "#{l(:label_ai_stats_this_month)} #{l(:field_ai_calls)}",
        "#{l(:label_ai_stats_this_month)} tokens",
        l(:label_ai_stats_last_used)
      ]

      CSV.generate(encoding: 'UTF-8') do |csv|
        # 系统汇总
        csv << ["# #{l(:label_ai_usage_stats)} - #{@today}"]
        csv << ["# #{l(:label_ai_stats_total)}: #{@sys_total_calls} #{l(:field_ai_calls)}, #{@sys_total_tokens} tokens"]
        csv << ["# #{l(:label_ai_stats_today)}: #{@sys_daily_calls} #{l(:field_ai_calls)}, #{@sys_daily_tokens} tokens"]
        csv << ["# #{l(:label_ai_stats_this_week)}: #{@sys_weekly_calls} #{l(:field_ai_calls)}, #{@sys_weekly_tokens} tokens"]
        csv << ["# #{l(:label_ai_stats_this_month)}: #{@sys_monthly_calls} #{l(:field_ai_calls)}, #{@sys_monthly_tokens} tokens"]
        csv << []
        csv << headers

        @user_stats.each do |s|
          csv << [
            s[:user]&.name || l(:label_user_unknown),
            s[:total_calls],
            s[:total_tokens],
            s[:daily_calls],
            s[:daily_tokens],
            s[:weekly_calls],
            s[:weekly_tokens],
            s[:monthly_calls],
            s[:monthly_tokens],
            s[:last_used_at]&.strftime('%Y-%m-%d %H:%M:%S')
          ]
        end
      end
    end

    def generate_pdf
      require 'rbpdf'

      pdf = RBPDF.new('L', 'mm', 'A4')
      pdf.set_margins(10, 10, 10)
      pdf.set_auto_page_break(true, 15)
      pdf.add_page

      # 标题
      pdf.set_font('helvetica', 'B', 18)
      pdf.cell(0, 12, "#{l(:label_ai_usage_stats)} - #{@today}", 0, 1, 'C')

      # 时间
      pdf.set_font('helvetica', '', 9)
      pdf.cell(0, 6, l(:label_ai_stats_period_info), 0, 1, 'L')
      pdf.cell(0, 6, l(:label_ai_stats_today) + ': ' + @today.strftime('%Y-%m-%d') +
                     '  |  ' + l(:label_ai_stats_this_week) + ': ' + @today.beginning_of_week.strftime('%Y-%m-%d') + ' ~ ' + @today.strftime('%Y-%m-%d') +
                     '  |  ' + l(:label_ai_stats_this_month) + ': ' + @today.beginning_of_month.strftime('%Y-%m-%d') + ' ~ ' + @today.strftime('%Y-%m-%d'), 0, 1, 'L')

      pdf.ln(4)

      # 系统汇总
      pdf.set_font('helvetica', 'B', 12)
      pdf.cell(0, 8, l(:label_ai_stats_total), 0, 1, 'L')

      sys_headers = [l(:field_ai_calls), 'tokens']
      sys_data = [
        [@sys_total_calls.to_s, @sys_total_tokens.to_s],
        [@sys_daily_calls.to_s, @sys_daily_tokens.to_s],
        [@sys_weekly_calls.to_s, @sys_weekly_tokens.to_s],
        [@sys_monthly_calls.to_s, @sys_monthly_tokens.to_s]
      ]
      sys_labels = [l(:label_ai_stats_total), l(:label_ai_stats_today), l(:label_ai_stats_this_week), l(:label_ai_stats_this_month)]

      pdf.set_font('helvetica', 'B', 9)
      header_names = ['', sys_headers[0], sys_headers[1]]
      col_widths = [40, 30, 30]
      header_names.each_with_index { |h, i| pdf.cell(col_widths[i], 6, h, 1, 0, 'C') }
      pdf.ln

      pdf.set_font('helvetica', '', 9)
      sys_labels.each_with_index do |label, idx|
        pdf.cell(col_widths[0], 6, label, 1, 0, 'L')
        pdf.cell(col_widths[1], 6, sys_data[idx][0], 1, 0, 'R')
        pdf.cell(col_widths[2], 6, sys_data[idx][1], 1, 1, 'R')
      end

      pdf.ln(6)

      # 用户明细表
      pdf.set_font('helvetica', 'B', 12)
      pdf.cell(0, 8, l(:label_ai_stats_user_detail), 0, 1, 'L')

      user_cols = [
        l(:field_user),
        "#{l(:label_ai_stats_total)}\ncalls",
        "#{l(:label_ai_stats_total)}\ntokens",
        "#{l(:label_ai_stats_today)}\ncalls",
        "#{l(:label_ai_stats_today)}\ntokens",
        "#{l(:label_ai_stats_this_week)}\ncalls",
        "#{l(:label_ai_stats_this_week)}\ntokens",
        "#{l(:label_ai_stats_this_month)}\ncalls",
        "#{l(:label_ai_stats_this_month)}\ntokens",
        l(:label_ai_stats_last_used)
      ]
      user_col_widths = [42, 25, 25, 25, 25, 25, 25, 25, 25, 35]

      pdf.set_font('helvetica', 'B', 7)
      user_cols.each_with_index { |h, i| pdf.multi_cell(user_col_widths[i], 7, h, 1, 'C', false, 0, '', '', true, 0, true) }
      pdf.ln

      pdf.set_font('helvetica', '', 7)
      @user_stats.each do |s|
        row = [
          s[:user]&.name || l(:label_user_unknown),
          s[:total_calls].to_s,
          s[:total_tokens].to_s,
          s[:daily_calls].to_s,
          s[:daily_tokens].to_s,
          s[:weekly_calls].to_s,
          s[:weekly_tokens].to_s,
          s[:monthly_calls].to_s,
          s[:monthly_tokens].to_s,
          s[:last_used_at]&.strftime('%m/%d %H:%M') || '-'
        ]
        row.each_with_index { |cell, i| pdf.cell(user_col_widths[i], 5, cell, 1, 0, (i == 0 ? 'L' : 'R')) }
        pdf.ln
      end

      pdf.output
    end

  end
end
