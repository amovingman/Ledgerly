Rails.application.routes.draw do
  get '/up', to: 'health#live'
  get '/ready', to: 'health#ready'

  namespace :api do
    namespace :v1 do
      get '/status', to: 'status#show'
    end
  end

  root 'errors#not_found'
  match '*path', to: 'errors#not_found', via: :all
end
