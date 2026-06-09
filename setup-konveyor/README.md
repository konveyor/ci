# Setup Konveyor Action

Composite action that starts minikube, loads images from artifacts, builds an operator bundle if needed, and installs Konveyor.

## Usage

```yaml
- name: Setup Konveyor
  uses: konveyor/ci/setup-konveyor@main
  with:
    artifact: my-images-artifact
    operator_bundle: quay.io/konveyor/tackle2-operator-bundle:latest
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `artifact` | Name of artifact containing custom images to load | No | `""` |
| `operator_bundle` | Image URI for operator-bundle. If empty, a bundle will be built | No | `""` |
| `operator_bundle_fallback` | Fallback operator bundle URI used when building custom bundle | No | `""` |
| `base_tag` | Tag for operator image to build custom bundle on top of | No | `latest` |
| `oauth_proxy` | Image URI for oauth_proxy | No | `""` |
| `tackle_hub` | Image URI for tackle-hub | No | `""` |
| `tackle_postgres` | Image URI for tackle-postgres | No | `""` |
| `keycloak_sso` | Image URI for keycloak_sso | No | `""` |
| `keycloak_init` | Image URI for keycloak_init | No | `""` |
| `tackle_ui` | Image URI for tackle-ui | No | `""` |
| `addon_analyzer` | Image URI for analyzer addon | No | `""` |
| `addon_discovery` | Image URI for discovery addon | No | `""` |
| `namespace` | Namespace for the konveyor install | No | `""` |
| `tackle_cr` | Full YAML/JSON string representing the Tackle resource | No | Default Tackle CR |

## What it does

1. Sets up docker buildx (if artifact is provided)
2. Starts minikube with max memory/cpus
3. Downloads and loads images from artifact into minikube
4. Makes operator bundle (if `operator_bundle` is empty)
5. Pushes the bundle to registry
6. Installs Konveyor using the operator
