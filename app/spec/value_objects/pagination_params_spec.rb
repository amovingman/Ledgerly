require 'rails_helper'

RSpec.describe PaginationParams do
  it 'defaults to page one with 25 results' do
    window = described_class.parse
    expect([window.page, window.per_page, window.offset]).to eq([1, 25, 0])
  end

  it 'calculates a bounded page offset' do
    window = described_class.parse(page: '3', per_page: '100')
    expect([window.page, window.per_page, window.offset]).to eq([3, 100, 200])
  end

  ['0', '-1', '1.5', 'abc', '', ' 1', '01', ['1'], { 'page' => '1' }].each do |invalid|
    it "rejects invalid page #{invalid.inspect}" do
      expect { described_class.parse(page: invalid) }.to raise_error(described_class::Invalid)
    end

    it "rejects invalid per_page #{invalid.inspect}" do
      expect { described_class.parse(per_page: invalid) }.to raise_error(described_class::Invalid)
    end
  end

  it 'rejects a page size above the maximum' do
    expect { described_class.parse(per_page: '101') }.to raise_error(described_class::Invalid)
  end
end
