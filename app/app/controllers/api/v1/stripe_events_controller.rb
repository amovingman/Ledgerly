module Api
  module V1
    class StripeEventsController < BaseController
      def show
        event = StripeEvent.find_by!(stripe_id: params.expect(:stripe_id))
        render json: { data: event.slice(:stripe_id, :event_type, :api_version, :status, :attempts, :last_error,
                                         :processed_at, :created_at) }
      end
    end
  end
end
