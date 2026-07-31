# frozen_string_literal: true

class CreateAiProviders < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_providers do |t|
      t.string  :name,            null: false
      t.string  :slug,            null: false
      t.string  :provider_type,   null: false  # openai, glm, minimax, kimi, deepseek, custom
      t.string  :api_url,         null: false
      t.text    :api_key,         null: false  # encrypted
      t.string  :default_model,   null: false
      t.text    :available_models              # JSON array of model names
      t.text    :settings                      # JSON extra settings
      t.boolean :is_enabled,      null: false, default: true
      t.boolean :is_builtin,      null: false, default: false
      t.integer :position,        null: false, default: 0

      t.timestamps
    end

    add_index :ai_providers, :slug, unique: true
    add_index :ai_providers, :is_enabled
    add_index :ai_providers, :position

    # 注：不再内置服务商，所有服务商由管理员通过下拉菜单创建
  end
end
