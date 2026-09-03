{{- define "static-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "static-site.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "static-site.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "static-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "static-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "static-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "static-site.gitSecretName" -}}
{{- if .Values.gitCredentials.onePassword.enabled -}}
{{- printf "%s-git" .Release.Name -}}
{{- else -}}
{{- required "gitCredentials.secretName is required when OnePasswordItem provisioning is disabled" .Values.gitCredentials.secretName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "static-site.nginxConfigName" -}}
{{- printf "%s-nginx" ((include "static-site.fullname" .) | trunc 57 | trimSuffix "-") }}
{{- end }}
