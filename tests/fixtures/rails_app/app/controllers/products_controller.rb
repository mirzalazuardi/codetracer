# frozen_string_literal: true

class ProductsController < ApplicationController
  before_action :set_product, only: [:show, :update]

  def index
    @products = Product.all
    render json: @products
  end

  def show
    render json: @product
  end

  def create
    validate_input(params)
    @product = build_product(params)

    if @product.save
      notify_inventory(@product)
      render json: @product, status: :created
    else
      render json: @product.errors, status: :unprocessable_entity
    end
  end

  def update
    validate_input(params)

    if @product.update(product_params)
      recalculate_pricing(@product)
      render json: @product
    else
      render json: @product.errors, status: :unprocessable_entity
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(:name, :price, :category)
  end

  def validate_input(input)
    check_required_fields(input)
    sanitize_values(input)
  end

  def check_required_fields(input)
    raise ArgumentError, "Name required" unless input[:name].present?
  end

  def sanitize_values(input)
    input[:name] = input[:name].strip if input[:name]
  end

  def build_product(input)
    Product.new(product_params)
  end

  def notify_inventory(product)
    InventoryService.update(product)
  end

  def recalculate_pricing(product)
    apply_discounts(product)
    update_tax(product)
    PricingService.recalculate(product)
  end

  def apply_discounts(product)
    # Apply any applicable discounts
  end

  def update_tax(product)
    # Update tax calculations
  end
end
