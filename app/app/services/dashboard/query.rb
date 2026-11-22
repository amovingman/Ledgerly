module Dashboard
  class Query
    SECTIONS = %w[customers usage invoices ledger webhooks].freeze

    def initialize(params)
      @params = params
    end

    def call(section)
      return Summary.call if section == 'overview'
      raise ActiveRecord::RecordNotFound unless SECTIONS.include?(section)

      scope = Collections.scope(section)
      scope = filter(scope, section)
      window = PaginationParams.parse(page: @params[:page], per_page: @params[:per_page])
      collection(scope, section, window)
    end

    private

    def collection(scope, section, window)
      records = scope.limit(window.per_page).offset(window.offset)
      { data: records.map { |record| Presentation.public_send(section, record) },
        meta: { page: window.page, per_page: window.per_page, total: scope.count } }
    end

    def filter(scope, section)
      scope = customer_filter(scope, section) if @params[:customer_id].present?
      scope = status_filter(scope, section) if @params[:status].present?
      scope = search_filter(scope, section) if @params[:q].present?
      scope = invoice_filter(scope, section) if @params[:invoice_id].present?
      return scope if @params[:stripe_event_id].blank?

      event_filter(scope, section)
    end

    def event_filter(scope, section)
      raise ActionController::BadRequest unless section == 'ledger'

      scope.where(ledger_transactions: { stripe_event_id: Billing::Input.identifier(@params[:stripe_event_id]) })
    end

    def invoice_filter(scope, section)
      raise ActionController::BadRequest unless section == 'ledger'

      scope.where(ledger_transactions: { invoice_id: Billing::Input.identifier(@params[:invoice_id]) })
    end

    def customer_filter(scope, section)
      id = Billing::Input.identifier(@params[:customer_id])
      return scope.where(invoices: { customer_id: id }) if section == 'ledger'
      raise ActionController::BadRequest if section == 'webhooks'

      scope.where(section == 'customers' ? { id: id } : { customer_id: id })
    end

    def status_filter(scope, section)
      choices = Collections::STATUSES.fetch(section, [])
      status = @params[:status]
      raise ActionController::BadRequest unless status.is_a?(String) && choices.include?(status)
      return scope.where(invoice_line_item_id: nil) if status == 'unbilled'
      return scope.where.not(invoice_line_item_id: nil) if status == 'billed'

      scope.where(status: status)
    end

    def search_filter(scope, section)
      query = @params[:q]
      raise ActionController::BadRequest unless query.is_a?(String) && query.length <= 100

      text = "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%"
      scope.where(Collections::SEARCH.fetch(section), query: text)
    end
  end
end
