# frozen_string_literal: true

module AiAssistant
  class AiMessage < ActiveRecord::Base
    self.table_name = 'ai_messages'

    belongs_to :user
    belongs_to :ai_provider, class_name: 'AiAssistant::AiProvider', optional: true

    # ========== 验证 ==========
    validates :content, :role, :conversation_id, presence: true
    validates :role, inclusion: { in: %w[system user assistant] }

    # ========== 范围 ==========
    scope :by_conversation, ->(cid) { where(conversation_id: cid).order(created_at: :asc) }
    scope :recent,          -> { order(created_at: :desc) }
    scope :reports,         -> { where.not(report_type: nil) }
    scope :for_user,        ->(user) { where(user_id: user.id) }

    # ========== 方法 ==========
    def report?
      report_type.present?
    end
  end
end
