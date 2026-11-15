{{/*
Hardened security contexts for ModerServer platform infrastructure.

Both helpers take a dict with the optional keys "uid" and "gid"; the default is
the unprivileged nobody user (65534), and "gid" defaults to "uid".

Usage:
  securityContext:
    {{- include "common.security.pod" (dict) | nindent 8 }}
  securityContext:
    {{- include "common.security.container" (dict "uid" 101 "gid" 1001) | nindent 12 }}
*/}}

{{/*
Pod Security Context: non-root, RuntimeDefault seccomp
*/}}
{{- define "common.security.pod" -}}
{{- $uid := default 65534 .uid -}}
{{- $gid := default $uid .gid -}}
runAsNonRoot: true
runAsUser: {{ $uid }}
runAsGroup: {{ $gid }}
fsGroup: {{ $gid }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Container Security Context: read-only root filesystem, no privilege escalation,
no capabilities, non-root, RuntimeDefault seccomp
*/}}
{{- define "common.security.container" -}}
{{- $uid := default 65534 .uid -}}
{{- $gid := default $uid .gid -}}
readOnlyRootFilesystem: true
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
runAsNonRoot: true
runAsUser: {{ $uid }}
runAsGroup: {{ $gid }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}
