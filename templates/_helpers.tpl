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
{{- default (printf "%s-git" ((include "static-site.fullname" .) | trunc 59 | trimSuffix "-")) .Values.gitCredentials.secretName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.nginxConfigName" -}}
{{- printf "%s-nginx" ((include "static-site.fullname" .) | trunc 57 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.pvcName" -}}
{{- default (printf "%s-site" ((include "static-site.fullname" .) | trunc 58 | trimSuffix "-")) .Values.persistence.existingClaim | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.workflowServiceAccountName" -}}
{{- default (printf "%s-workflow" ((include "static-site.fullname" .) | trunc 54 | trimSuffix "-")) .Values.workflow.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.eventsServiceAccountName" -}}
{{- default (printf "%s-events" ((include "static-site.fullname" .) | trunc 56 | trimSuffix "-")) .Values.events.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.workflowTemplateName" -}}
{{- printf "%s-build" ((include "static-site.fullname" .) | trunc 57 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.eventSourceName" -}}
{{- printf "%s-github" ((include "static-site.fullname" .) | trunc 56 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.eventsNamespace" -}}
{{- default .Release.Namespace .Values.events.namespace }}
{{- end }}

{{- define "static-site.eventsSecretsRoleName" -}}
{{- printf "%s-events-secrets" ((include "static-site.fullname" .) | trunc 48 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.eventsSubmitRoleName" -}}
{{- printf "%s-events-submit" ((include "static-site.fullname" .) | trunc 49 | trimSuffix "-") }}
{{- end }}
