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
  && apt-get install -y --no-install-recommends \
     python3 \
     python3-flask \
     build-essential \
     vim \
  && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /usr/src/app/

COPY --from=release /root/release /usr/src/app


ENTRYPOINT []

EXPOSE 3000


CMD ["python3", "main.py"]
