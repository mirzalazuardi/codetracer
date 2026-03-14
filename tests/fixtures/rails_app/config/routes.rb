# frozen_string_literal: true

Rails.application.routes.draw do
  # ── Resourceful routes ─────────────────────────────────────
  resources :orders do
    member do
      post 'refund'
      get 'receipt'
      patch 'cancel'
    end
    collection do
      get 'pending'
      get 'completed'
    end
  end

  resources :users, only: [:index, :show, :create, :update]

  # ── Namespaced routes ──────────────────────────────────────
  namespace :admin do
    resources :orders, only: [:index, :show, :update] do
      member do
        post 'force_refund'
      end
    end
    resources :users
  end

  # ── Direct route mappings ──────────────────────────────────
  post '/checkout', to: 'checkout#create'
  get '/checkout/success', to: 'checkout#success'

  post '/payments/process', to: 'payments#process_payment'
  get '/payments/:id/status', to: 'payments#status'

  # ── Root and misc ──────────────────────────────────────────
  root 'home#index'
  get '/health', to: 'health#check'
end
