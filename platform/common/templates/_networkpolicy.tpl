{{/*
Default-deny ingress policy for a namespace. Every allowed flow must then be
granted by an explicit NetworkPolicy next to the workload that receives it.
Usage: {{ include "common.networkpolicy.defaultDeny" (dict "ctx" . "namespace" "argocd") }}
*/}}
{{- define "common.networkpolicy.defaultDeny" -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: {{ .namespace }}
  labels:
    {{- include "common.labels.standard" .ctx | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
{{- end -}}
