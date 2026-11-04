{{/* Image reference: prefer immutable digest (promotion), fall back to tag (local dev). */}}
{{- define "platform-app.image" -}}
{{- if .digest -}}
{{ .repository }}@{{ .digest }}
{{- else -}}
{{ .repository }}:{{ required "image.tag or image.digest is required" .tag }}
{{- end -}}
{{- end -}}

{{- define "platform-app.labels" -}}
app.kubernetes.io/part-of: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
platform.io/tenant: {{ .Values.tenant.id | quote }}
platform.io/deployment-mode: {{ .Values.tenant.mode | quote }}
platform.io/data-residency: {{ .Values.tenant.residency | quote }}
{{- end -}}

{{- define "platform-app.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "platform-app.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{- define "platform-app.redisUrl" -}}
{{- .Values.redisUrl | default (printf "redis://%s-redis:6379/0" .Release.Name) -}}
{{- end -}}

{{/* Residency: pin pods to nodes whose region label is in the allowed list. */}}
{{- define "platform-app.residencyAffinity" -}}
{{- if .Values.tenant.enforceRegion }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/region
              operator: In
              values:
                {{- toYaml (required "tenant.allowedRegions is required when enforceRegion=true" .Values.tenant.allowedRegions) | nindent 16 }}
{{- end }}
{{- end -}}
