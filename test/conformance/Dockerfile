# syntax=docker/dockerfile:1
###############################################
# ModerServer Conformance Engine
# Validation suite for platform components and applications
###############################################

# renovate: datasource=docker depName=alpine
ARG ALPINE_VERSION=3.24.4
# renovate: datasource=docker depName=aquasec/trivy
ARG TRIVY_VERSION=0.76.2
# renovate: datasource=docker depName=hadolint/hadolint
ARG HADOLINT_VERSION=v2.15.1
# renovate: datasource=docker depName=ghcr.io/yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
# renovate: datasource=docker depName=stackrox/kube-linter
ARG KUBE_LINTER_VERSION=v0.8.3
# renovate: datasource=github-releases depName=FairwindsOps/polaris
ARG POLARIS_VERSION=v10.2.6
# renovate: datasource=docker depName=ghcr.io/gitleaks/gitleaks
ARG GITLEAKS_VERSION=v8.30.1
# renovate: datasource=docker depName=koalaman/shellcheck
ARG SHELLCHECK_VERSION=v0.11.0
# renovate: datasource=docker depName=derailed/popeye
ARG POPEYE_VERSION=v0.22.1
# renovate: datasource=docker depName=quay.io/kubescape/kubescape-cli
ARG KUBESCAPE_VERSION=v4.0.20

FROM aquasec/trivy:${TRIVY_VERSION} AS trivy-bin
FROM hadolint/hadolint:${HADOLINT_VERSION} AS hadolint-bin
FROM ghcr.io/yannh/kubeconform:${KUBECONFORM_VERSION} AS kubeconform-bin
FROM stackrox/kube-linter:${KUBE_LINTER_VERSION} AS kube-linter-bin
FROM us-docker.pkg.dev/fairwinds-ops/oss/polaris:${POLARIS_VERSION} AS polaris-bin
FROM ghcr.io/gitleaks/gitleaks:${GITLEAKS_VERSION} AS gitleaks-bin
FROM koalaman/shellcheck:${SHELLCHECK_VERSION} AS shellcheck-bin
FROM derailed/popeye:${POPEYE_VERSION} AS popeye-bin
FROM quay.io/kubescape/kubescape-cli:${KUBESCAPE_VERSION} AS kubescape-bin

FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="ModerServer Conformance Suite" \
      org.opencontainers.image.description="Validation suite for ModerServer applications and components" \
      org.opencontainers.image.vendor="ModerServer" \
      org.opencontainers.image.licenses="Apache-2.0"

# Install base tools
RUN apk add --no-cache \
      bash \
      curl \
      ca-certificates \
      git \
      python3 \
      py3-pip \
      helm \
      docker-cli \
      docker-cli-buildx \
      bind-tools

# renovate: datasource=pypi depName=yamllint
ARG YAMLLINT_VERSION=1.38.0
RUN pip install --no-cache-dir --break-system-packages "yamllint==${YAMLLINT_VERSION}"

# Copy official pre-compiled CLI binaries
COPY --from=trivy-bin /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=hadolint-bin /bin/hadolint /usr/local/bin/hadolint
COPY --from=kubeconform-bin /kubeconform /usr/local/bin/kubeconform
COPY --from=kube-linter-bin /kube-linter /usr/local/bin/kube-linter
COPY --from=polaris-bin /usr/local/bin/polaris /usr/local/bin/polaris
COPY --from=gitleaks-bin /usr/bin/gitleaks /usr/local/bin/gitleaks
COPY --from=shellcheck-bin /bin/shellcheck /usr/local/bin/shellcheck
COPY --from=popeye-bin /bin/popeye /usr/local/bin/popeye
COPY --from=kubescape-bin /usr/bin/kubescape /usr/local/bin/kubescape

# Copy conformance scripts and shared hack libraries
COPY test/conformance /conformance
COPY hack /hack

WORKDIR /workspace

ENTRYPOINT ["/conformance/run.sh"]
