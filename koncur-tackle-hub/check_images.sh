#!/bin/bash

set -e

REQUIRED_IMAGES=(
    "quay.io/konveyor/tackle2-hub"
    "quay.io/konveyor/tackle2-addon-analyzer"
    "quay.io/konveyor/tackle2-addon-discovery"
    "quay.io/konveyor/tackle2-addon-platform"
    "quay.io/konveyor/c-sharp-provider"
    "quay.io/konveyor/java-external-provider"
    "quay.io/konveyor/go-external-provider"
    "quay.io/konveyor/python-external-provider"
    "quay.io/konveyor/nodejs-external-provider"
)
hub_regex=".*tackle2-hub.*"
addon_regex=".*tackle2-addon-analyzer.*"
addon_discovery=".*tackle2-addon-discovery.*"
addon_platform=".*tackle2-addon-platform.*"
kantra_image_regex=".*kantra.*"
java_provider_image_regex=".*java(-external)?-provider.*"
c_sharp_provider_image_regex=".*c-sharp-provider.*"
go_provider_image_regex=".*go(-external)?-provider.*"
python_provider_image_regex=".*python(-external)?-provider.*"
nodejs_provider_image_regex=".*nodejs(-external)?-provider.*"

echo "Checking for required images in Kind cluster..."
echo "------------------------------------------------------------"

# Get list of all images in Kind cluster
IMAGES=$(docker exec koncur-test-control-plane crictl images -o json | jq -r '.images[] | .repoTags[]' 2>/dev/null)

MISSING=()
FOUND=()
FOUND_TAG=""

if [ -z "$IMAGES" ]; then
    echo "No images found in Kind cluster."
    MISSING=("${REQUIRED_IMAGES[@]}")
else
    # Check each required image
    for required in "${REQUIRED_IMAGES[@]}"; do
        if echo "$IMAGES" | grep -qi "$required"; then
            MATCHED=$(echo "$IMAGES" | grep -i "$required" | head -n 1)
            FOUND+=("$required: $MATCHED")

            # Extract tag from the first found image
            if [ -z "$FOUND_TAG" ]; then
                FOUND_TAG=$(echo "$MATCHED" | cut -d':' -f2)
                echo "Extracted tag from found image: $FOUND_TAG"
            fi
        else
            MISSING+=("$required")
        fi
    done
fi

