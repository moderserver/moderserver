{{/*
Platform domain served by the gateway
*/}}
{{- define "nginx-gateway-fabric.domain" -}}
{{- $global := default dict .Values.global -}}
{{- default "home.arpa" $global.domain -}}
{{- end -}}
