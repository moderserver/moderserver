# syntax=docker/dockerfile:1
###############################################
# ModerServer Argo CD
# Purpose: Single image for the Argo CD application controller, repo server and
#          API server. Upstream ships one binary for every component; each
#          Deployment selects its component with the command it runs.
###############################################

# renovate: datasource=docker depName=quay.io/argoproj/argocd
ARG ARGOCD_VERSION=v3.6.1
# renovate: datasource=docker depName=alpine
ARG ALPINE_VERSION=3.24.4

FROM quay.io/argoproj/argocd:${ARGOCD_VERSION} AS argocd-bin
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="ModerServer Argo CD" \
      org.opencontainers.image.description="Argo CD application controller, repo server and API server" \
      org.opencontainers.image.vendor="ModerServer" \
      org.opencontainers.image.licenses="Apache-2.0"

# git, gnupg, helm and kustomize are used by the repo server to render manifests
# hadolint ignore=DL3018
RUN apk add --no-cache git gnupg helm kustomize ca-certificates tzdata && \
    mkdir -p /app/config/tls /app/config/ssh /app/config/gpg/source /app/config/gpg/keys /home/argocd /tmp /helm-working-dir && \
    chown -R 65534:65534 /app /home/argocd /tmp /helm-working-dir && \
    ln -s /usr/bin/helm /usr/local/bin/helm && \
    ln -s /usr/bin/kustomize /usr/local/bin/kustomize

COPY --from=argocd-bin /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=argocd-bin /usr/local/bin/gpg-wrapper.sh /usr/local/bin/gpg-wrapper.sh
COPY --from=argocd-bin /usr/local/bin/git-verify-wrapper.sh /usr/local/bin/git-verify-wrapper.sh
RUN ln -s /usr/local/bin/argocd /usr/local/bin/argocd-application-controller && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-repo-server && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-server

USER 65534:65534
WORKDIR /home/argocd

ENTRYPOINT ["/usr/local/bin/argocd"]
