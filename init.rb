# frozen_string_literal: true

# 将插件 lib 目录加入 Ruby 加载路径
plugin_lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(plugin_lib) unless $LOAD_PATH.include?(plugin_lib)

require 'ai_assistant'
require 'ai_assistant/client'
require 'ai_assistant/ai_client'
require 'ai_assistant/guard_prompt'
require 'ai_assistant/report_generator'
require 'ai_assistant/hooks'
require 'ai_assistant/mixins/ai_capable'

Redmine::Plugin.register :redmine_ai_assistant do
  name 'Redmine AI Assistant'
  author 'carolcoral'
  description 'Redmine 统一 AI 能力核心枢纽 -- AI-powered intelligent ' \
              'assistant with chat, report generation, mixin API for other plugins, ' \
              'and multi-provider provider support.'
  version '1.1.0'
  url 'https://cnb.cool/xindu.site/redmine'
  author_url 'https://xindu.site'

  requires_redmine version_or_higher: '6.1.0'

  # ========== 权限 ==========
  permission :manage_ai_providers, {
    ai_assistant_providers: [:index, :new, :create, :edit, :update, :destroy, :toggle]
  }, require: :admin

  permission :use_ai_chat, {
    ai_assistant_chat: [:send_message, :history]
  }, require: :loggedin

  permission :generate_ai_reports, {
    ai_assistant_reports: [:daily, :weekly, :monthly, :generate]
  }, require: :loggedin

  permission :view_ai_stats, {
    ai_assistant_stats: [:index]
  }, require: :admin

  # ========== 管理菜单 ==========
  menu :admin_menu,
       :ai_assistant_providers,
       { controller: 'ai_assistant/providers', action: 'index' },
       caption: :label_ai_providers,
       icon: 'openai',
       plugin: 'redmine_ai_assistant',
       if: proc { User.current.admin? && AiAssistant.enabled? }

  menu :admin_menu,
       :ai_assistant_stats,
       { controller: 'ai_assistant/stats', action: 'index' },
       caption: :label_ai_usage_stats,
       icon: 'stats',
       plugin: 'redmine_ai_assistant',
       if: proc { User.current.admin? && AiAssistant.enabled? }

  # ========== 插件设置 ==========
  settings default: {
    'enabled' => '0',
    'default_provider_id' => '',
    'guard_prompt_enabled' => '1',
    'system_prompt' => '',
    'max_history_messages' => '20',
    'report_timezone' => '',
    'custom_pet_image_url' => '',
    'pet_size' => '60'
  }, partial: 'settings/redmine_ai_assistant'
end
