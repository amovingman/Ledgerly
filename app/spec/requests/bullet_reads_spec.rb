require 'rails_helper'
require 'bullet'

RSpec.describe 'Billing query loading' do
  before do
    configure_stripe_test
    authenticate_api
    Bullet.enable = true
    Bullet.counter_cache_enable = false
    Bullet.unused_eager_loading_enable = false
    Bullet.raise = true
  end

  after do
    Bullet.end_request
    Bullet.enable = false
  end

  it 'detects a deliberately lazy customer association as a positive control' do
    ids = Array.new(3) { create_invoice.id }
    Bullet.start_request
    Invoice.where(id: ids).to_a.each { |invoice| invoice.customer.name }
    expect(Bullet.notification?).to be(true)
  end

  it 'reports no N+1 queries for invoice list/detail and balance reads' do
    invoice, = paid_stripe_invoice
    Bullet.start_request
    headers = { 'Authorization' => 'Bearer request-test-key' }
    ["/api/v1/customers/#{invoice.customer_id}/invoices", "/api/v1/invoices/#{invoice.id}",
     "/api/v1/customers/#{invoice.customer_id}/balance"].each do |path|
      get path, headers: headers
      expect(response).to have_http_status(:ok)
    end
    expect(Bullet.notification?).to be(false)
  end
end
