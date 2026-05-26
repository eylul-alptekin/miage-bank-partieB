{{- define "miage-bank.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "miage-bank.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "miage-bank.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "miage-bank.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "miage-bank.selectorLabels" -}}
app.kubernetes.io/name: {{ include "miage-bank.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "miage-bank.serviceAccountName" -}}
{{ include "miage-bank.fullname" . }}-sa
{{- end }}
