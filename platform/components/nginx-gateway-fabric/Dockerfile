# syntax=docker/dockerfile:1
###############################################
# ModerServer NGINX Gateway Fabric Control Plane
# Purpose: Gateway API controller managing dynamic NGINX data plane instances
###############################################

# renovate: datasource=github-releases depName=nginx/nginx-gateway-fabric
ARG NGF_VERSION=v2.8.1
# renovate: datasource=docker depName=golang
ARG GOLANG_VERSION=1.27.4-alpine
# renovate: datasource=docker depName=alpine
ARG ALPINE_VERSION=3.24.4

FROM golang:${GOLANG_VERSION} AS build-base
ARG NGF_VERSION
# Patched golang.org/x/net carried on top of the upstream release
# renovate: datasource=go depName=golang.org/x/net
ARG GOLANG_X_NET_VERSION=v0.62.0
# hadolint ignore=DL3018
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch ${NGF_VERSION} https://github.com/nginx/nginx-gateway-fabric /src && \
    go get "golang.org/x/net@${GOLANG_X_NET_VERSION}" && \
    CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=${NGF_VERSION#v} -X main.telemetryReportPeriod=24h -X main.telemetryEndpointInsecure=false" -o /dist/gateway ./cmd/gateway

FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="ModerServer NGINX Gateway Fabric" \
      org.opencontainers.image.description="NGINX Gateway Fabric control plane for ModerServer" \
      org.opencontainers.image.vendor="ModerServer" \
      org.opencontainers.image.licenses="Apache-2.0"

# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates tzdata

COPY --from=build-base /dist/gateway /usr/bin/gateway
RUN ln -s /usr/bin/gateway /usr/local/bin/gateway

USER 101:1001

ENTRYPOINT ["/usr/bin/gateway"]
CMD ["controller"]
