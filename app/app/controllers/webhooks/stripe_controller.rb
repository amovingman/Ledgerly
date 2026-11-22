module Webhooks
  class StripeController < ActionController::API
    include ApiErrors

    def create
      result = StripeIntegration::ReceiveEvent.call(raw: request.raw_post,
                                                    signature: request.headers['Stripe-Signature'])
      StripeIntegration::OutboxDispatcher.call(record_id: result.record.outbox_record.id)
      render json: { received: true, duplicate: result.replayed }
    end
  end
end
