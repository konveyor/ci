#!/bin/bash

FILE_PATH=$1
kantra_image_regex=".*kantra.*"
java_provider_image_regex=".*java(-external)?-provider.*"
c_sharp_provider_image_regex=".*c-sharp-provider.*"
go_provider_image_regex=".*go(-external)?-provider.*"
python_provider_image_regex=".*python(-external)?-provider.*"
nodejs_provider_image_regex=".*nodejs(-external)?-provider.*"
for image in $(find "$FILE_PATH" -type f -name "*.tar"); do
    echo "Attempting to load image: ${image}"

    if [[ "$image" =~ $kantra_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "Kantra Image Found Set Env Var: RUNNER_IMG=$result"
        echo "RUNNER_IMG=$result" >> $GITHUB_ENV
    fi
    if [[ "$image" =~ $java_provider_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "Java Provider Image Found Set Env Var: JAVA_PROVIDER_IMG=$result"
        echo "JAVA_PROVIDER_IMG=$result" >> $GITHUB_ENV
    fi
    if [[ "$image" =~ $c_sharp_provider_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "C Sharp Provider Found Set Env Var: CSHARP_PROVIDER_IMG=$result"
        echo "CSHARP_PROVIDER_IMG=$result" >> $GITHUB_ENV
    fi
    if [[ "$image" =~ $go_provider_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "Go Provider Image Found Set Env Var: GO_PROVIDER_IMG=$result"
        echo "GO_PROVIDER_IMG=$result" >> $GITHUB_ENV
    fi
    if [[ "$image" =~ $python_provider_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "Python Provider Image Found Set Env Var: PYTHON_PROVIDER_IMG=$result"
        echo "PYTHON_PROVIDER_IMG=$result" >> $GITHUB_ENV
    fi
    if [[ "$image" =~ $nodejs_provider_image_regex ]]; then
        result=$(podman load -i "${image}" | awk '{print $3}')
        echo "Node.js Provider Image Found Set Env Var: NODEJS_PROVIDER_IMG=$result"
        echo "NODEJS_PROVIDER_IMG=$result" >> $GITHUB_ENV
    fi

done
