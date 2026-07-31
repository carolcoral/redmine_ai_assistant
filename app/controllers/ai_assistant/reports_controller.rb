# frozen_string_literal: true

module AiAssistant
  class ReportsController < ApplicationController
    before_action :require_login

    accept_api_auth :generate

    def daily
      render json: generate_report('daily')
    end

    def weekly
      render json: generate_report('weekly')
    end

    def monthly
      render json: generate_report('monthly')
    end

    def generate
      report_type = params[:report_type] || 'daily'

      render json: generate_report(report_type)
    end

    private

    def generate_report(report_type)
      timezone = Setting.plugin_redmine_ai_assistant.try(:[], 'report_timezone')
      provider_id = params[:provider_id] ||
                    Setting.plugin_redmine_ai_assistant.try(:[], 'default_provider_id')
      period_offset = params[:period_offset]

      generator = ReportGenerator.new(
        User.current,
        report_type:    report_type,
        timezone:       timezone,
        provider_id:    provider_id,
        period_offset:  period_offset
      )

      result = generator.generate

      if result[:error]
        { error: result[:error] }
      else
        {
          report_type: report_type,
          content:     result[:content],
          tokens_used: result[:tokens_used]
        }
      end
    rescue ArgumentError => e
      { error: e.message }
    rescue StandardError => e
      Rails.logger.error "Report Generation Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { error: "报告生成失败: #{e.message}" }
    end
  end
end
