class ApplicationController < ActionController::API
  include ApiErrors
  include Pagination

  before_action :authenticate_api_key!
  before_action :validate_json_body!

  private

  def authenticate_api_key!
    expected = ENV['API_KEY'].to_s
    if expected.strip.empty?
      render_error(:service_unavailable, 'authentication_unavailable', 'API authentication is not configured.')
      return
    end

    token = request.authorization.to_s.match(/\ABearer ([^\s]+)\z/)&.captures&.first
    return if token && ActiveSupport::SecurityUtils.secure_compare(expected, token)

    response.set_header('WWW-Authenticate', 'Bearer')
    render_error(:unauthorized, 'unauthorized', 'A valid Bearer API key is required.')
  end

  def validate_json_body!
    request.request_parameters if request.content_mime_type == Mime[:json]
  end
end
