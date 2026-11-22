module Dashboard
  class PagesController < BaseController
    before_action :require_viewer!

    def show
      render 'dashboard/index'
    end
  end
end
