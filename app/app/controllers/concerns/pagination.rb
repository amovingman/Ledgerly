module Pagination
  private

  def pagination
    @pagination ||= PaginationParams.parse(page: params[:page], per_page: params[:per_page])
  end
end
