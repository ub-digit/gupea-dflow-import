ARG DSPACE_VERSION

FROM alpine:latest AS release
ARG GIT_REVISION
ARG GIT_REPO_URL

RUN apk add --no-cache git

WORKDIR /root/

RUN set -ex \
  && git clone $GIT_REPO_URL release -b $GIT_REVISION --depth 1

FROM docker.ub.gu.se/dspace:dspace-8_x-${DSPACE_VERSION}

RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update \
  && apt-get install -y  --no-install-recommends \
     ruby-full build-essential vim \
  && rm -rf /var/lib/apt/lists/*

RUN gem install bundler

# Set working directory in container
WORKDIR /usr/src/app/

COPY --from=release /root/release /usr/src/app

RUN bundle install --jobs 4 --retry 3

COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3000

# Start the main process
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000"]
