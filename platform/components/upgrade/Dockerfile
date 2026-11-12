# syntax=docker/dockerfile:1
###############################################
# ModerServer OS Upgrade Runner
# Base: Alpine Linux
# Purpose: Executes host chroot package upgrades via system-upgrade-controller
###############################################

# renovate: datasource=docker depName=alpine
ARG ALPINE_VERSION=3.24.4
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="ModerServer OS Upgrade Runner" \
      org.opencontainers.image.description="Host OS upgrade runner for ModerServer GitOps" \
      org.opencontainers.image.vendor="ModerServer" \
      org.opencontainers.image.licenses="Apache-2.0"

# hadolint ignore=DL3018
RUN apk add --no-cache bash

COPY run-upgrade.sh /usr/local/bin/run-upgrade.sh
RUN chmod 755 /usr/local/bin/run-upgrade.sh

ENTRYPOINT ["/usr/local/bin/run-upgrade.sh"]
