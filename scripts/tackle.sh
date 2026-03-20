#!/usr/bin/env bash
#
# tackle.sh - Convenience CLI to manage local Tackle Hub + Kind cluster
#             for koncur testing
#
# Usage:
#   ./tackle.sh install [--auth] [--port=8080] [--tlsPort=8443]
#   ./tackle.sh uninstall
#   ./tackle.sh help
#
# Image overrides:
#   Set environment variables to use custom images (same as Makefile):
#     HUB
#     ANALYZER_ADDON
#     CSHARP_PROVIDER_IMG
#     GENERIC_PROVIDER_IMG
#     JAVA_PROVIDER_IMG
#     KANTRA_FQIN
#     DISCOVERY_ADDON
#     PLATFORM_ADDON
#

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────────────────────────────
# Configurable defaults (override via env vars like in Makefile)
# ──────────────────────────────────────────────────────────────────────────────

hubImage="${HUB:-quay.io/konveyor/tackle2-hub:latest}"
analyzerImage="${ANALYZER_ADDON:-quay.io/konveyor/tackle2-addon-analyzer:latest}"
csharpProvider="${CSHARP_PROVIDER_IMG:-quay.io/konveyor/c-sharp-provider:latest}"
genericProvider="${GENERIC_PROVIDER_IMG:-quay.io/konveyor/generic-external-provider:latest}"
javaProvider="${JAVA_PROVIDER_IMG:-quay.io/konveyor/java-external-provider:latest}"
kantraImage="${KANTRA_FQIN:-quay.io/konveyor/kantra:latest}"
discoveryImage="${DISCOVERY_ADDON:-quay.io/konveyor/tackle2-addon-discovery:latest}"
platformImage="${PLATFORM_ADDON:-quay.io/konveyor/tackle2-addon-platform:latest}"

readonly defaultClusterName="koncur-test"
readonly defaultNamespace="konveyor-tackle"
readonly defaultHostPort=8080
readonly defaultHostPortTls=8443

readonly adminUser="admin"
readonly adminPass="Passw0rd!"

# ──────────────────────────────────────────────────────────────────────────────
# Globals
# ──────────────────────────────────────────────────────────────────────────────

clusterName="$defaultClusterName"
namespace="$defaultNamespace"
hostPort="$defaultHostPort"
hostPortTls="$defaultHostPortTls"
authEnabled=false

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

die() {
  echo "ERROR: $*" >&2
  exit 1
}

step() {
  printf "\n\033[1;34m==> %s\033[0m\n" "$*"
}

success() {
  printf "\n\033[1;32m✔ %s\033[0m\n" "$*"
}

runKubectl() {
  command kubectl \
    --context="kind-${clusterName}" \
    "$@"
}

waitFor() {
  local timeout="$1"
  shift
  local what="$1"
  shift
  local cmd=("$@")

  step "Waiting for ${what} (timeout ${timeout}s)..."
  for ((i=1; i<=timeout; i+=5)); do
    if "${cmd[@]}" &>/dev/null; then
      success "${what} is ready"
      return 0
    fi
    sleep 5
    printf "."
  done
  die "Timeout waiting for ${what}"
}

getKeycloakPod() {
  runKubectl get pods \
    -n "${namespace}" \
    -l app.kubernetes.io/name=tackle-keycloak-sso \
    -o name \
    --no-headers \
    | head -n 1
}

# ──────────────────────────────────────────────────────────────────────────────
# Core functions – small & focused
# ──────────────────────────────────────────────────────────────────────────────

ensureDirectories() {
  mkdir -p -m 777 \
    cache \
    .koncur/config
}

createKindConfig() {
  local configFile=".koncur/config/kind-config.yaml"

  cat > "$configFile" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: ${hostPort}
        protocol: TCP
        listenAddress: "0.0.0.0"
      - containerPort: 443
        hostPort: ${hostPortTls}
        protocol: TCP
        listenAddress: "0.0.0.0"
    extraMounts:
      - hostPath: ./cache
        containerPath: /cache
EOF
}

createKindCluster() {
  createKindConfig
  kind create cluster \
    --name "${clusterName}" \
    --config .koncur/config/kind-config.yaml
}

configureLocalPathStorage() {
  step "Patching local-path-storage to use /cache ..."

  runKubectl patch configmap local-path-config \
    -n local-path-storage \
    --type=merge \
    -p "$(cat <<'EOF'
{"data":{"config.json":"{\"nodePathMap\":[],\"sharedFileSystemPath\":\"/cache\"}"}}
EOF
)"

  runKubectl rollout restart deployment local-path-provisioner \
    -n local-path-storage

  runKubectl rollout status deployment local-path-provisioner \
    -n local-path-storage \
    --timeout=60s
}

installIngressNginx() {
  step "Installing ingress-nginx ..."
  runKubectl apply \
    -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml

  waitFor 300 "ingress-nginx controller" \
    runKubectl wait \
    --namespace ingress-nginx \
    --for=condition=ready \
    pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=10s
}

