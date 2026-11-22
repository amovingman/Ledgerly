if Rails.env.benchmark?
  require Rails.root.join('lib/ledgerly_benchmark/safety')
  require Rails.root.join('lib/ledgerly_benchmark/metrics')
  LedgerlyBenchmark::Safety.check!
  Rails.application.config.middleware.use LedgerlyBenchmark::Metrics

  # SDK API-base options do not inherit the global Stripe.api_base setting.
  # Override only this isolated environment; preserve the actual SDK and HTTP path.
  Rails.application.config.after_initialize do
    StripeIntegration::Gateway.prepend(Module.new do
      private

      def client_options
        super.merge(api_base: 'http://benchmark-provider:4242')
      end
    end)
  end
end
