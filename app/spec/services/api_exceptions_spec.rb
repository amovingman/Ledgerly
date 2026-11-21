require 'rails_helper'

RSpec.describe ApiExceptions do
  it 'hides internal failure details in its JSON fallback' do
    status, headers, body = described_class.call('action_dispatch.exception' => RuntimeError.new('private secret'))
    expect(status).to eq(500)
    expect(headers).to include('content-type' => 'application/json', 'cache-control' => 'no-store')
    expect(JSON.parse(body.join)).to eq('error' => {
                                          'code' => 'internal_error', 'message' => 'An unexpected error occurred.'
                                        })
  end

  it 'preserves a known HTTP status outside controller handlers' do
    status, _headers, body = described_class.call('action_dispatch.exception' => ActionController::BadRequest.new)
    expect(status).to eq(400)
    expect(JSON.parse(body.join).dig('error', 'code')).to eq('request_error')
  end
end
