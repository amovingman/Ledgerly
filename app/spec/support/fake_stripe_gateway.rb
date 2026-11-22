# Deterministic provider contract double. Gateway HTTP specs separately exercise the actual SDK.
class FakeStripeGateway
  attr_accessor :fail_after_create, :fail_after_finalize
  attr_reader :calls, :objects

  def initialize
    @objects = Hash.new { |hash, key| hash[key] = {} }
    @calls = []
  end

  def retrieve(kind, id)
    @calls << { action: :retrieve, kind: kind, id: id }
    copy(@objects.fetch(kind).fetch(id))
  end

  def list(kind, parameters = {})
    @calls << { action: :list, kind: kind }
    filters = parameters.deep_stringify_keys
    matches = @objects[kind].values.select do |item|
      filters.all? do |key, value|
        key == 'payment' ? value.all? { |field, expected| item.dig('payment', field) == expected } : item[key] == value
      end
    end
    matches.map { |item| copy(item) }
  end

  def create(operation)
    kind = operation.kind
    @calls << { action: :create, kind: kind, key: operation.idempotency_key, payload: copy(operation.payload) }
    prefix = { 'customer' => 'cus', 'invoice' => 'in', 'item' => 'ii' }.fetch(kind)
    id = "#{prefix}_#{SecureRandom.hex(8)}"
    remote = operation.payload.merge('id' => id, 'livemode' => false, 'object' => kind)
    remote.merge!('total' => 0, 'amount_paid' => 0, 'status' => 'draft') if kind == 'invoice'
    @objects[kind][id] = remote
    @objects['invoice'].fetch(remote.fetch('invoice'))['total'] += remote.fetch('amount') if kind == 'item'
    if fail_after_create == kind
      self.fail_after_create = nil
      raise StripeIntegration::Retryable, 'stripe_unavailable'
    end
    copy(remote)
  end

  def finalize(operation)
    @calls << { action: :finalize, kind: 'invoice' }
    invoice = @objects['invoice'].fetch(operation.invoice.stripe_invoice_id)
    invoice.merge!('status' => 'open', 'auto_advance' => true)
    if fail_after_finalize
      self.fail_after_finalize = false
      raise StripeIntegration::Retryable, 'stripe_unavailable'
    end
    copy(invoice)
  end

  def create_count(kind)
    calls.count { |call| call[:action] == :create && call[:kind] == kind }
  end

  def seed_paid(invoice, refunds: [])
    suffix = invoice.id.to_s
    currency = invoice.currency.downcase
    customer = invoice.customer.stripe_customer_id
    remote_id = invoice.stripe_invoice_id
    @objects['invoice'][remote_id] = { 'id' => remote_id, 'object' => 'invoice', 'livemode' => false,
                                       'customer' => customer, 'currency' => currency, 'total' => invoice.amount,
                                       'amount_paid' => invoice.amount, 'status' => 'paid', 'metadata' => {} }
    @objects['invoice_payment']["inpay_#{suffix}"] = {
      'id' => "inpay_#{suffix}", 'invoice' => remote_id, 'livemode' => false, 'amount_paid' => invoice.amount,
      'currency' => currency, 'status' => 'paid',
      'payment' => { 'type' => 'payment_intent', 'payment_intent' => "pi_#{suffix}" }
    }
    @objects['payment_intent']["pi_#{suffix}"] = {
      'id' => "pi_#{suffix}", 'livemode' => false, 'currency' => currency, 'customer' => customer,
      'status' => 'succeeded', 'amount_received' => invoice.amount, 'latest_charge' => "ch_#{suffix}"
    }
    @objects['charge']["ch_#{suffix}"] = {
      'id' => "ch_#{suffix}", 'livemode' => false, 'currency' => currency, 'customer' => customer,
      'payment_intent' => "pi_#{suffix}", 'paid' => true, 'captured' => true, 'amount_captured' => invoice.amount
    }
    refunds.each_with_index do |amount, index|
      id = "re_#{suffix}_#{index}"
      @objects['refund'][id] = { 'id' => id, 'charge' => "ch_#{suffix}", 'payment_intent' => "pi_#{suffix}",
                                 'amount' => amount, 'currency' => currency, 'status' => 'succeeded' }
    end
  end

  private

  def copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
