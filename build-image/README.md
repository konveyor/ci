# Build Image Action

A composite GitHub Action for building container images using Podman with built-in caching and artifact management.

## Features

- Builds container images using Podman
- Automatic build caching using GitHub Actions cache
- Support for loading base images from artifacts
- Saves built images as artifacts for use in subsequent jobs
- Customizable build arguments and context
- Optional repository checkout

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `repo` | The name of the repository to build (e.g., "konveyor/analyzer-lsp") | Yes | - |
| `ref` | The branch, tag or ref to use during checkout of the repository (e.g., "main") | No | `main` |
| `base_image` | The name of the base image to load into podman before building. This will use the same tag to test with | No | - |
| `image_name` | The name of the image to build (e.g., "my-app", "quay.io/myorg/my-app"). Must not contain colons (:) or @ characters. Max 255 chars. | Yes | - |
| `image_tag` | The tag for the image (e.g., "latest", "v1.0.0"). Must not contain `:`, `/`, or `@`. Cannot start with `.` or `-`. Max 128 chars. | Yes | `latest` |
| `dockerfile_path` | Path to the Dockerfile or Containerfile | No | `Dockerfile` |
| `build_context` | Build context directory | No | `.` |
| `checked_out` | If the repository is already checked out | No | `false` |
| `build_args` | Build arguments to pass to podman build (e.g., "ARG1=value1 ARG2=value2") | No | `""` |
| `cache-key-file` | File that will determine if there is a cache, based on its hash | No | `go.sum` |

## Outputs

| Output | Description |
|--------|-------------|
| `image_name` | The full name of the built image |
| `image_tag` | The tag of the built image |
| `tar_file` | Path to the tar file containing the image |
| `file_name` | The artifact file name |

## Usage Examples

### Basic Usage

Build an image from a Konveyor repository:

```yaml
- name: Build analyzer-lsp image
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    ref: main
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest
```

### Build with Custom Dockerfile Path

Build an image using a specific Dockerfile:

```yaml
- name: Build provider image
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/java-external-provider
    ref: main
    image_name: quay.io/konveyor/java-external-provider
    image_tag: v0.1.0
    dockerfile_path: external-providers/java-external-provider/Dockerfile
    build_context: .
```

### Build with Base Image from Artifact

Build an image that depends on a previously built base image:

```yaml
- name: Build base image
  id: build-base
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    ref: main
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest

- name: Build provider image using base
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/java-external-provider
    ref: main
    image_name: quay.io/konveyor/java-external-provider
    image_tag: latest
    base_image: ${{ steps.build-base.outputs.file_name }}
```

### Build with Build Arguments

Pass build arguments to the container build:

```yaml
- name: Build with build args
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    ref: main
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest
    build_args: |
      VERSION=1.0.0
      BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

### Build from Already Checked Out Repository

If your workflow already checked out the repository:

```yaml
- name: Checkout code
  uses: actions/checkout@v4

- name: Build image
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest
    checked_out: true
```

### Re-checkout After Building a Different Repository

**Important Note:** If you build an image from a different repository (without `checked_out: true`), the action will checkout that repository, changing your working directory. You'll need to re-checkout your original repository to continue working with it.

```yaml
- name: Checkout current repository
  uses: actions/checkout@v4

- name: Run tests or other steps
  run: make test

- name: Build image from different repository
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    ref: main
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest
    # checked_out is false, so analyzer-lsp will be checked out

- name: Re-checkout current repository
  uses: actions/checkout@v4
  # This restores your original repository context

- name: Continue with current repository
  run: make build
```

### Custom Cache Key

Use a different file for cache invalidation:

```yaml
- name: Build image with custom cache
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/tackle2-hub
    ref: main
    image_name: quay.io/konveyor/tackle2-hub
    image_tag: latest
    cache-key-file: package-lock.json
```

### Using Build Cache in Your Dockerfile

To take advantage of the build cache, you need to add cache mounts to your RUN commands in the Dockerfile. The cache is stored at `/var/tmp/buildah-cache-1001`. Here's an example based on the analyzer-lsp Dockerfile:

**Go Example:**

```dockerfile
FROM registry.access.redhat.com/ubi9/go-toolset:1.23 as builder

USER 0
WORKDIR /analyzer-lsp

# Copy source files
COPY go.mod go.sum ./
COPY . .

# Fix cache ownership if it was populated by previous builds
RUN --mount=type=cache,id=gomod,uid=1001,gid=0,mode=0777,target=/opt/app-root/src/go/pkg/mod \
    chown -R 1001:0 /opt/app-root/src/go/pkg/mod && \
    chmod -R g+w /opt/app-root/src/go/pkg/mod

USER 1001

# Build with cache mount for Go modules
RUN --mount=type=cache,id=gomod,uid=1001,gid=0,mode=0777,target=/opt/app-root/src/go/pkg/mod \
    make build
