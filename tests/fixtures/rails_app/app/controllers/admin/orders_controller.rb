# frozen_string_literal: true

module Admin
  class OrdersController < ApplicationController
    before_action :require_admin
    before_action :set_order, only: [:show, :update, :force_refund]

    def index
      @orders = Order.includes(:user, :items).recent
      render json: @orders
    end

    def show
      render json: @order
    end

    def update
      if @order.update(order_params)
        render json: @order
      else
        render json: { errors: @order.errors }, status: :unprocessable_entity
      end
    end

    def force_refund
      result = AdminRefundService.call(@order, current_user, force: true)
      if result.success?
        AdminNotificationJob.perform_async('force_refund', @order.id, current_user.id)
        render json: { status: 'force_refunded' }
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    end

    private

    def require_admin
      render json: { error: 'Admin required' }, status: :forbidden unless current_user&.admin?
    end

    def set_order
      @order = Order.find(params[:id])
    end

    def order_params
      params.require(:order).permit(:status, :notes)
    end
  end
end
