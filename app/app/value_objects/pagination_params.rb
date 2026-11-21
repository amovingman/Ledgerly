# typed: strict

class PaginationParams
  extend T::Sig

  class Invalid < StandardError; end

  sig { returns(Integer) }
  attr_reader :page

  sig { returns(Integer) }
  attr_reader :per_page

  sig { params(page: Integer, per_page: Integer).void }
  def initialize(page:, per_page:)
    @page = page
    @per_page = per_page
  end

  sig { returns(Integer) }
  def offset
    (page - 1) * per_page
  end

  sig { params(page: T.untyped, per_page: T.untyped).returns(PaginationParams) }
  def self.parse(page: nil, per_page: nil)
    parsed_page = parse_integer(page, 1)
    parsed_size = parse_integer(per_page, 25)
    raise Invalid if parsed_size > 100

    new(page: parsed_page, per_page: parsed_size)
  end

  sig { params(value: T.untyped, default: Integer).returns(Integer) }
  def self.parse_integer(value, default)
    return default if value.nil?
    raise Invalid unless value.is_a?(String) && /\A[1-9]\d*\z/.match?(value)

    value.to_i
  end
  private_class_method :parse_integer
end
