# typed: true

module StripeIntegration
  class Operations
    extend T::Sig

    sig { params(gateway: T.untyped).void }
    def initialize(gateway:)
      @gateway = gateway
    end

    # Explicit references keep the persisted request intent auditable.
    # rubocop:disable Metrics/ParameterLists
    sig do
      params(key: String, kind: String, customer: Customer,
             invoice: T.nilable(Invoice), line: T.nilable(InvoiceLineItem),
             payload: StripeIntegration::Types::Parameters).returns(StripeOperation)
    end
    def prepare(key:, kind:, customer:, invoice: nil, line: nil, payload: {})
      StripeOperation.find_or_create_by!(operation_key: key) do |record|
        record.assign_attributes(kind: kind, customer: customer, invoice: invoice, invoice_line_item: line,
                                 idempotency_key: "ledgerly:#{SecureRandom.uuid}")
        record.payload = payload.deep_stringify_keys
        unless kind == 'finalize'
          record.payload['metadata'] =
            record.payload.fetch('metadata',
                                 {}).merge('ledgerly_operation' => record.idempotency_key)
        end
      end
    end

    # rubocop:enable Metrics/ParameterLists

    sig { params(operation: StripeOperation).returns(StripeIntegration::Types::JsonObject) }
    def execute(operation)
      remote = operation.status == 'succeeded' ? retrieve_completed(operation) : perform(operation)
      validate_remote!(operation, remote)
      unless operation.status == 'succeeded'
        operation.update!(remote_id: remote.fetch('id'), status: 'succeeded', completed_at: Time.current)
      end
      remote
    end

    private

    sig { params(operation: StripeOperation).returns(StripeIntegration::Types::JsonObject) }
    def retrieve_completed(operation)
      @gateway.retrieve(operation.kind == 'finalize' ? 'invoice' : operation.kind, operation.remote_id)
    end

    sig { params(operation: StripeOperation).returns(StripeIntegration::Types::JsonObject) }
    def perform(operation)
      previous = operation.first_attempted_at
      operation.update!(first_attempted_at: Time.current) unless previous
      operation.kind == 'finalize' ? finalize(operation) : find_or_create(operation, previous)
    end

    sig { params(operation: StripeOperation, previous: T.nilable(ActiveSupport::TimeWithZone)).returns(StripeIntegration::Types::JsonObject) }
    def find_or_create(operation, previous)
      if previous
        matches = @gateway.list(operation.kind, list_parameters(operation)).select do |remote|
          remote.dig('metadata', 'ledgerly_operation') == operation.idempotency_key
        end
        raise ReviewRequired, 'ambiguous_remote_operation' if matches.size > 1
        return matches.first if matches.one?
        raise ReviewRequired, 'idempotency_window_expired' if previous <= 23.hours.ago
      end
      @gateway.create(operation)
    end

    sig { params(operation: StripeOperation).returns(StripeIntegration::Types::Parameters) }
    def list_parameters(operation)
      case operation.kind
      when 'invoice' then { customer: operation.payload.fetch('customer') }
      when 'item' then { invoice: operation.payload.fetch('invoice') }
      else {}
      end
    end

    sig { params(operation: StripeOperation).returns(StripeIntegration::Types::JsonObject) }
    def finalize(operation)
      remote = @gateway.retrieve('invoice', T.must(operation.invoice).stripe_invoice_id)
      return remote unless remote.fetch('status') == 'draft'

      @gateway.finalize(operation)
    end

    sig { params(operation: StripeOperation, remote: StripeIntegration::Types::JsonObject).void }
    def validate_remote!(operation, remote)
      Contract.check!(remote, { livemode: false }, code: 'live_object_rejected')
      validate_identity!(operation, remote)
      Contract.check!(remote, operation.payload.slice('customer', 'invoice', 'currency', 'amount'),
                      code: 'operation_payload_mismatch')
    end

    sig { params(operation: StripeOperation, remote: StripeIntegration::Types::JsonObject).void }
    def validate_identity!(operation, remote)
      if operation.kind == 'finalize'
        raise ReviewRequired, 'unexpected_invoice_status' unless %w[open paid].include?(remote['status'])
      elsif remote.dig('metadata', 'ledgerly_operation') != operation.idempotency_key
        raise ReviewRequired, 'operation_identity_mismatch'
      end
    end
  end
end
