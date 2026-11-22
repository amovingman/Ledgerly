Rails.application.routes.draw do
  get '/up', to: 'health#live'
  get '/ready', to: 'health#ready'
  post '/webhooks/stripe', to: 'webhooks/stripe#create'

  draw :dashboard

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
      resources :invoices, only: :show do
        resource :collection, only: %i[show create], controller: 'stripe_collections'
      end
      get 'stripe_events/:stripe_id', to: 'stripe_events#show'
    end
  end

  root 'errors#not_found'
  match '*path', to: 'errors#not_found', via: :all
end
