#!/bin/bash
set -e

# Remove Puma PID if it exists (useful in Docker restarts)
if [ -f /usr/src/app/tmp/pids/puma.pid ]; then
  rm -f /usr/src/app/tmp/pids/puma.pid
fi

# Run bundle install before starting rails if local development environment
if [[ "$1" == "bundle" && $2 == "exec" && ("$RACK_ENV" == "development" || "$RACK_ENV" = "test") ]]; then
  echo "Running bundle install for $RACK_ENV environment..."
  bundle install
fi

# Ensure tmp/pids directory exists (for Puma)
mkdir -p /usr/src/app/tmp/pids 

# Execute the passed command
exec "$@"
