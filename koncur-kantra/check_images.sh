#!/bin/bash

set -e

REQUIRED_IMAGES=("quay.io/konveyor/kantra" "quay.io/konveyor/c-sharp-provider" "quay.io/konveyor/java-external-provider" "quay.io/konveyor/go-external-provider" "quay.io/konveyor/python-external-provider" "quay.io/konveyor/nodejs-external-provider")
kantra_image_regex=".*kantra.*"
java_provider_image_regex=".*java(-external)?-provider.*"
c_sharp_provider_image_regex=".*c-sharp-provider.*"
go_provider_image_regex=".*go(-external)?-provider.*"
python_provider_image_regex=".*python(-external)?-provider.*"
nodejs_provider_image_regex=".*nodejs(-external)?-provider.*"

echo "Checking for required podman images..."
echo "------------------------------------------------------------"

# Get list of all podman images
IMAGES=$(podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null)

if [ -z "$IMAGES" ]; then
    echo "No images found in podman."
    echo ""
    echo "Missing images:"
    for img in "${REQUIRED_IMAGES[@]}"; do
        echo "  - $img"
    done
    exit 1
fi

MISSING=()
FOUND=()
FOUND_TAG=""

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

    # Find recent nightly runs (any status — image builds often succeed even when
    # unrelated test jobs fail, and --status=success would skip those runs entirely)
    WORKFLOW_RUNS=$(gh run list -R=konveyor/ci --workflow=nightly-koncur.yaml --branch=main --limit=10 --json databaseId --jq '.[].databaseId')

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
            # Pattern matches: quay.io_konveyor_kantra--main_2026.02.18
            # But NOT: quay.io_konveyor_kantra--main_2026.02.18_amd64
            PATTERN="${ARTIFACT_PREFIX}--*_20[0-9][0-9].[0-9][0-9].[0-9][0-9]"
            echo "  Downloading manifest list artifact matching: ${PATTERN}"

            OUTPUT=$(gh run download -R=konveyor/ci "$WORKFLOW_RUN" --pattern "$PATTERN" --dir "$TEMP_DIR" 2>&1)
            EXIT_CODE=$?

            if [ $EXIT_CODE -ne 0 ]; then
                if ! echo "$OUTPUT" | grep -q "no artifact matches"; then
                    echo "  Error downloading artifact for $img:"
                    echo "  $OUTPUT"
                fi
                echo "  Warning: Could not download artifact for $img from run $WORKFLOW_RUN"
                RUN_DOWNLOAD_OK=0
                break
            else
                echo "  Successfully downloaded artifact for $img"
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
        # Strip common git ref prefixes so full refs like refs/heads/main become valid tags
        PULL_TAG="${PULL_TAG#refs/heads/}"
        PULL_TAG="${PULL_TAG#refs/tags/}"
        if [[ "$PULL_TAG" == *"/"* ]]; then
            echo "Error: FALLBACK_TAG '$PULL_TAG' contains '/' and is not a valid image tag"
            exit 1
        fi
        PULL_SUCCESS=0
        for img in "${MISSING[@]}"; do
            PULLED=0
            ACTUAL_TAG=""

            # Try to pull with PULL_TAG first
            echo "Pulling $img:$PULL_TAG..."
            if podman pull "$img:$PULL_TAG" 2>&1; then
                echo "Successfully pulled $img:$PULL_TAG"
                PULLED=1
                ACTUAL_TAG="$PULL_TAG"
            else
                echo "Failed to pull $img:$PULL_TAG"

                # If PULL_TAG is not "latest", try "latest" as fallback
                if [ "$PULL_TAG" != "latest" ]; then
                    echo "Attempting fallback to $img:latest..."
                    if podman pull "$img:latest" 2>&1; then
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
                if [ -n "$FOUND_TAG" ] && [ "$ACTUAL_TAG" != "$FOUND_TAG" ]; then
                    NEW_TAG="$img:$FOUND_TAG"
                    echo "Re-tagging to: $NEW_TAG"
                    podman tag "$img:$ACTUAL_TAG" "$NEW_TAG"
                fi

                if [[ "$img" =~ $kantra_image_regex ]]; then
                    echo "RUNNER_IMG=$NEW_TAG" >> $GITHUB_ENV
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

    # Load downloaded images into podman and optionally re-tag
    echo ""
    echo "Loading downloaded images into podman..."
    for image in $(find "$TEMP_DIR" -type f -name "*.tar"); do
        echo "Loading: ${image}"
        LOADED_IMAGE=$(podman load -i "${image}" | awk '{print $3}')
        echo "Loaded image: $LOADED_IMAGE"

        # Re-tag if we have a tag from found images
        if [ -n "$FOUND_TAG" ] && [ -n "$LOADED_IMAGE" ]; then
            # Extract the repository name (without the tag)
            IMAGE_REPO=$(echo "$LOADED_IMAGE" | cut -d':' -f1)
            NEW_TAG="${IMAGE_REPO}:${FOUND_TAG}"
            echo "Re-tagging to: $NEW_TAG"
            podman tag "$LOADED_IMAGE" "$NEW_TAG"
        fi
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


    done

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo ""
    echo "Download and load complete. Re-checking images..."
    exec "$0"
else
    echo "------------------------------------------------------------"
    echo "Status: All required images are present"

    # Set environment variables for all found images to ensure they're available in subsequent steps
    for img_info in "${FOUND[@]}"; do
        # Extract image name with tag from the "image: found_image" format
        IMAGE=$(echo "$img_info" | awk '{print $NF}')

        if [[ "$IMAGE" =~ $kantra_image_regex ]]; then
            echo "Setting RUNNER_IMG=$IMAGE"
            echo "RUNNER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
        if [[ "$IMAGE" =~ $java_provider_image_regex ]]; then
            echo "Setting JAVA_PROVIDER_IMG=$IMAGE"
            echo "JAVA_PROVIDER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
        if [[ "$IMAGE" =~ $c_sharp_provider_image_regex ]]; then
            echo "Setting CSHARP_PROVIDER_IMG=$IMAGE"
            echo "CSHARP_PROVIDER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
        if [[ "$IMAGE" =~ $go_provider_image_regex ]]; then
            echo "Setting GO_PROVIDER_IMG=$IMAGE"
            echo "GO_PROVIDER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
        if [[ "$IMAGE" =~ $python_provider_image_regex ]]; then
            echo "Setting PYTHON_PROVIDER_IMG=$IMAGE"
            echo "PYTHON_PROVIDER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
        if [[ "$IMAGE" =~ $nodejs_provider_image_regex ]]; then
            echo "Setting NODEJS_PROVIDER_IMG=$IMAGE"
            echo "NODEJS_PROVIDER_IMG=$IMAGE" >> $GITHUB_ENV
        fi
    done

    exit 0
fi
