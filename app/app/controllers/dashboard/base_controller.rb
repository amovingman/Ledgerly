module Dashboard
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    self.forgery_protection_origin_check = true

    before_action :protect_response
    protect_from_forgery with: :exception
    rescue_from ActionController::InvalidAuthenticityToken, with: :expired_form

    private

    def expired_form
      reset_session
      @error = 'This form expired. Sign in again to continue.'
      render 'dashboard/login', status: :unprocessable_content
    end

    def authenticated?
      expected = ENV['API_KEY'].to_s
      fingerprint = session[:dashboard_key].to_s
      expiry = session[:dashboard_expires_at].to_i
      expected.present? && expiry > Time.current.to_i &&
        ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(expected), fingerprint)
    end

    def require_viewer!
      return if authenticated?

      reset_session
      if request.format.json?
        render json: { error: { code: 'session_expired', message: 'Sign in again to continue.' } },
               status: :unauthorized
      else
        redirect_to dashboard_login_path
      end
    end

    def protect_response
      response.set_header('Cache-Control', 'no-store')
      response.set_header('X-Frame-Options', 'DENY')
      response.set_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; " \
                                                     "font-src 'self'; img-src 'self' data:; connect-src 'self'; " \
                                                     "frame-ancestors 'none'; form-action 'self'; base-uri 'none'")
    end
  end
end
