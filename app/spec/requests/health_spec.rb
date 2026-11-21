require 'rails_helper'

RSpec.describe 'Health endpoints' do
  it 'serves public JSON liveness without API authentication' do
    get '/up'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'ok')
  end

  it 'checks the real database and Redis connections' do
    get '/ready'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'ok', 'checks' => { 'postgres' => 'ok', 'redis' => 'ok' })
  end

  it 'reports database failure without exposing connection details' do
    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection)
      .and_raise(ActiveRecord::ConnectionNotEstablished, 'private connection details')
    get '/ready'
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('checks', 'postgres')).to eq('unavailable')
    expect(response.body).not_to include('private connection details')
  end

  it 'reports Redis failure and closes the connection' do
    client = instance_double(Redis)
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:ping).and_raise(Redis::CannotConnectError, 'private redis address')
    allow(client).to receive(:close)
    get '/ready'
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('checks', 'redis')).to eq('unavailable')
    expect(response.body).not_to include('private redis address')
    expect(client).to have_received(:close)
  end
end
