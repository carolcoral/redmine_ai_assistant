# frozen_string_literal: true

module AiAssistant
  module Mixins
    # 提供给其他 Redmine 插件的 AI 能力混入模块
    #
    # == 使用方式
    #
    # 在你的插件中：
    #
    #   require 'ai_assistant/mixins/ai_capable'
    #
    #   class MyPluginController < ApplicationController
    #     include AiAssistant::Mixins::AiCapable
    #
    #     def analyze
    #       result = ai_chat("分析 #{Issue.find(params[:id]).subject}")
    #       if result[:error]
    #         render json: { error: result[:error] }, status: :unprocessable_entity
    #       else
    #         render json: { analysis: result[:content] }
    #       end
    #     end
    #   end
    #
    # == 提供的实例方法
    #
    # - ai_chat(message, **options)          -> 发送一条消息
    # - ai_chat_messages(messages, **options) -> 发送多轮消息（原始格式）
    # - ai_chat_stream(message, **options, &block) -> 流式对话
    # - ai_ready?                             -> 检查 AI 是否可用
    #
    # options 中可指定：
    #   :provider     -> 服务商 ID 或 AiProvider 实例（可选）
    #   :model        -> 模型名（可选）
    #   :temperature  -> 温度 0.0～2.0
    #   :max_tokens   -> 最大 token 数
    #   :timeout      -> 超时秒数（默认 120）
    #   :system       -> 系统提示词
    #
    module AiCapable
      extend ActiveSupport::Concern

      # 发送单条消息给 AI
      #
      # @param message [String] 用户消息文本
      # @param options [Hash]
      # @return [Hash] { content:, model:, tokens_used: } 或 { error: }
      def ai_chat(message, **options)
        messages = build_messages_from_options(message, options)
        client   = build_client(options)
        client.chat(messages, **client_options(options))
      end

      # 发送多轮消息（原始 messages 格式）
      #
      # @param messages [Array<Hash>] [{ role:, content: }, ...]
      # @param options  [Hash]
      # @return [Hash] { content:, model:, tokens_used: } 或 { error: }
      def ai_chat_messages(messages, **options)
        client = build_client(options)
        client.chat(messages, **client_options(options))
      end

      # 流式对话
      #
      # @param message [String]
      # @param options [Hash]
      # @yield [Hash] 每个数据块 { content:, ... } 或 { done: true }
      def ai_chat_stream(message, **options, &block)
        messages = build_messages_from_options(message, options)
        client   = build_client(options)
        client.chat_stream(messages, **client_options(options), &block)
      end

      # 检查 AI 功能是否可用
      def ai_ready?
        AiAssistant.ready?
      end

      private

      def build_messages_from_options(message, options)
        msgs = []
        msgs << { role: 'system', content: options[:system] } if options[:system].present?
        msgs << { role: 'user', content: message }
        msgs
      end

      def build_client(options)
        AiAssistant::Client.new(
          provider: options[:provider],
          model:    options[:model]
        )
      end

      def client_options(options)
        options.slice(:temperature, :max_tokens, :timeout, :open_timeout)
      end
    end
  end
end
