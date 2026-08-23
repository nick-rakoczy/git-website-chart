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

{{- define "static-site.pipelineServiceAccountName" -}}
{{- default (printf "%s-pipeline" ((include "static-site.fullname" .) | trunc 54 | trimSuffix "-")) .Values.pipeline.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.triggersServiceAccountName" -}}
{{- default (printf "%s-triggers" ((include "static-site.fullname" .) | trunc 54 | trimSuffix "-")) .Values.triggers.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.pipelineName" -}}
{{- printf "%s-build" ((include "static-site.fullname" .) | trunc 57 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.eventListenerName" -}}
{{- printf "%s-github" ((include "static-site.fullname" .) | trunc 56 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.eventListenerServiceName" -}}
{{- printf "el-%s" (include "static-site.eventListenerName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "static-site.triggersNamespace" -}}
{{- default .Release.Namespace .Values.triggers.namespace }}
{{- end }}

{{- define "static-site.triggersRoleName" -}}
{{- printf "%s-triggers" ((include "static-site.fullname" .) | trunc 41 | trimSuffix "-") }}
{{- end }}

{{- define "static-site.gitSyncStep" -}}
- name: git-sync
  image: "{{ .Values.pipeline.git.image.repository }}:{{ .Values.pipeline.git.image.tag }}"
  imagePullPolicy: {{ .Values.pipeline.git.image.pullPolicy }}
  args:
    - {{ printf "--repo=%s" .Values.site.repository | quote }}
    - {{ "--ref=$(params.revision)" | quote }}
    - --root=/workspace
    - --link=source
    - --one-time=true
    - --depth={{ .Values.pipeline.git.depth }}
    - --submodules={{ ternary "off" "recursive" .Values.pipeline.git.disableSubmodules }}
    - --git-gc=off
    {{- if eq .Values.gitCredentials.authentication "ssh" }}
    - --ssh-key-file=/etc/git-secret/ssh
    - --ssh-known-hosts=true
    - --ssh-known-hosts-file=/etc/git-secret/known_hosts
    {{- else if eq .Values.gitCredentials.authentication "githubApp" }}
    - --github-app-private-key-file=/etc/git-secret/private-key.pem
    {{- end }}
  {{- if eq .Values.gitCredentials.authentication "githubApp" }}
  env:
    - name: GITSYNC_GITHUB_APP_APPLICATION_ID
      valueFrom:
        secretKeyRef:
          name: {{ include "static-site.gitSecretName" . }}
          key: {{ .Values.gitCredentials.githubApp.applicationIdKey }}
    - name: GITSYNC_GITHUB_APP_INSTALLATION_ID
      valueFrom:
        secretKeyRef:
          name: {{ include "static-site.gitSecretName" . }}
          key: {{ .Values.gitCredentials.githubApp.installationIdKey }}
  {{- end }}
  volumeMounts:
    - name: source
      mountPath: /workspace
    - name: git-credentials
      mountPath: /etc/git-secret
      readOnly: true
{{- end }}
