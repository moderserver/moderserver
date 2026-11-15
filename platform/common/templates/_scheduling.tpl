{{/*
Scheduling for platform infrastructure: Linux control-plane nodes, tolerating
the taints a control-plane node may carry.

Usage (pod spec level):
  {{- include "common.scheduling.controlPlane" . | nindent 6 }}
*/}}
{{- define "common.scheduling.controlPlane" -}}
nodeSelector:
  kubernetes.io/os: linux
  node-role.kubernetes.io/control-plane: "true"
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
{{- end -}}
