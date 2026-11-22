require 'open3'
require 'tmpdir'

programs = {
  valid: ['Billing::Result[Invoice].new(record: Invoice.new, replayed: false).record.amount', []],
  wrong_record: ['Billing::Result[Invoice].new(record: Customer.new, replayed: false)', %w[Invoice Customer]],
  wrong_event: ['StripeIntegration::ProcessEvent.new(event: Customer.new)', %w[StripeEvent Customer]],
  wrong_scalar: ["Billing::Input.positive_integer(1, field: 'quantity').upcase", %w[upcase Integer]]
}
Dir.mktmpdir('type-contracts-', File.expand_path('../tmp', __dir__)) do |directory|
  programs.each do |name, (source, expected)|
    path = File.join(directory, "#{name}.rb")
    File.write(path, "# typed: true\n#{source}\n")
    stdout, stderr, status = Open3.capture3('bin/typecheck', '--color=never', path)
    output = stdout + stderr
    passed = expected.empty? ? status.success? : !status.success? && expected.all? { |word| output.include?(word) }
    raise "Type contract #{name} failed:\n#{output}" unless passed
  end
end
puts 'PASS: valid types accepted; wrong result records, webhook records and scalar use rejected'
