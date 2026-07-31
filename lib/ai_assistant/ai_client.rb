# frozen_string_literal: true

require 'net/http'
require 'json'

module AiAssistant
  # ---- 向后兼容包装 ----
  # 原有 AiClient 类保留为 Client 的别名，确保已有调用代码不受影响。
  # 新代码请使用 AiAssistant.chat / AiAssistant.client 等 API。
  class AiClient < Client
    # 保留原有初始化签名 -- 第一个参数可以是 provider 实例
    def initialize(provider = nil, model: nil)
      super(provider: provider, model: model)
    end

    # 保留原有的 default_provider 类方法
    def self.default_provider
      AiProvider.enabled.ordered.first
    end
  end
end
