# frozen_string_literal: true

require_relative 'ai_assistant/client'

module AiAssistant
  PLUGIN_NAME = :redmine_ai_assistant

  # ==================================================================
  # 统一 AI 能力层 -- Redmine 系统 AI 功能核心枢纽
  #
  # 外部插件可通过以下方式接入：
  #
  #   # 方式 1：模块级 API（推荐，零配置）
  #   result = AiAssistant.chat("Hello")
  #   result = AiAssistant.chat_messages([{role: "user", content: "Hello"}])
  #
  #   # 方式 2：Mixin 混入
  #   include AiAssistant::Mixins::AiCapable
  #   result = ai_chat("Hello")
  #
  #   # 方式 3：获取 Client 实例（高级用法）
  #   client = AiAssistant.client(provider: my_provider)
  #   client.chat(messages)
  # ==================================================================

  class << self
    # ---- 状态查询 ----

    # 检查插件是否启用（用户已登录 + 设置中 enabled == '1'）
    def enabled?
      User.current&.logged? &&
        Setting.plugin_redmine_ai_assistant&.dig('enabled') == '1'
    end

    # 检查 AI 是否就绪（已启用且有可用服务商）
    def ready?
      enabled? && AiProvider.enabled.exists?
    end

    # 返回当前可用的服务商列表
    def available_providers
      AiProvider.enabled.ordered
    end

    # 返回默认服务商（设置中指定或第一个启用的）
    def default_provider
      provider_id = Setting.plugin_redmine_ai_assistant&.dig('default_provider_id')
      provider_id.present? ? AiProvider.enabled.find_by(id: provider_id) : AiProvider.enabled.ordered.first
    end

    # ---- 对话 API ----

    # 发送单条消息给 AI（无历史上下文）
    #
    # @param message [String] 用户消息
    # @param options [Hash]
    #   :provider    - 指定服务商（ID 或 AiProvider 实例）
    #   :model       - 指定模型名
    #   :temperature - 采样温度（默认 0.7）
    #   :max_tokens  - 最大输出 token 数（默认 4096）
    #   :timeout     - 请求超时秒数（默认 120）
    #   :system      - 系统提示词
    #   :linkify     - 是否转换 #ID 为链接（默认 true）
    #
    # @return [Hash]
    #   成功: { content:, role:, model:, tokens_used:, prompt_tokens:, completion_tokens: }
    #   失败: { error: "..." }
    #
    # @example
    #   AiAssistant.chat("分析问题 #123")
    #   AiAssistant.chat("Hello", temperature: 0.3, max_tokens: 2048)
    def chat(message, **options)
      system_msg = options.delete(:system)
      messages = []
      messages << { role: 'system', content: system_msg } if system_msg.present?
      messages << { role: 'user', content: message }
      chat_messages(messages, **options)
    end

    # 发送多轮消息（原始 messages 格式，适用于有历史上下文）
    #
    # @param messages [Array<Hash>] [{ role:, content: }, ...]
    # @param options  [Hash] 同 chat 方法
    # @return [Hash] 同 chat 方法
    #
    # @example
    #   AiAssistant.chat_messages([
    #     { role: "system", content: "You are a helpful assistant." },
    #     { role: "user",   content: "什么是敏捷开发？" }
    #   ])
    def chat_messages(messages, **options)
      client = build_client(options)
      client_opts = extract_client_options(options)
      client.chat(messages, **client_opts)
    end

    # 流式对话（SSE 逐 block 回调）
    #
    # @param message [String]
    # @param options [Hash] 同 chat 方法
    # @yield [Hash] 每个数据块
    #   { content: "部分文本" } -- 增量内容
    #   { done: true }          -- 流结束
    #
    # @example
    #   AiAssistant.chat_stream("写一首诗") do |chunk|
    #     if chunk[:done]
    #       puts "\n--- finished ---"
    #     else
    #       print chunk[:content]
    #     end
    #   end
    def chat_stream(message, **options, &block)
      system_msg = options.delete(:system)
      messages = []
      messages << { role: 'system', content: system_msg } if system_msg.present?
      messages << { role: 'user', content: message }

      client = build_client(options)
      client_opts = extract_client_options(options)
      client.chat_stream(messages, **client_opts, &block)
    end

    # ---- Client 实例化 ----

    # 获取配置好的 Client 实例（高级用法）
    #
    # @param config [Hash]
    #   :provider, :model, :temperature, :max_tokens, :timeout, :linkify
    # @return [AiAssistant::Client]
    def client(**config)
      Client.new(**config)
    end

    private

    def build_client(options)
      Client.new(
        provider: options[:provider],
        model:    options[:model]
      )
    end

    def extract_client_options(options)
      options.slice(:temperature, :max_tokens, :timeout, :open_timeout, :linkify)
    end
  end
end
