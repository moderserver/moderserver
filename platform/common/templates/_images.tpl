{{/*
Content-addressed image tag: <appVersion>-<hash of the image build inputs>.

The build inputs are the Dockerfile* and *.sh files at the root of the chart.
hack/lib/common.sh (component_image_tag) computes the same value when building,
so a change to a Dockerfile (base image bump, patch, new binary) always yields a
new tag and rolls out to nodes, while an unchanged image keeps its tag.
*/}}
{{- define "common.images.tag" -}}
{{- $inputs := "" -}}
{{- range $path, $_ := .Files.Glob "Dockerfile*" -}}
{{- $inputs = printf "%s%s" $inputs ($.Files.Get $path) -}}
{{- end -}}
{{- range $path, $_ := .Files.Glob "*.sh" -}}
{{- $inputs = printf "%s%s" $inputs ($.Files.Get $path) -}}
{{- end -}}
{{- printf "%s-%s" (.Chart.AppVersion | replace "+" "-") (sha256sum $inputs | trunc 12) -}}
{{- end -}}

{{/*
Image registry shared by all ModerServer platform images
*/}}
{{- define "common.images.registry" -}}
{{- $global := default dict .Values.global -}}
{{- default "ghcr.io/moderserver" $global.imageRegistry -}}
{{- end -}}

{{/*
Full image reference for a platform image.
Usage: {{ include "common.images.ref" (dict "ctx" . "name" "argocd-server") }}
*/}}
{{- define "common.images.ref" -}}
{{- printf "%s/%s:%s" (include "common.images.registry" .ctx) .name (include "common.images.tag" .ctx) -}}
{{- end -}}
