{{/*
Demo component Deployment template
*/}}
{{- define "otel-demo.deployment" }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "otel-demo.name" . }}-{{ .name }}
  labels:
    {{- include "otel-demo.labels" . | nindent 4 }}
spec:
  replicas: {{ .replicas | default .defaultValues.replicas }}
  revisionHistoryLimit: {{ .revisionHistoryLimit | default .defaultValues.revisionHistoryLimit }}
  selector:
    matchLabels:
      {{- include "otel-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "otel-demo.selectorLabels" . | nindent 8 }}
        {{- include "otel-demo.workloadLabels" . | nindent 8 }}
      {{- if .podAnnotations }}
      annotations:
        {{- toYaml .podAnnotations | nindent 8 }}
      {{- end }}
    spec:
      {{- if or .defaultValues.image.pullSecrets ((.imageOverride).pullSecrets) }}
      imagePullSecrets:
        {{- ((.imageOverride).pullSecrets) | default .defaultValues.image.pullSecrets | toYaml | nindent 8}}
      {{- end }}
      serviceAccountName: {{ include "otel-demo.serviceAccountName" .}}
      {{- $schedulingRules := .schedulingRules | default dict }}
      {{- if or .defaultValues.schedulingRules.nodeSelector $schedulingRules.nodeSelector}}
      nodeSelector:
        {{- $schedulingRules.nodeSelector | default .defaultValues.schedulingRules.nodeSelector | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.schedulingRules.affinity $schedulingRules.affinity}}
      affinity:
        {{- $schedulingRules.affinity | default .defaultValues.schedulingRules.affinity | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.schedulingRules.tolerations $schedulingRules.tolerations}}
      tolerations:
        {{- $schedulingRules.tolerations | default .defaultValues.schedulingRules.tolerations | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.podSecurityContext .podSecurityContext }}
      securityContext:
        {{- .podSecurityContext | default .defaultValues.podSecurityContext | toYaml | nindent 8 }}
      {{- end}}
      containers:
        - name: {{ .name }}
          image: '{{ ((.imageOverride).repository) | default .defaultValues.image.repository }}:{{ ((.imageOverride).tag) | default (printf "%s-%s" (default .Chart.AppVersion .defaultValues.image.tag) (replace "-" "" .name)) }}'
          imagePullPolicy: {{ ((.imageOverride).pullPolicy) | default .defaultValues.image.pullPolicy }}
          {{- if .command }}
          command:
            {{- .command | toYaml | nindent 10 -}}
          {{- end }}
          {{- if or .ports .service}}
          ports:
            {{- include "otel-demo.pod.ports" . | nindent 10 }}
          {{- end }}
          env:
            {{- include "otel-demo.pod.env" . | nindent 10 }}
          resources:
            {{- .resources | toYaml | nindent 12 }}
          {{- if or .defaultValues.securityContext .securityContext }}
          securityContext:
            {{- .securityContext | default .defaultValues.securityContext | toYaml | nindent 12 }}
          {{- end}}
          {{- if .livenessProbe }}
          livenessProbe:
            {{- .livenessProbe | toYaml | nindent 12 }}
          {{- end }}
          volumeMounts:
          {{- range .mountedConfigMaps }}
            - name: {{ .name | lower }}
              mountPath: {{ .mountPath }}
              {{- if .subPath }}
              subPath: {{ .subPath }}
              {{- end }}
          {{- end }}
            - name: shared-logs
              # Make sure this matches the filelog receiver in the OTEL config.
              mountPath: /logs

        - name: cx-otel-sidecar
          # image: otel/opentelemetry-collector-contrib:latest
          image: 104013952213.dkr.ecr.us-west-2.amazonaws.com/ianbowers/opentelemetry-collector-contrib:latest
          ports:
            - name: grpc
              containerPort: 4317
              protocol: TCP
            - name: http
              containerPort: 4318
              protocol: TCP
          command:
            - "/otelcol-contrib"
            - "--config=/conf/cx-otel-sidecar-config.yaml"
          env:
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "ClusterName=ian-bowers-eks-usw2"
            - name: CORALOGIX_DOMAIN
              value: "cx498.coralogix.com"
            - name: CX_APPLICATION
              value: "EKS"
            - name: CX_SUBSYSTEM
              value: {{ include "otel-demo.name" . }}-{{ .name }}
            # This is the private key for Coralogix. It should be stored in a secret. E.g.:
            #   kubectl create secret generic coralogix-keys -n $NAMESPACE --from-literal=PRIVATE_KEY=$PRIVATE_KEY
            - name: CORALOGIX_PRIVATE_KEY
              valueFrom:
                secretKeyRef:
                  name: coralogix-keys
                  key: PRIVATE_KEY
          # This is the shared volume between the application container and the OTEL sidecar container.
          volumeMounts:
            - name: cx-otel-sidecar-config-volume
              mountPath: /conf
            - name: shared-logs
              # Make sure this matches the filelog receiver in the OTEL config.
              mountPath: /logs

      volumes:
        # This is the shared volume between the application container and the OTEL sidecar container.
        - name: shared-logs
          emptyDir: {}

          # This is the volume that contains the OTEL config.
        - name: cx-otel-sidecar-config-volume
          configMap:
            name: cx-otel-sidecar-config
            items:
              - key: cx-otel-sidecar-config
                path: cx-otel-sidecar-config.yaml

        {{- range .mountedConfigMaps }}
        - name: {{ .name | lower}}
          configMap:
            {{- if .existingConfigMap }}
            name: {{ tpl .existingConfigMap $ }}
            {{- else }}
            name: {{ include "otel-demo.name" $ }}-{{ $.name }}-{{ .name | lower }}
            {{- end }}
        {{- end }}
      {{- if .initContainers }}
      initContainers:
        {{- tpl (toYaml .initContainers) . | nindent 8 }}
      {{- end}}
{{- end }}

{{/*
Demo component Service template
*/}}
{{- define "otel-demo.service" }}
{{- if or .ports .service}}
{{- $service := .service | default dict }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "otel-demo.name" . }}-{{ .name }}
  labels:
    {{- include "otel-demo.labels" . | nindent 4 }}
  {{- with $service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ $service.type | default "ClusterIP" }}
  ports:
    {{- if .ports }}
    {{- range $port := .ports }}
    - port: {{ $port.value }}
      name: {{ $port.name}}
      targetPort: {{ $port.value }}
    {{- end }}
    {{- end }}

    {{- if $service.port }}
    - port: {{ $service.port}}
      name: tcp-service
      targetPort: {{ $service.port }}
      {{- if $service.nodePort }}
      nodePort: {{ $service.nodePort }}
      {{- end }}
    {{- end }}
  selector:
    {{- include "otel-demo.selectorLabels" . | nindent 4 }}
{{- end}}
{{- end}}

{{/*
Demo component ConfigMap template
*/}}
{{- define "otel-demo.configmap" }}
{{- range .mountedConfigMaps }}
{{- if .data }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "otel-demo.name" $ }}-{{ $.name }}-{{ .name | lower }}
  labels:
        {{- include "otel-demo.labels" $ | nindent 4 }}
