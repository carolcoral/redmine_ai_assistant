# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  # AI 服务商管理（仅管理员）
  scope module: 'ai_assistant' do
    resources :ai_providers, controller: 'providers', as: 'ai_assistant_providers' do
      member do
        put :toggle
      end
      collection do
        post :fetch_models
      end
    end
  end

  # AI 聊天 API
  namespace :ai_assistant do
    post 'chat/send_message', to: 'chat#send_message'
    get  'chat/history',     to: 'chat#history'
    get  'chat/clear',       to: 'chat#clear'

    # 工作报告生成
    get  'reports/daily',    to: 'reports#daily'
    get  'reports/weekly',   to: 'reports#weekly'
    get  'reports/monthly',  to: 'reports#monthly'
    post 'reports/generate', to: 'reports#generate'

    # 用量统计（仅管理员）
    get  'stats',   to: 'stats#index'
    get  'stats/export', to: 'stats#export'
  end
end
