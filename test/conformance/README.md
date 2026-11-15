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

### Accepted Findings

A finding is never silenced without a written reason:

* `.trivyignore` (repository root) lists the accepted static findings. Each entry is commented, and CVE entries carry an expiry date.
* `runtime/exceptions/<namespace>.trivyignore` lists accepted runtime findings for one namespace only. Every other namespace is scanned with no exception.

## Usage

Every check runs inside the conformance image (`test/conformance/Dockerfile`),
which pins the whole toolchain. Nothing but Docker is needed on the host, and
the result is the same on a laptop and in CI.

### From this repository

```bash
# Static Conformance of all platform components, or of one
make test-conformance
make test-conformance COMPONENT=cert-manager

# Runtime Conformance: installs a QEMU machine, or uses the cluster KUBECONFIG points at
make test-conformance-runtime
```

Both targets build the image from the working tree first, so a change to a
check or to a tool version is exercised immediately.

### From another repository

```bash
# Static checks of a chart directory. The Docker socket lets the suite build
# and scan the images of the Dockerfiles it finds.
docker run --rm \
  --user "$(id -u):$(id -g)" --group-add "$(stat -c '%g' /var/run/docker.sock)" \
  -e HOME=/tmp -e USER=conformance \
  -v "$(pwd):/workspace" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/moderserver/conformance:latest --static path/to/chart

# Runtime checks of a namespace of a running cluster
docker run --rm --net=host \
  -v "${KUBECONFIG}:/tmp/kubeconfig:ro" -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/moderserver/conformance:latest --runtime my-namespace
```
