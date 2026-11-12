# syntax=docker/dockerfile:1
###############################################
# ModerServer System Upgrade Controller
# Purpose: Manages declarative node upgrades and OS chroot reconciliations
###############################################

# renovate: datasource=docker depName=rancher/system-upgrade-controller
ARG SUC_VERSION=v0.21.0
# renovate: datasource=docker depName=alpine
ARG ALPINE_VERSION=3.24.4

FROM rancher/system-upgrade-controller:${SUC_VERSION} AS upstream-bin
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="ModerServer System Upgrade Controller" \
      org.opencontainers.image.description="System Upgrade Controller for ModerServer platform" \
      org.opencontainers.image.vendor="ModerServer" \
      org.opencontainers.image.licenses="Apache-2.0"

# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates tzdata

COPY --from=upstream-bin /bin/system-upgrade-controller /usr/local/bin/system-upgrade-controller

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/system-upgrade-controller"]
