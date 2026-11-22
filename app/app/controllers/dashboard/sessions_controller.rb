module Dashboard
  class SessionsController < BaseController
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: lambda {
                 render plain: 'Too many sign-in attempts. Try again in three minutes.', status: :too_many_requests
               }

    def new
      return redirect_to dashboard_path if authenticated?

      render 'dashboard/login'
    end

    def create
      return unavailable if ENV['API_KEY'].blank?
      return rejected unless valid_key?

      establish_session
      redirect_to dashboard_path, status: :see_other
    end

    def destroy
      reset_session
      redirect_to dashboard_login_path, status: :see_other
    end

    private

    def establish_session
      reset_session
      session[:dashboard_key] = Digest::SHA256.hexdigest(ENV['API_KEY'].to_s)
      session[:dashboard_expires_at] = 30.minutes.from_now.to_i
    end

    def valid_key?
      supplied = params[:password]
      supplied.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(ENV['API_KEY'].to_s, supplied)
    end

    def rejected
      @error = 'That access key was not recognized.'
      render 'dashboard/login', status: :unauthorized
    end

    def unavailable
      @error = 'Dashboard access is not configured for this instance.'
      render 'dashboard/login', status: :service_unavailable
    end
  end
end
