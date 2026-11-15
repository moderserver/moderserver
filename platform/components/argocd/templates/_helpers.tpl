{{/*
Standard labels, with app.kubernetes.io/part-of: argocd as required by the
Argo CD settings manager on the ConfigMaps and Secrets it reads
*/}}
{{- define "argocd.labels.standard" -}}
{{- include "common.labels.standard" . | replace "app.kubernetes.io/part-of: moderserver" "app.kubernetes.io/part-of: argocd" -}}
{{- end -}}
