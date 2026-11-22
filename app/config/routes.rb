Rails.application.routes.draw do
  get '/up', to: 'health#live'
  get '/ready', to: 'health#ready'

  namespace :api do
    namespace :v1 do
      get '/status', to: 'status#show'
      resources :customers, only: %i[index show create] do
        resources :invoices, only: :index
        get :balance, to: 'balances#show'
      end
      resources :plans, only: %i[index show create]
      resources :subscriptions, only: %i[show create] do
        post :cancel, on: :member
        resources :invoices, only: :create
      end
      resources :usage_events, only: :create
      resources :invoices, only: :show
    end
  end

  root 'errors#not_found'
  match '*path', to: 'errors#not_found', via: :all
end
