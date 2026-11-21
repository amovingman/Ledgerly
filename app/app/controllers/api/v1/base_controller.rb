module Api
  module V1
    class BaseController < ApplicationController
      private

      def find_record(model, id = params[:id])
        model.find(Billing::Input.identifier(id))
      end

      def render_result(result, serializer)
        response.set_header('Idempotency-Replayed', result.replayed.to_s)
        render json: { data: Representation.public_send(serializer, result.record) },
               status: result.replayed ? :ok : :created
      end

      def render_collection(scope, serializer)
        window = pagination
        records = scope.limit(window.per_page).offset(window.offset)
        render json: { data: records.map { |record| Representation.public_send(serializer, record) },
                       meta: { page: window.page, per_page: window.per_page, total: scope.count } }
      end
    end
  end
end
