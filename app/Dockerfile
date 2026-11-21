# Development/test image. Production hardening belongs to a later release.
FROM ruby:3.4.13-slim-bookworm

ARG BUNDLER_VERSION=4.1.0

ENV BUNDLE_FROZEN=true \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/* && \
    gem install bundler --version "$BUNDLER_VERSION" --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle install

RUN useradd --create-home --shell /bin/bash rails && chown rails:rails /rails
COPY --chown=rails:rails . .
USER rails

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
