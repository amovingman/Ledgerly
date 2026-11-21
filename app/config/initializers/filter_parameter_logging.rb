Rails.application.config.filter_parameters += %i[
  passw secret token api_key authorization signature card cvc
]
