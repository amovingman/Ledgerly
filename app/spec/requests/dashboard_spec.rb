require 'rails_helper'

RSpec.describe 'Read-only dashboard' do
  let(:json_headers) { { 'Accept' => 'application/json' } }

  before do
    authenticate_api
    Rails.cache.clear
  end

  def sign_in
    post '/dashboard/session', params: { password: 'request-test-key' }
  end

  def form_token
    get '/dashboard/login'
    response.parsed_body.at_css('input[name="authenticity_token"]')['value']
  end

  def csrf_sign_in
    post '/dashboard/session', params: { password: 'request-test-key', authenticity_token: form_token }
  end

  it 'requires a viewer session for pages and data' do
    get '/dashboard'
    expect(response).to redirect_to('/dashboard/login')
    get '/dashboard/data/customers', headers: json_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'signs in without sending the credential back to the browser' do
    sign_in
    expect(response).to redirect_to('/dashboard')
    expect(response.headers.fetch('Set-Cookie')).to include('httponly', 'samesite=strict')
    expect(response.headers.fetch('Set-Cookie')).not_to include('request-test-key')
    get '/dashboard/data/customers', headers: json_headers
    expect(response).to have_http_status(:ok)
  end

  it 'rejects an incorrect key and fails closed when no key is configured' do
    post '/dashboard/session', params: { password: 'wrong' }
    expect(response).to have_http_status(:unauthorized)
    allow(ENV).to receive(:[]).with('API_KEY').and_return('')
    post '/dashboard/session', params: { password: 'anything' }
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'expires a viewer session and invalidates it on key rotation' do
    sign_in
    travel 31.minutes do
      get '/dashboard/data/customers', headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
    sign_in
    allow(ENV).to receive(:[]).with('API_KEY').and_return('rotated-key')
    get '/dashboard/data/customers', headers: json_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not authorize API writes or create billing records from a viewer cookie' do
    sign_in
    post '/api/v1/customers', params: { customer: { name: 'No write', email: 'readonly@example.test' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Customer.count).to eq(0)
    post '/dashboard/data/customers', params: { name: 'No write' }, as: :json
    expect(response).not_to have_http_status(:success)
  end

  it 'paginates and searches customer records without interpreting wildcard input' do
    create_customer(name: 'Aster Studio')
    selected = create_customer(name: 'Harbor Systems')
    sign_in
    get '/dashboard/data/customers', params: { q: 'Harbor', per_page: '1' }, headers: json_headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([selected.id.to_s])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    get '/dashboard/data/customers', params: { q: '%' }, headers: json_headers
    expect(response.parsed_body.fetch('data')).to be_empty
  end

  it 'keeps customer-scoped usage and invoices isolated and paginated' do
    first = create_subscription
    other = create_subscription
    usage = create_usage(subscription: first)
    invoice = create_invoice(subscription: first)
    create_usage(subscription: other)
    create_invoice(subscription: other)
    sign_in
    get '/dashboard/data/usage', params: { customer_id: first.customer_id.to_s }, headers: json_headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([usage.id.to_s])
    get '/dashboard/data/invoices', params: { customer_id: first.customer_id.to_s }, headers: json_headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([invoice.id.to_s])
  end

  it 'returns invoice details, complete entry fields and exact money strings' do
    invoice = create_invoice(amount: 9_007_199_254_740_993)
    journal = LedgerTransaction.create!(journal_attributes(invoice: invoice))
    sign_in
    get "/dashboard/data/invoices/#{invoice.id}", headers: json_headers
    expect(response.parsed_body.dig('data', 'amount')).to eq('9007199254740993')
    get '/dashboard/data/ledger', params: { invoice_id: invoice.id.to_s }, headers: json_headers
    data = response.parsed_body.fetch('data')
    expect(data.pluck('journal_id').uniq).to eq([journal.id.to_s])
    expect(data.pluck('debit')).to include('9007199254740993', '0')
  end

  it 'keeps currencies separate in exact overview ledger totals' do
    usd = create_invoice(amount: 70)
    cad = create_invoice(subscription: create_subscription(plan: create_plan(currency: 'CAD')), amount: 90)
    [usd, cad].each { |invoice| LedgerTransaction.create!(journal_attributes(invoice: invoice)) }
    sign_in
    get '/dashboard/data/overview', headers: json_headers
    expect(response.parsed_body.dig('data', 'ledger_totals')).to contain_exactly(
      { 'currency' => 'CAD', 'debit' => '90', 'credit' => '90' },
      { 'currency' => 'USD', 'debit' => '70', 'credit' => '70' }
    )
  end

  it 'shows webhook operational status without exposing raw payloads' do
    event = StripeEvent.create!(stripe_id: 'evt_dashboard', event_type: 'invoice.paid', api_version: 'fixture',
                                raw_payload: '{"private":"value"}', payload: { private: 'value' }, status: 'review',
                                last_error: 'remote_invoice_mismatch')
    sign_in
    get '/dashboard/data/webhooks', params: { status: 'review' }, headers: json_headers
    row = response.parsed_body.fetch('data').sole
    expect(row).to include('stripe_id' => event.stripe_id, 'status' => 'review',
                           'last_error' => 'remote_invoice_mismatch')
    expect(row.keys).not_to include('raw_payload', 'payload')
  end

  it 'rejects invalid filters and unsupported sections' do
    sign_in
    get '/dashboard/data/invoices', params: { status: 'unknown' }, headers: json_headers
    expect(response).to have_http_status(:bad_request)
    get '/dashboard/data/usage', params: { per_page: '101' }, headers: json_headers
    expect(response).to have_http_status(:bad_request)
    get '/dashboard/data/secrets', headers: json_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'signs out and prevents reuse of the current session' do
    sign_in
    delete '/dashboard/session'
    get '/dashboard/data/customers', headers: json_headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers.fetch('Cache-Control')).to include('no-store')
  end

  it 'renders the dashboard shell and returns customer and webhook details without changing records' do
    customer = create_customer
    event = StripeEvent.create!(stripe_id: 'evt_read', event_type: 'invoice.paid', api_version: 'fixture',
                                raw_payload: '{}', payload: {}, status: 'received')
    sign_in
    expect { get '/dashboard' }.not_to(change { [Customer.count, Invoice.count, LedgerEntry.count, StripeEvent.count] })
    expect(response.body).to include('dashboard.mjs', 'Read-only workspace')
    get "/dashboard/data/customers/#{customer.id}", headers: json_headers
    expect(response.parsed_body.dig('data', 'invoice_count')).to eq(0)
    get "/dashboard/data/webhooks/#{event.id}", headers: json_headers
    expect(response.parsed_body.dig('data', 'stripe_id')).to eq('evt_read')
    get '/dashboard/data/ledger', params: { stripe_event_id: event.id.to_s }, headers: json_headers
    expect(response.parsed_body.fetch('data')).to be_empty
  end

  it 'validates filter types and refuses unsupported scopes' do
    sign_in
    [{ q: ['bad'] }, { status: ['paid'] }, { invoice_id: '1' }, { stripe_event_id: '1' }].each do |params|
      get '/dashboard/data/customers', params: params, headers: json_headers
      expect(response).to have_http_status(:bad_request)
    end
    get '/dashboard/data/webhooks', params: { customer_id: '1' }, headers: json_headers
    expect(response).to have_http_status(:bad_request)
  end

  context 'with CSRF protection enabled' do
    around do |example|
      original = Dashboard::BaseController.allow_forgery_protection
      Dashboard::BaseController.allow_forgery_protection = true
      example.run
    ensure
      Dashboard::BaseController.allow_forgery_protection = original
    end

    it 'enforces CSRF and same-origin protection when enabled, including sign-in and sign-out' do
      get '/dashboard/login'
      response.parsed_body.at_css('input[name="authenticity_token"]')['value']
      post '/dashboard/session', params: { password: 'request-test-key' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('This form expired.')
      csrf_sign_in
      expect(response).to redirect_to('/dashboard')
      post '/dashboard/logout'
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'submits the real sign-out form with CSRF enabled in API mode' do
      csrf_sign_in
      get '/dashboard'
      form = response.parsed_body.at_css('form[action="/dashboard/logout"]')
      post form['action'], params: { authenticity_token: form.at_css('input[name="authenticity_token"]')['value'] }
      expect(response).to redirect_to('/dashboard/login')
      get '/dashboard/data/customers', headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
