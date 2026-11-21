require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render json: { page: pagination.page, per_page: pagination.per_page, offset: pagination.offset }
    end

    def create
      params.require(:usage)
      head :created
    end

    def show
      raise ActiveRecord::RecordNotFound
    end

    def update
      record = Class.new { include ActiveModel::Model }.new
      raise ActiveRecord::RecordInvalid, record
    end
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('API_KEY').and_return('controller-test-key')
    request.headers['Authorization'] = 'Bearer controller-test-key'
  end

  it 'exposes validated pagination to API controllers' do
    get :index, params: { page: '2', per_page: '10' }
    expect(response.parsed_body).to eq('page' => 2, 'per_page' => 10, 'offset' => 10)
  end

  it 'renders invalid pagination as a JSON client error' do
    get :index, params: { per_page: ['1'] }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_pagination')
  end

  it 'renders missing required input as a JSON client error' do
    post :create
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('error', 'code')).to eq('bad_request')
  end

  it 'renders missing database resources as JSON' do
    get :show, params: { id: 'missing' }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig('error', 'code')).to eq('not_found')
  end

  it 'renders model validation errors as JSON' do
    put :update, params: { id: 'invalid' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('error', 'code')).to eq('validation_failed')
  end
end
