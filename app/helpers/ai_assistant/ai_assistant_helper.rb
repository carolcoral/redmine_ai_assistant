# frozen_string_literal: true

module AiAssistant
  module AiAssistantHelper
    # 注入聊天组件到全局页面
    def ai_chat_widget
      return '' unless User.current.logged?

      render partial: 'ai_assistant/chat/widget'
    end
  end
end
