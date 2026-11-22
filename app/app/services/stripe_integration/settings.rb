# typed: true

module StripeIntegration
  module Settings
    extend T::Sig

    API_VERSION = '2026-11-18.endive'.freeze
    MAX_ATTEMPTS = 8
    MINIMUMS = { 'USD' => 50, 'CAD' => 50, 'EUR' => 50, 'GBP' => 30 }.freeze
    COLLECTION_LIMIT = 99_999_999 # Deliberately conservative application limit, not a Stripe maximum.

    sig { returns(String) }
    def self.secret_key!
      key = ENV['STRIPE_SECRET_KEY'].to_s
      return key if /\A(?:sk|rk|rkcs)_test_[A-Za-z0-9]+\z/.match?(key)

      raise Billing::Error.new('stripe_unavailable', 'Configure a Stripe test-mode secret key.', status: 503)
    end

    sig { returns(String) }
    def self.webhook_secret!
      secret = ENV['STRIPE_WEBHOOK_SECRET'].to_s
      return secret if secret.start_with?('whsec_') && secret.length > 6

      raise Billing::Error.new('webhook_unavailable', 'Configure the Stripe webhook signing secret.', status: 503)
    end
  end
end
