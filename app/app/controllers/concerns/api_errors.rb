module ApiErrors
  extend ActiveSupport::Concern

  included do
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from ActionController::BadRequest, with: :bad_request
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :invalid_json
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :validation_failed
    rescue_from PaginationParams::Invalid, with: :invalid_pagination
  end

  private

  def render_error(status, code, message)
    render json: { error: { code: code, message: message } }, status: status
  end

  def bad_request
    render_error(:bad_request, 'bad_request', 'Required parameters are missing or invalid.')
  end

  def invalid_json
    render_error(:bad_request, 'invalid_json', 'The request body must contain valid JSON.')
  end

  def not_found
    render_error(:not_found, 'not_found', 'The requested resource was not found.')
  end

  def validation_failed
    render_error(:unprocessable_content, 'validation_failed', 'The resource could not be validated.')
  end

  def invalid_pagination
    render_error(:bad_request, 'invalid_pagination', 'page must be positive; per_page must be between 1 and 100.')
  end
end