data:
  {{- .data | toYaml | nindent 2}}
{{- end}}
{{- end}}
{{- end}}

{{/*
Demo component Ingress template
*/}}
{{- define "otel-demo.ingress" }}
{{- $hasIngress := false}}
{{- if .ingress }}
{{- if .ingress.enabled }}
{{- $hasIngress = true }}
{{- end }}
{{- end }}
{{- $hasServicePorts := false}}
{{- if .service }}
{{- if .service.port }}
{{- $hasServicePorts = true }}
{{- end }}
{{- end }}
{{- if and $hasIngress (or .ports $hasServicePorts) }}
{{- $ingresses := list .ingress }}
{{- if .ingress.additionalIngresses }}
{{-   $ingresses := concat $ingresses .ingress.additionalIngresses -}}
{{- end }}
{{- range $ingresses }}
---
apiVersion: "networking.k8s.io/v1"
kind: Ingress
metadata:
  {{- if .name }}
  name: {{include "otel-demo.name" $ }}-{{ $.name }}-{{ .name | lower }}
  {{- else }}
  name: {{include "otel-demo.name" $ }}-{{ $.name }}
  {{- end }}
  labels:
    {{- include "otel-demo.labels" $ | nindent 4 }}
  {{- if .annotations }}
  annotations:
    {{ toYaml .annotations | nindent 4 }}
  {{- end }}
spec:
  {{- if .ingressClassName }}
  ingressClassName: {{ .ingressClassName }}
  {{- end -}}
  {{- if .tls }}
  tls:
    {{- range .tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      {{- with .secretName }}
      secretName: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
