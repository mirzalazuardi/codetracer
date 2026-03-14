# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_locale
  after_action :log_request

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  def authenticate_user!
    redirect_to login_path unless current_user
  end

  def set_locale
    I18n.locale = current_user&.locale || I18n.default_locale
  end

  def log_request
    Rails.logger.info("Request completed: #{request.path}")
  end

  def record_not_found
    render json: { error: 'Record not found' }, status: :not_found
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
