module Api
  module V1
    class StatusController < ApplicationController
      def show
        render json: { data: { service: 'ledgerly', status: 'ok' } }
      end
    end
  end
end
