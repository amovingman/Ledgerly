require 'rails_helper'

RSpec.describe StripeIntegration::Settings do
  describe '.secret_key!' do
    %w[sk_test_example rk_test_example rkcs_test_example].each do |key|
      it "accepts the #{key.split('_').first} test-key format" do
        stub_const('ENV', ENV.to_h.merge('STRIPE_SECRET_KEY' => key))
        expect(described_class.secret_key!).to eq(key)
      end
    end

    ['', 'sk_live_example', 'rk_live_example', 'rkcs_live_example', 'sk_test_example\n'].each do |key|
      it "rejects unsupported credentials #{key.inspect}" do
        stub_const('ENV', ENV.to_h.merge('STRIPE_SECRET_KEY' => key))
        expect { described_class.secret_key! }.to raise_error(Billing::Error) do |error|
          expect(error.code).to eq('stripe_unavailable')
        end
      end
    end
  end
end
