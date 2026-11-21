class Customer < ApplicationRecord
  has_many :subscriptions, dependent: :restrict_with_exception
  has_many :usage_events, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }
  validates :name, presence: true, length: { maximum: 200 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
end
