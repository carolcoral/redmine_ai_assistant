# frozen_string_literal: true

module AiAssistant
  class ProvidersController < AdminController
    before_action :find_provider, only: [:edit, :update, :destroy, :toggle]

    require_sudo_mode for: [:create, :update, :destroy]

    self.main_menu = false

    def index
      @providers = AiProvider.ordered
    end

    def new
      @provider = AiProvider.new(provider_type: 'custom')
    end

    def create
      @provider = AiProvider.new(provider_params)
      @provider.is_builtin = false

      if @provider.save
        flash[:notice] = l(:notice_successful_create)
        redirect_to action: :index
      else
        render :new
      end
    end

    def edit; end

    def update
      update_params = provider_params
      # 编辑时 API Key 留空则保留原值，避免空字符串覆盖已加密的密钥
      update_params = update_params.except(:api_key) if update_params[:api_key].blank?
      if @provider.update(update_params)
        flash[:notice] = l(:notice_successful_update)
        redirect_to action: :index
      else
        render :edit
      end
    end

    def destroy
      @provider.destroy
      flash[:notice] = l(:notice_successful_delete)
      redirect_to action: :index
    end

    def toggle
      @provider.update(is_enabled: !@provider.is_enabled)
      redirect_to action: :index
    end

    # POST /ai_providers/fetch_models
    # 根据前端传来的 api_url / api_key 获取可用模型列表
    # 编辑场景下 api_key 可留空，通过 provider_id 回退到已保存的密钥
    def fetch_models
      api_url  = params[:api_url].to_s.strip
      api_key  = params[:api_key].to_s.strip
      provider_id = params[:provider_id].to_i

      if api_key.blank? && provider_id > 0
        saved_provider = AiProvider.find_by(id: provider_id)
        api_key = saved_provider&.api_key.to_s
      end

      if api_url.blank? || api_key.blank?
        render json: { error: l(:error_api_url_key_required) }, status: :bad_request
        return
      end

      # 用临时 provider 实例请求模型列表
      temp_provider = AiProvider.new(api_url: api_url, api_key: api_key)
      models, err = temp_provider.fetch_remote_models

      if err
        render json: { error: err }, status: :unprocessable_entity
      else
        render json: { models: models }
      end
    end

    private

    def find_provider
      @provider = AiProvider.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def provider_params
      params.require(:ai_assistant_ai_provider).permit(
        :name, :slug, :api_url, :api_key,
        :default_model, :available_models, :settings, :is_enabled, :position
      )
    end
  end
end
