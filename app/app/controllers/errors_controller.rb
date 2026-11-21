class ErrorsController < ApplicationController
  def not_found
    render_error(:not_found, 'not_found', 'The requested resource was not found.')
  end
end