```

```yaml
- name: Build Go image with cache
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/analyzer-lsp
    ref: main
    image_name: quay.io/konveyor/analyzer-lsp
    image_tag: latest
    cache-key-file: go.sum  # Cache invalidates when go.sum changes
```

**Maven Example:**

```dockerfile
FROM maven:3.9-eclipse-temurin-17 as builder

WORKDIR /app
COPY pom.xml ./
COPY src ./src

# Build with cache mount for Maven dependencies
RUN --mount=type=cache,id=maven,uid=1000,gid=1000,mode=0777,target=/root/.m2/repository \
    mvn clean package -DskipTests
```

```yaml
- name: Build Maven image with cache
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/tackle2-hub
    ref: main
    image_name: quay.io/konveyor/tackle2-hub
    image_tag: latest
    cache-key-file: pom.xml  # Cache invalidates when pom.xml changes
```

**npm Example:**

```dockerfile
FROM node:18 as builder

WORKDIR /app
COPY package.json package-lock.json ./
COPY . .

# Install with cache mount for npm cache
RUN --mount=type=cache,id=npm,uid=1000,gid=1000,mode=0777,target=/root/.npm \
    npm ci && npm run build
```

```yaml
- name: Build Node image with cache
  uses: konveyor/ci/build-image@main
  with:
    repo: konveyor/my-node-app
    ref: main
    image_name: quay.io/konveyor/my-node-app
    image_tag: latest
    cache-key-file: package-lock.json  # Cache invalidates when package-lock.json changes
```

**Key points:**
- The `--mount=type=cache` directive creates a cache mount during the build
- `id=gomod` is a unique identifier for this cache (use different IDs for different cache types)
- `uid=1001,gid=0,mode=0777` sets proper permissions for the cache directory
- `target=/opt/app-root/src/go/pkg/mod` specifies where the cache is mounted (language-specific)
- The cache persists between builds and is keyed by the hash of your `cache-key-file`
- **Important:** Set `cache-key-file` to match your dependency lock file to ensure cache invalidation when dependencies change

Common cache configurations:
- **Go modules:** target `/opt/app-root/src/go/pkg/mod`, cache-key-file `go.sum`
- **npm:** target `/root/.npm`, cache-key-file `package-lock.json`
- **Maven:** target `/root/.m2/repository`, cache-key-file `pom.xml`
- **pip:** target `/root/.cache/pip`, cache-key-file `requirements.txt`

## Complete Workflow Example

Here's a complete workflow example that builds multiple images:

```yaml
name: Build Images

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-images:
    runs-on: ubuntu-latest
    steps:
      - name: Build analyzer-lsp
        uses: konveyor/ci/build-image@main
        with:
          repo: konveyor/analyzer-lsp
          ref: main
          image_name: quay.io/konveyor/analyzer-lsp
          image_tag: ${{ github.sha }}

      - name: Build java-external-provider
        uses: konveyor/ci/build-image@main
        with:
          repo: konveyor/java-external-provider
          ref: main
          image_name: quay.io/konveyor/java-external-provider
          image_tag: ${{ github.sha }}
          base_image: quay.io_konveyor_analyzer-lsp--${{ github.sha }}

      - name: Build generic-external-provider
        uses: konveyor/ci/build-image@main
        with:
          repo: konveyor/generic-external-provider
          ref: main
          image_name: quay.io/konveyor/generic-external-provider
          image_tag: ${{ github.sha }}
```

## How It Works

1. **Checkout**: Optionally checks out the specified repository if not already checked out
2. **Caching**: Sets up build cache using the hash of the specified cache key file
3. **Base Image**: If specified, downloads and loads the base image artifact into Podman
4. **Build**: Builds the container image using Podman with the specified parameters
5. **Save**: Saves the built image to a tar file
6. **Upload**: Uploads the image tar file as a GitHub Actions artifact with 1-day retention
7. **Summary**: Outputs build information to the GitHub Actions step summary

## Notes

- Images are saved as artifacts with a retention period of 1 day
- Artifact names are generated from the image name and tag with special characters replaced
- The action uses Podman for building images, ensuring rootless container builds
- Build cache is stored at `/var/tmp/buildah-cache-1001` and keyed by image name and cache file hash
- **Cache Key File**: The `cache-key-file` input specifies which file's hash is used for cache invalidation. If the specified file doesn't exist in your repository, the cache key will not include a hash component, which may reduce cache effectiveness. Ensure you set `cache-key-file` to an appropriate dependency lock file for your project (e.g., `go.sum` for Go, `package-lock.json` for npm, `pom.xml` for Maven, `requirements.txt` for Python)
- **Image Name Restrictions**: Per OCI Distribution Specification:
  - `image_name`: Must not contain `:` or `@` characters. Maximum 255 characters.
  - `image_tag`: Must not contain `:`, `/`, or `@` characters. Cannot start with `.` or `-`. Maximum 128 characters.
  - Separate the image registry/name from the tag/digest properly across these two inputs

## License

This action is part of the Konveyor CI tools.