installCluster() {
  step "Creating Kind cluster '${clusterName}' ..."
  createKindCluster
  configureLocalPathStorage
  installIngressNginx
}

installOlm() {
  step "Installing Operator Lifecycle Manager ..."
  curl -sL \
    https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.38.0/install.sh \
    | bash -s v0.38.0 || true

  waitFor 180 "OLM pods" \
    runKubectl wait \
    --for=condition=ready \
    pod \
    -l app=olm-operator \
    -n olm \
    --timeout=60s

  waitFor 180 "catalog pods" \
    runKubectl wait \
    --for=condition=ready \
    pod \
    -l app=catalog-operator \
    -n olm \
    --timeout=60s
}

installTackleOperator() {
  step "Installing Tackle operator ..."
  runKubectl apply \
    -f https://raw.githubusercontent.com/konveyor/tackle2-operator/main/tackle-k8s.yaml

  waitFor 300 "Tackle CRD" \
    runKubectl get crd tackles.tackle.konveyor.io

  waitFor 300 "Tackle operator pod" \
    runKubectl wait \
    --namespace "${namespace}" \
    --for=condition=ready \
    pod \
    --selector=name=tackle-operator \
    --timeout=10s
}

createCachePv() {
  step "Creating hostPath PV for Tackle cache ..."
  mkdir -p -m 777 cache/hub-cache

  cat <<EOF | runKubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: tackle-cache-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /cache/hub-cache
    type: DirectoryOrCreate
EOF
}

applyTackleCr() {
  local authValue="false"
  $authEnabled && authValue="true"

  step "Applying Tackle CR (auth=${authValue}) ..."

  cat <<EOF | runKubectl apply -f -
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: tackle
  namespace: ${namespace}
spec:
  cache_storage_class: "manual"
  cache_data_volume_size: "10Gi"
  rwx_supported: "true"
  hub_image_fqin: ${hubImage}
  analyzer_fqin: ${analyzerImage}
  provider_c_sharp_image_fqin: ${csharpProvider}
  provider_python_image_fqin: ${genericProvider}
  provider_nodejs_image_fqin: ${genericProvider}
  provider_java_image_fqin: ${javaProvider}
  kantra_fqin: ${kantraImage}
  language_discovery_fqin: ${discoveryImage}
  platform_fqin: ${platformImage}
  feature_auth_required: "${authValue}"
EOF
}

waitForHubReady() {
  waitFor 900 "Tackle Hub pod" \
    runKubectl wait \
    --namespace "${namespace}" \
    --for=condition=ready \
    pod \
    -l app.kubernetes.io/name=tackle-hub \
    --timeout=30s
}

# ──────────────────────────────────────────────────────────────────────────────
# Keycloak configuration – now properly decomposed
# ──────────────────────────────────────────────────────────────────────────────

waitForKeycloakDeployment() {
  waitFor 600 "Keycloak deployment" \
    runKubectl get deployment tackle-keycloak-sso \
    -n "${namespace}"
}

waitForKeycloakPod() {
  waitFor 600 "Keycloak pod" \
    runKubectl wait \
    --namespace "${namespace}" \
    --for=condition=ready \
    pod \
    -l app.kubernetes.io/name=tackle-keycloak-sso \
    --timeout=30s
}

applyKeycloakNetworkPolicy() {
  step "Creating NetworkPolicy to allow ingress-nginx → Keycloak ..."
  cat <<EOF | runKubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tackle-keycloak-ingress
  namespace: ${namespace}
spec:
  podSelector:
    matchLabels:
      role: tackle-keycloak-sso
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: 8080
          protocol: TCP
        - port: 8443
          protocol: TCP
EOF
}

configureKeycloakHostname() {
  step "Configuring Keycloak hostname for local access ..."

  runKubectl set env deployment/tackle-keycloak-sso \
    -n "${namespace}" \
    KC_HOSTNAME="https://localhost:${hostPortTls}/auth" \
    KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true

  runKubectl patch deployment tackle-keycloak-sso \
    -n "${namespace}" \
    --type=json \
    -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/args\", \"value\": [\"-Djgroups.dns.query=mta-kc-discovery.openshift-mta\", \"--verbose\", \"start\", \"--hostname=https://localhost:${hostPortTls}/auth\", \"--hostname-backchannel-dynamic=true\"]}]"

  runKubectl rollout status deployment/tackle-keycloak-sso \
    -n "${namespace}" \
    --timeout=180s
}

disableHubPasswordUpdate() {
  step "Disabling password update prompt on Tackle Hub ..."

  runKubectl set env deployment/tackle-hub \
    -n "${namespace}" \
    KEYCLOAK_REQ_PASS_UPDATE=false

  runKubectl rollout status deployment/tackle-hub \
    -n "${namespace}" \
    --timeout=120s
}