# Display found images
if [ ${#FOUND[@]} -gt 0 ]; then
    echo "Found images:"
    for img in "${FOUND[@]}"; do
        echo "  ✓ $img"
    done
fi

# Display missing images
if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "Missing images:"
    for img in "${MISSING[@]}"; do
        echo "  ✗ $img"
    done
    echo "------------------------------------------------------------"
    echo "Status: ${#MISSING[@]} image(s) missing"
    echo ""

    if [ -n "$FOUND_TAG" ]; then
        echo "Will re-tag downloaded images to match: $FOUND_TAG"
    fi

    echo "Attempting to download missing images from a recent nightly run..."

    # Determine the correct nightly workflow based on FALLBACK_TAG.
    # Release branches use version-specific workflows (e.g. nightly-koncur-0.9.yaml).
    NIGHTLY_WORKFLOW="nightly-koncur.yaml"
    if [ -n "$FALLBACK_TAG" ] && [ "$FALLBACK_TAG" != "main" ] && [ "$FALLBACK_TAG" != "latest" ]; then
        CLEAN_TAG="${FALLBACK_TAG#refs/heads/}"
        CLEAN_TAG="${CLEAN_TAG#refs/tags/}"
        VERSION="${CLEAN_TAG#release-}"
        if [ "$VERSION" != "$CLEAN_TAG" ]; then
            CANDIDATE="nightly-koncur-${VERSION}.yaml"
            PROBE_OUTPUT=""
            if PROBE_OUTPUT=$(gh run list -R=konveyor/ci --workflow="$CANDIDATE" --branch=main --limit=1 --json databaseId --jq '.[0].databaseId' 2>&1); then
                if [ -n "$PROBE_OUTPUT" ] && [ "$PROBE_OUTPUT" != "null" ]; then
                    NIGHTLY_WORKFLOW="$CANDIDATE"
                    echo "Using versioned nightly workflow: $NIGHTLY_WORKFLOW"
                else
                    echo "Versioned workflow $CANDIDATE exists but has no runs on main, using default"
                fi
            else
                echo "Could not query workflow $CANDIDATE (gh error: $PROBE_OUTPUT), using default"
            fi
        fi
    fi

    # Find recent nightly runs (any status — image builds often succeed even when
    # unrelated test jobs fail, and --status=success would skip those runs entirely)
    WORKFLOW_RUNS=$(gh run list -R=konveyor/ci --workflow="$NIGHTLY_WORKFLOW" --branch=main --limit=10 --json databaseId --jq '.[].databaseId')

    if [ -z "$WORKFLOW_RUNS" ]; then
        echo "Error: Could not find any nightly workflow runs"
        exit 1
    fi

    # Create temp directory for downloads
    TEMP_DIR=$(mktemp -d)
    echo "Using temp directory: $TEMP_DIR"

    DOWNLOAD_SUCCESS=0

    # Try each recent run until we find one with non-expired artifacts
    for WORKFLOW_RUN in $WORKFLOW_RUNS; do
        echo "Trying workflow run: $WORKFLOW_RUN"
        RUN_DOWNLOAD_OK=1

        for img in "${MISSING[@]}"; do
            ARTIFACT_PREFIX="${img//\//_}"

            # Download only the manifest list (without _amd64 or _arm64 suffix)
            # Pattern matches: quay.io_konveyor_tackle2-hub--main_2026.02.18
            # But NOT: quay.io_konveyor_tackle2-hub--main_2026.02.18_amd64
            PATTERN="${ARTIFACT_PREFIX}--*_20[0-9][0-9].[0-9][0-9].[0-9][0-9]"
            echo "  Downloading manifest list artifact matching: ${PATTERN}"

            if OUTPUT=$(gh run download -R=konveyor/ci "$WORKFLOW_RUN" --pattern "$PATTERN" --dir "$TEMP_DIR" 2>&1); then
                echo "  Successfully downloaded artifact for $img"
            else
                if ! echo "$OUTPUT" | grep -q "no artifact matches"; then
                    echo "  Error downloading artifact for $img:"
                    echo "  $OUTPUT"
                fi
                echo "  Warning: Could not download artifact for $img from run $WORKFLOW_RUN"
                RUN_DOWNLOAD_OK=0
                break
            fi
        done

        if [ $RUN_DOWNLOAD_OK -eq 1 ]; then
            DOWNLOAD_SUCCESS=1
            echo "All missing image artifacts found in run $WORKFLOW_RUN"
            break
        fi

        # Clean up partial downloads before trying next run
        rm -rf "${TEMP_DIR:?}"/*
    done

    # Check if any downloads succeeded
    if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
        echo ""
        echo "Warning: No artifacts were successfully downloaded from any recent nightly run (they may have expired)"
        echo "Attempting to pull missing images from registry as fallback..."
        rm -rf "$TEMP_DIR"

        PULL_TAG="${FALLBACK_TAG:-latest}"
        PULL_TAG="${PULL_TAG#refs/heads/}"
        PULL_TAG="${PULL_TAG#refs/tags/}"
        if [[ "$PULL_TAG" == *"/"* ]]; then
            echo "Error: FALLBACK_TAG '$PULL_TAG' contains '/' and is not a valid image tag"
            exit 1
        fi
        CLUSTER_NAME=${CLUSTER_NAME:-koncur-test}
        PULL_SUCCESS=0
        for img in "${MISSING[@]}"; do
            PULLED=0
            ACTUAL_TAG=""

            echo "Pulling $img:$PULL_TAG..."
            if docker pull "$img:$PULL_TAG" 2>&1; then
                echo "Successfully pulled $img:$PULL_TAG"
                PULLED=1
                ACTUAL_TAG="$PULL_TAG"
            else
                echo "Failed to pull $img:$PULL_TAG"
                if [ "$PULL_TAG" != "latest" ]; then
                    echo "Attempting fallback to $img:latest..."
                    if docker pull "$img:latest" 2>&1; then
                        echo "Successfully pulled $img:latest"
                        PULLED=1
                        ACTUAL_TAG="latest"
                    else
                        echo "Failed to pull $img:latest"
                    fi
                fi
            fi

            if [ $PULLED -eq 1 ]; then
                PULL_SUCCESS=1
                NEW_TAG="$img:$ACTUAL_TAG"
                echo "Loading $NEW_TAG into Kind cluster..."
                kind load docker-image "$NEW_TAG" --name "${CLUSTER_NAME}"

                if [[ "$img" =~ $hub_regex ]]; then
                    echo "HUB=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $addon_regex ]]; then
                    echo "ANALYZER_ADDON=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $addon_discovery ]]; then
                    echo "DISCOVERY_ADDON=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $addon_platform ]]; then
                    echo "PLATFORM_ADDON=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $java_provider_image_regex ]]; then
                    echo "JAVA_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $c_sharp_provider_image_regex ]]; then
                    echo "CSHARP_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $go_provider_image_regex ]]; then
                    echo "GO_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $python_provider_image_regex ]]; then
                    echo "PYTHON_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
                fi
                if [[ "$img" =~ $nodejs_provider_image_regex ]]; then
                    echo "NODEJS_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
                fi
            fi
        done

        if [ $PULL_SUCCESS -eq 0 ]; then
            echo ""
            echo "Error: Could not download artifacts or pull images from registry"
            exit 1
        fi

        echo ""
        echo "Registry pull complete. Re-checking images..."
        exec "$0"
    fi

    # Load downloaded images into Kind cluster and optionally re-tag
    echo ""
    echo "Loading downloaded images into Kind cluster..."
    CLUSTER_NAME=${CLUSTER_NAME:-koncur-test}
    
    for image in $(find "$TEMP_DIR" -type f -name "*.tar"); do
        echo "Loading: ${image}"
        
        # Extract image name from tar file metadata
        # Try multiple methods to handle different tar formats
        LOADED_IMAGE=""
        
        # Method 1: Try with jq (most reliable if available)
        if command -v jq &> /dev/null; then
            LOADED_IMAGE=$(tar -xOf "${image}" manifest.json 2>/dev/null | jq -r '.[0].RepoTags[0] // empty' 2>/dev/null)
        fi
        
        # Method 2: Try with grep/sed if jq failed or not available
        if [ -z "$LOADED_IMAGE" ]; then
            LOADED_IMAGE=$(tar -xOf "${image}" manifest.json 2>/dev/null | grep -o '"RepoTags":\s*\[\s*"[^"]*"' | grep -o '"[^"]*"' | tail -1 | tr -d '"' 2>/dev/null)
        fi
        
        # Method 3: Try index.json for OCI format images
        if [ -z "$LOADED_IMAGE" ]; then
            LOADED_IMAGE=$(tar -xOf "${image}" index.json 2>/dev/null | grep -o '"org.opencontainers.image.ref.name":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        fi
        
        if [ -z "$LOADED_IMAGE" ]; then
            echo "Warning: Could not extract image name from ${image}, skipping..."
            echo "Debug: Listing tar contents:"
            tar -tf "${image}" 2>/dev/null | head -10
            continue
        fi
        
        echo "Image name: $LOADED_IMAGE"
        
        # Load image into Kind cluster
        kind load image-archive "${image}" --name "${CLUSTER_NAME}"
        
        # Use the extracted image name as-is (no re-tagging needed for Kind)
        NEW_TAG="$LOADED_IMAGE"
        echo "Loaded image: $NEW_TAG"
        if [[ "$image" =~ $kantra_image_regex ]]; then
            echo "Kantra Image Found Set Env Var: RUNNER_IMG=$NEW_TAG"
            echo "RUNNER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $java_provider_image_regex ]]; then
            echo "Java Provider Image Found Set Env Var: JAVA_PROVIDER_IMG=$NEW_TAG"
            echo "JAVA_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $c_sharp_provider_image_regex ]]; then
            echo "C Sharp Provider Found Set Env Var: CSHARP_PROVIDER_IMG=$NEW_TAG"
            echo "CSHARP_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $go_provider_image_regex ]]; then
            echo "Go Provider Image Found Set Env Var: GO_PROVIDER_IMG=$NEW_TAG"
            echo "GO_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $python_provider_image_regex ]]; then
            echo "Python Provider Image Found Set Env Var: PYTHON_PROVIDER_IMG=$NEW_TAG"
            echo "PYTHON_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $nodejs_provider_image_regex ]]; then
            echo "Node.js Provider Image Found Set Env Var: NODEJS_PROVIDER_IMG=$NEW_TAG"
            echo "NODEJS_PROVIDER_IMG=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $addon_regex ]]; then
            echo "Addon-Analyzer Image Found Set Env Var: ANALYZER_ADDON=$NEW_TAG"
            echo "ANALYZER_ADDON=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $addon_discovery ]]; then
            echo "Discovery Addon Image Found Set Env Var: DISCOVERY_ADDON=$NEW_TAG"
            echo "DISCOVERY_ADDON=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $addon_platform ]]; then
            echo "Platform Addon Image Found Set Env Var: PLATFORM_ADDON=$NEW_TAG"
            echo "PLATFORM_ADDON=$NEW_TAG" >> $GITHUB_ENV
        fi
        if [[ "$image" =~ $hub_regex ]]; then
            echo "Hub Image Image Found Set Env Var: HUB=$NEW_TAG"
            echo "HUB=$NEW_TAG" >> $GITHUB_ENV
        fi
    done

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo ""
    echo "Download and load complete. Re-checking images..."
    exec "$0"
else
    echo "------------------------------------------------------------"
    echo "Status: All required images are present"
    exit 0
fi
