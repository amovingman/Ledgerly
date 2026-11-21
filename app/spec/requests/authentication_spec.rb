require 'rails_helper'

RSpec.describe 'API authentication' do
  let(:api_key) { 'foundation-test-key' }
  let(:headers) { { 'Authorization' => "Bearer #{api_key}" } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('API_KEY').and_return(api_key)
  end

  it 'returns service status for an authenticated request' do
    get '/api/v1/status', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('data' => { 'service' => 'ledgerly', 'status' => 'ok' })
  end

  [nil, 'Bearer wrong', 'Basic foundation-test-key', 'Bearer foundation-test-key extra'].each do |authorization|
    it "rejects #{authorization ? 'invalid credentials' : 'missing credentials'} (#{authorization.inspect})" do
      get '/api/v1/status', headers: { 'Authorization' => authorization }.compact
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['WWW-Authenticate']).to eq('Bearer')
      expect(response.parsed_body.dig('error', 'code')).to eq('unauthorized')
      expect(response.body).not_to include(api_key)
    end
  end

  [nil, '', '   '].each do |configured_key|
    it "fails closed for an unconfigured key #{configured_key.inspect}" do
      allow(ENV).to receive(:[]).with('API_KEY').and_return(configured_key)
      get '/api/v1/status', headers: headers
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig('error', 'code')).to eq('authentication_unavailable')
    end
  end

  it 'rejects malformed JSON with the documented envelope' do
    post '/missing-resource', params: '{', headers: headers.merge('CONTENT_TYPE' => 'application/json')
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_json')
  end

  it 'returns JSON for an unknown route' do
    get '/missing-resource', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig('error', 'code')).to eq('not_found')
  end

  it 'returns JSON for the unmapped root route' do
    get '/', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq('application/json')
  end

  it 'filters sensitive parameters' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter('api_key' => api_key, 'authorization' => "Bearer #{api_key}"))
      .to eq('api_key' => '[FILTERED]', 'authorization' => '[FILTERED]')
  end
end
