# frozen_string_literal: true

module AiAssistant
  # 全局页面钩子 -- 在所有页面底部注入 AI 聊天组件
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_body_bottom(context)
      return unless AiAssistant.enabled?

      context[:controller].send(:render_to_string,
                                partial: 'ai_assistant/chat/widget',
                                locals: context)
    end

    def view_layouts_base_html_head(context)
      return unless AiAssistant.enabled?

      context[:controller].send(:render_to_string,
                                partial: 'ai_assistant/chat/head_tags',
                                locals: context)
    end
  end
end
