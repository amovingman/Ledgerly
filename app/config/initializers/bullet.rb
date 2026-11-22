if Rails.env.development? && ENV['BULLET_ENABLED'] == '1'
  require 'bullet'
  Rails.application.config.middleware.use Bullet::Rack
  Rails.application.config.after_initialize do
    Bullet.enable = true
    Bullet.raise = true
    Bullet.rails_logger = true
    Bullet.skip_html_injection = true
    Bullet.skip_http_headers = true
  end
end
