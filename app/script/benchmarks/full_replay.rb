require Rails.root.join('lib/ledgerly_benchmark/full_replay')
progress = lambda do |event|
  puts JSON.generate(event)
  $stdout.flush
end
result = LedgerlyBenchmark::FullReplay.new(progress: progress).call
puts "LEDGERLY_FULL_REPLAY=#{JSON.generate(result)}"
