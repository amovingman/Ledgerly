namespace :stripe do
  desc 'Recover durable webhook/collection work and dispatch pending outbox records'
  task recover: :environment do
    StripeIntegration::RecoverySweep.call
    puts 'Recovery sweep complete'
  end

  desc 'Safely replay a dead/review Stripe event without changing its payload or financial effects'
  task :replay_event, [:stripe_id] => :environment do |_task, args|
    StripeIntegration::RecoverySweep.replay(StripeEvent.find_by!(stripe_id: args.fetch(:stripe_id)))
    puts 'Event replay requested'
  end

  desc 'Replay collection after resolving a failure; original keys and expiry guards remain intact'
  task :replay_collection, [:invoice_id] => :environment do |_task, args|
    collection = InvoiceCollection.find_by!(invoice_id: args.fetch(:invoice_id))
    StripeIntegration::RecoverySweep.replay(collection)
    puts 'Collection replay requested'
  end
end
