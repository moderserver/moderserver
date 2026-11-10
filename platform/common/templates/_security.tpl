{{/*
Default Pod Security Context for ModerServer platform infrastructure
*/}}
{{- define "common.security.pod" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
fsGroupChangePolicy: "OnRootMismatch"
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Default Container Security Context for ModerServer platform infrastructure
*/}}
{{- define "common.security.container" -}}
readOnlyRootFilesystem: true
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
{{- end -}}
