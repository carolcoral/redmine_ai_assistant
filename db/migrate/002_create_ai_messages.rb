# frozen_string_literal: true

class CreateAiMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_messages do |t|
      t.references :user,        null: false
      t.references :ai_provider
      t.string     :conversation_id,  null: false  # UUID for grouping messages
      t.string     :role,             null: false  # system, user, assistant
      t.text       :content,          null: false
      t.string     :model                        # model used for this message
      t.integer    :tokens_used,     default: 0
      t.string     :report_type                  # daily, weekly, monthly (when generated as report)

      t.timestamps
    end

    add_index :ai_messages, :conversation_id
    add_index :ai_messages, [:user_id, :created_at]
    add_index :ai_messages, :report_type
  end
end
