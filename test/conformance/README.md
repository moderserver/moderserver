# ModerServer Conformance Suite

The ModerServer Conformance Suite validates that core platform components and catalog applications comply with the standards defined in the [ModerServer Manifesto](https://github.com/ModerServer/.github/blob/main/MANIFESTO.md).

## Checks

The suite runs in two phases:

### 1. Static Conformance (Pre-Deployment)

Audits source Dockerfiles, Helm charts, and rendered Kubernetes manifests prior to deployment:

| Tool | Script | Focus |
| :--- | :--- | :--- |
| **Hadolint** | `static/verify-image-hadolint.sh` | Containerfile best practices, rootless enforcement, pinned packages |
| **Trivy Image** | `static/verify-image-trivy.sh` | CVE vulnerability scanning against local container images |
| **Helm** | `static/verify-charts-helm-lint.sh` | Chart syntax, templates, and dependency resolution |
| **Kubeconform** | `static/verify-charts-kubeconform.sh` | Strict Kubernetes OpenAPI schema validation and CRD schemas |
| **Kube-Linter** | `static/verify-charts-kube-linter.sh` | Security best practices (non-root, security contexts, probes) |
| **Polaris** | `static/verify-charts-polaris.sh` | Workload configuration scoring and production best practices |
| **Kubescape** | `static/verify-charts-kubescape.sh` | NSA-CISA Kubernetes Hardening Guidance compliance |
| **Trivy Config** | `static/verify-charts-trivy.sh` | Static manifest misconfiguration and privilege escalation detection |

### 2. Runtime Conformance (Active Cluster)

Evaluates workloads running on an active Kubernetes cluster using industry-standard cluster analysis tools:

| Tool | Script | Focus |
| :--- | :--- | :--- |
| **Popeye** | `runtime/verify-runtime-popeye.sh` | Live cluster sanitization, misallocation, and resource health scoring |
| **Trivy K8s** | `runtime/verify-runtime-trivy.sh` | Live cluster vulnerability, RBAC, and workload misconfiguration audit |

## Usage

### Local Execution

From the root of the repository:

```bash
# Run Static Conformance against a specific component or application
./test/conformance/run.sh --static platform/components/upgrade
./test/conformance/run.sh --static platform/components/gateway-api

# Run Runtime Conformance against an active cluster namespace
./test/conformance/run.sh --runtime moderserver-system

# Run complete verification (Static + Runtime)
./test/conformance/run.sh --all platform/components/upgrade moderserver-system
```

### Containerized Execution

The suite can also run as a container without installing local tools:

```bash
# Build the conformance image
make build-conformance

# Run static checks via container
docker run --rm \
  -v "$(pwd):/workspace" \
  ghcr.io/moderserver/conformance:latest --static platform/components/gateway-api
```
