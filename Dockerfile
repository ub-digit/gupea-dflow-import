#FROM dspace/dspace:dspace-8_x
FROM docker.ub.gu.se/dspace:dspace-8_x-release-2025.10.001

# The location of the app files in the image
ENV APP_HOME=/usr/src/app/
WORKDIR  $APP_HOME

# Install Ruby gems
COPY ./app/Gemfile* ./

# Install locale and other stuff
RUN apt-get update \
    && apt-get install -y ruby-full build-essential vim

RUN gem install bundler

RUN bundle install

# Prepare the data directory
RUN mkdir /data && mkdir /data/import/

# Copy the full context
COPY ./app ./

# Start the main process
ENTRYPOINT ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292"]