configureAdminUserInKeycloak() {
  step "Configuring admin user in Keycloak ..."

  local kcPod
  kcPod=$(getKeycloakPod)

  local kcPass
  kcPass=$(runKubectl get secret tackle-keycloak-sso \
    -n "${namespace}" \
    -o jsonpath='{.data.password}' \
    | base64 -d)

  runKubectl exec "${kcPod}" \
    -n "${namespace}" \
    -- /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080/auth \
    --realm master \
    --user admin \
    --password "${kcPass}"

  local adminUserId=""
  for ((i=1; i<=30; i++)); do
    adminUserId=$(runKubectl exec "${kcPod}" \
      -n "${namespace}" \
      -- /opt/keycloak/bin/kcadm.sh get users \
      -r tackle \
      -q username="${adminUser}" \
      --fields id 2>/dev/null \
      | grep -o '"id":"[^"]*"' \
      | cut -d'"' -f4 || true)

    if [[ -n "${adminUserId}" ]]; then
      break
    fi
    sleep 5
  done

  if [[ -z "${adminUserId}" ]]; then
    die "Failed to find admin user '${adminUser}' in Keycloak after 150s"
  fi

  runKubectl exec "${kcPod}" \
    -n "${namespace}" \
    -- /opt/keycloak/bin/kcadm.sh update "users/${adminUserId}" \
    -r tackle \
    -s 'requiredActions=[]'
}

configureKeycloak() {
  waitForKeycloakDeployment
  waitForKeycloakPod
  applyKeycloakNetworkPolicy
  configureKeycloakHostname
  disableHubPasswordUpdate
  configureAdminUserInKeycloak
  success "Keycloak configured. Admin user ready (user: ${adminUser}, pass: ${adminPass})"
}

startPortForward() {
  local svcPort=8080
  local localPort=8081

  echo ""
  if $authEnabled; then
    echo "Tackle Hub installed WITH authentication."
    echo "Access UI:  https://localhost:${hostPortTls}  (self-signed cert - accept warning)"
    echo "User:       ${adminUser}"
    echo "Password:   ${adminPass}"
  else
    echo "Tackle Hub installed (no auth)."
    echo "Access UI:  http://localhost:${hostPort}"
  fi
  echo ""

  echo "Starting port-forward to Tackle Hub service..."
  echo "API → http://localhost:${localPort}"
  echo "UI  → http://localhost:${localPort}/hub"
  echo ""
  echo "Press Ctrl+C to stop"

  runKubectl port-forward \
    -n "${namespace}" \
    svc/tackle-hub \
    "${localPort}:${svcPort}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Subcommands
# ──────────────────────────────────────────────────────────────────────────────

cmdInstall() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auth)
        authEnabled=true
        shift
        ;;
      --no-auth)
        authEnabled=false
        shift
        ;;
      --port=*)
        hostPort="${1#*=}"
        shift
        ;;
      --tlsPort=*)
        hostPortTls="${1#*=}"
        shift
        ;;
      --cluster=*)
        clusterName="${1#*=}"
        shift
        ;;
      --help|-h)
        cmdHelp
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  ensureDirectories

  step "Resolved images:"
  echo "  Hub         : ${hubImage}"
  echo "  Analyzer    : ${analyzerImage}"
  echo "  C# Provider : ${csharpProvider}"
  echo "  Generic     : ${genericProvider}"
  echo "  Java        : ${javaProvider}"
  echo "  Kantra      : ${kantraImage}"
  echo "  Discovery   : ${discoveryImage}"
  echo "  Platform    : ${platformImage}"

  installCluster
  installOlm
  installTackleOperator
  createCachePv
  applyTackleCr
  waitForHubReady

  if $authEnabled; then
    configureKeycloak
  fi

  success "Tackle Hub is ready!"

  startPortForward
}

cmdUninstall() {
  step "Removing Tackle CR and namespace ..."

  runKubectl delete \
    --ignore-not-found=true \
    tackle \
    tackle \
    -n "${namespace}" || true

  runKubectl delete \
    --ignore-not-found=true \
    namespace \
    "${namespace}" || true

  step "Deleting Kind cluster '${clusterName}' ..."

  kind delete cluster \
    --name "${clusterName}"

  success "Cleanup complete"
}

cmdHelp() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install     Create kind cluster + install Tackle Hub + start port-forward
  uninstall   Remove Tackle and delete kind cluster
  help        Show this help

Install options:
  --auth              Enable Keycloak authentication
  --no-auth           Disable authentication (default)
  --port=8080         Host port for HTTP ingress
  --tlsPort=8443      Host port for HTTPS ingress
  --cluster=NAME      Kind cluster name (default: ${defaultClusterName})

Image overrides:
  Set these env vars to use custom images (same names as Makefile):
    HUB
    ANALYZER_ADDON
    CSHARP_PROVIDER_IMG
    GENERIC_PROVIDER_IMG
    JAVA_PROVIDER_IMG
    KANTRA_FQIN
    DISCOVERY_ADDON
    PLATFORM_ADDON

EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Main entry point
# ──────────────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  cmdHelp
  exit 1
fi

case "$1" in
  install)
    shift
    cmdInstall "$@"
    ;;
  uninstall)
    shift
    cmdUninstall "$@"
    ;;
  help|--help|-h)
    cmdHelp
    ;;
  *)
    die "Unknown command: $1. Run '$(basename "$0") help' for usage."
    ;;
esac

