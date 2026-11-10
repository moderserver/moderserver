{{/*
Expand the name of the chart.
*/}}
{{- define "common.names.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "common.names.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Construct the full hostname: <subdomain>.<clusterDomain>
*/}}
{{- define "common.names.host" -}}
{{- $subdomain := default .Chart.Name .Values.subdomain -}}
{{- $global := default dict .Values.global -}}
{{- $domain := default "home.arpa" $global.domain -}}
{{- printf "%s.%s" $subdomain $domain -}}
{{- end -}}
