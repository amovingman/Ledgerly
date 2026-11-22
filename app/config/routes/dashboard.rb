get '/dashboard/login', to: 'dashboard/sessions#new', as: :dashboard_login
post '/dashboard/session', to: 'dashboard/sessions#create', as: :dashboard_session
delete '/dashboard/session', to: 'dashboard/sessions#destroy'
post '/dashboard/logout', to: 'dashboard/sessions#destroy', as: :dashboard_logout
get '/dashboard', to: 'dashboard/pages#show', as: :dashboard
get '/dashboard/data/invoices/:id', to: 'dashboard/data#invoice'
get '/dashboard/data/customers/:id', to: 'dashboard/data#customer'
get '/dashboard/data/webhooks/:id', to: 'dashboard/data#webhook'
get '/dashboard/data/:section', to: 'dashboard/data#index', defaults: { format: :json }
