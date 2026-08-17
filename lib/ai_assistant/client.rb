# frozen_string_literal: true

require 'net/http'
require 'json'

module AiAssistant
  # 统一 AI 客户端 -- 插件核心能力层
  #
  # 封装所有服务商对接细节（认证、端点拼接、参数注入、响应解析、
  # 错误处理、issue 链接转换等），对外仅暴露统一的对话接口。
  #
  # 外部插件应使用 AiAssistant.chat / AiAssistant.chat_messages
  # 等模块级方法，无需直接实例化本类。
  class Client
    DEFAULT_TEMPERATURE = 0.7
    DEFAULT_MAX_TOKENS  = 4096
    DEFAULT_TIMEOUT     = 120
    DEFAULT_OPEN_TIMEOUT = 10

    attr_reader :provider, :model, :config

    # @param config [Hash]
    #   :provider   - 指定 AiProvider 实例或 ID（可选，默认取启用的第一个）
    #   :model      - 指定模型名（可选，默认取 provider.default_model）
    #   :temperature, :max_tokens, :timeout, :open_timeout
    def initialize(**config)
      @config   = build_config(config)
      @provider = resolve_provider(@config[:provider])
      @model    = @config[:model] || @provider.default_model

      raise ArgumentError, 'No AI provider configured or enabled' if @provider.nil?
      raise ArgumentError, 'AI provider is missing API key (please contact administrator)' if @provider.api_key.blank?
    end

    # ========== 公共接口 ==========

    # 发送对话请求，返回标准化结果 Hash
    #
    # @param messages [Array<Hash>] [{ role:, content: }, ...]
    # @param options  [Hash] 覆盖初始化参数
    # @return [Hash]
    #   成功: { content:, role:, model:, tokens_used:, prompt_tokens:, completion_tokens: }
    #   失败: { error: "..." }
    def chat(messages, **options)
      merged = @config.merge(options)
      body   = build_request_body(messages, merged)
      uri    = URI(@provider.chat_endpoint)

      http = build_http(uri, merged)
      request = build_request(uri, body)

      response = http.request(request)
      parse_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout
      { error: 'AI 服务请求超时，请稍后重试' }
    rescue StandardError => e
      { error: "AI 服务异常: #{e.message}" }
    end

    # 流式对话，每收到一个 chunk 回调一次
    #
    # @yield [Hash] 每个数据块 { content:, ... } 或 { done: true }
    def chat_stream(messages, **options, &block)
      return enum_for(:chat_stream, messages, **options) unless block

      merged = @config.merge(options)
      body   = build_request_body(messages, merged).merge(stream: true)
      uri    = URI(@provider.chat_endpoint)

      http = build_http(uri, merged.merge(timeout: merged[:timeout] || 300))
      request = build_request(uri, body)

      http.request(request) do |response|
        check_stream_error(response)
        response.read_body do |chunk|
          parse_sse_chunks(chunk).each do |data|
            break if data[:done]

            yield data if block
          end
        end
      end
    end

    # ========== 类方法快捷入口 ==========

    # 解析当前默认或指定 provider
    def self.resolve(provider_id = nil)
      if provider_id.present?
        AiProvider.enabled.find_by(id: provider_id)
      end || AiProvider.enabled.ordered.first
    end

    # ========== 私有实现 ==========

    private

    def build_config(user_config)
      {
        temperature:    DEFAULT_TEMPERATURE,
        max_tokens:     DEFAULT_MAX_TOKENS,
        timeout:        DEFAULT_TIMEOUT,
        open_timeout:   DEFAULT_OPEN_TIMEOUT,
        provider:       nil,
        model:          nil,
        linkify_issues: true
      }.merge(user_config.compact)
    end

    def resolve_provider(explicit)
      return explicit if explicit.is_a?(AiProvider)
      return AiProvider.enabled.find_by(id: explicit) if explicit.present?

      self.class.resolve
    end

    def build_http(uri, options)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl      = uri.scheme == 'https'
        http.open_timeout = options[:open_timeout]
        http.read_timeout = options[:timeout]
      end
    end

    def build_request(uri, body)
      Net::HTTP::Post.new(uri.path, @provider.headers).tap do |req|
        req.body = body.to_json
      end
    end

    def build_request_body(messages, options)
      body = {
        model:       @model,
        messages:    messages,
        stream:      false,
        temperature: options[:temperature],
        max_tokens:  options[:max_tokens]
      }

      # 注入 provider 特定参数（如 top_p 等）
      extra = @provider.extra_settings
      param_keys = extra.select { |k, _v| k.start_with?('param_') }
      body.merge!(param_keys.transform_keys { |k| k.to_s.sub('param_', '').to_sym })

      body
    end

    # ========== 响应解析 ==========

    def parse_response(response)
      case response.code.to_i
      when 200
        parse_success(response)
      when 401
        { error: 'AI 服务认证失败，请检查 API Key 配置' }
      when 429
        { error: 'AI 服务请求过于频繁，请稍后重试' }
      when 500..599
        { error: "AI 服务异常 (#{response.code})，请稍后重试" }
      else
        data = JSON.parse(response.body) rescue {}
        { error: data['error']&.[]('message') || "AI 服务返回异常 (#{response.code})" }
      end
    end

    def parse_success(response)
      data   = JSON.parse(response.body)
      choice = data.dig('choices', 0, 'message')
      usage  = data['usage'] || {}

      {
        content:           maybe_linkify(choice['content']),
        role:              choice['role'],
        model:             data['model'],
        tokens_used:       usage['total_tokens'] || 0,
        prompt_tokens:     usage['prompt_tokens'] || 0,
        completion_tokens: usage['completion_tokens'] || 0
      }
    end

    # ========== 流式响应解析 (SSE) ==========

    def parse_sse_chunks(raw)
      results = []
      raw.to_s.split(/\n\n/).each do |block|
        block.strip.lines.each do |line|
          line = line.strip
          next if line.empty? || line == 'data: [DONE]'
          next unless line.start_with?('data: ')

          json_str = line.sub(/^data:\s*/, '')
          begin
            data = JSON.parse(json_str)
            choice = data.dig('choices', 0)
            finish = choice&.dig('finish_reason')
            if finish && finish != 'null'
              results << { done: true, finish_reason: finish }
            else
              delta = choice&.dig('delta', 'content')
              results << { content: delta } if delta
            end
          rescue JSON::ParserError
            next
          end
        end
      end
      results
    end

    def check_stream_error(response)
      code = response.code.to_i
      return if code == 200

      raise "AI stream error (HTTP #{code})"
    end

    # ========== Issue 链接处理 ==========

    def maybe_linkify(content)
      return content unless @config[:linkify_issues]
      return content if content.blank?

      content.gsub(/(?<!\[)#(\d+)(?!\d)(?!\]\()/) do |_match|
        issue_id = $1
        "[##{issue_id}](#{issue_url(issue_id)})"
      end
    end

    def issue_url(issue_id)
      "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue_id}"
    end
  end
end
