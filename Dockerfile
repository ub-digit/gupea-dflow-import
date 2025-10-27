FROM       ruby:2.7

# The location of the app files in the image
ENV        APP_HOME=/usr/src/app/
WORKDIR    $APP_HOME

# Install Ruby gems
COPY       ./app/Gemfile* ./
RUN        bundle install

# Install locale and other stuff
RUN        DEBIAN_FRONTEND=noninteractive \
           apt-get update \
        && apt-get install -y --no-install-recommends \
           vim mc tree less  \
           locales \
        && rm -rf /var/lib/apt/lists/* \
        && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
        && locale-gen

# Prepare the environment
ENV        LANG=en_US.UTF-8 \
           LANGUAGE=en_US:en \
           TZ=Europe/Stockholm

# Prepare the data directory
RUN        mkdir /data && mkdir /data/import/

# Copy the full context
COPY       ./app ./

# Start the main process
CMD        ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292"]
