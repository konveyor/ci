# Konveyor CI

## Releases nightly status

Branch | Konveyor | CLI
--|--|--
**main** | [![Run Konveyor main nightly tests](https://github.com/konveyor/ci/actions/workflows/nightly-main.yaml/badge.svg?branch=main)](https://github.com/konveyor/ci/actions/workflows/nightly-main.yaml) | [![Nightly CLI test for main](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-latest.yaml/badge.svg)](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-latest.yaml)
**release-0.8** | [![Run Konveyor release-0.8 nightly tests](https://github.com/konveyor/ci/actions/workflows/nightly-release-0.8.yaml/badge.svg?branch=main)](https://github.com/konveyor/ci/actions/workflows/nightly-release-0.8.yaml) | [![Nightly CLI test for release-0.8](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-release08.yaml/badge.svg)](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-release08.yaml)
**release-0.7** | [![Run Konveyor release-0.7 nightly tests](https://github.com/konveyor/ci/actions/workflows/nightly-release-0.7.yaml/badge.svg?branch=main)](https://github.com/konveyor/ci/actions/workflows/nightly-release-0.7.yaml) | [![Nightly CLI test for release-0.7](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-release07.yaml/badge.svg)](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-release07.yaml)

## Repositories status

Component | CI (after merge) | Nightly (cron)
--|--|--
**Hub** | [![Hub main](https://github.com/konveyor/tackle2-hub/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/konveyor/tackle2-hub/actions/workflows/main.yml) | [![Hub Test Suite](https://github.com/konveyor/tackle2-hub/actions/workflows/test-nightly.yml/badge.svg?branch=main)](https://github.com/konveyor/tackle2-hub/actions/workflows/test-nightly.yml)
**UI** | [![CI (repo level)](https://github.com/konveyor/tackle2-ui/actions/workflows/ci-repo.yml/badge.svg?branch=main)](https://github.com/konveyor/tackle2-ui/actions/workflows/ci-repo.yml) | [![Nightly CI (repo level @main)](https://github.com/konveyor/tackle2-ui/actions/workflows/nightly-ci-repo.yaml/badge.svg?event=schedule)](https://github.com/konveyor/tackle2-ui/actions/workflows/nightly-ci-repo.yaml)
**E2E API** | [![Test TIER0](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier0.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier0.yml) [![Test TIER1](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier1.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier1.yml) [![Test TIER2](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier2.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/main-tier2.yml) | [![Test nightly TIER0](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier0.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier0.yml) [![Test nightly TIER1](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier1.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier1.yml) [![Test nightly TIER2](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier2.yml/badge.svg)](https://github.com/konveyor/go-konveyor-tests/actions/workflows/nightly-tier2.yml) [![Test nightly TIER3](https://img.shields.io/endpoint?url=https%3A%2F%2Fsajidmansoori12.pythonanywhere.com%2Fretrieve_data%3Fpipeline%3Dtier3-nightly&cacheSeconds=60)](https://jenkins-csb-migrationqe-main.dno.corp.redhat.com/view/MTA/job/mta/job/konveyor-tier3-nightly/)
**E2E UI** | | [![E2E Nightly Tests (main)(without analysis)](https://img.shields.io/github/actions/workflow/status/konveyor/tackle2-ui/e2e-nightly.yaml?label=E2E%20Nightly%20Tests%20(main)(without%20analysis)&event=schedule)](https://github.com/konveyor/tackle2-ui/actions/workflows/nightly-main-e2e.yaml)<br>[![E2E All tiers Nightly(main)(with analysis)](https://img.shields.io/endpoint?url=https%3A%2F%2Fsajidmansoori12.pythonanywhere.com%2Fretrieve_data%3Fpipeline%3Dui-tier-all-nightly&label=E2E%20All%20tiers%20Nightly(main)(with%20analysis))](https://jenkins-csb-migrationqe-main.dno.corp.redhat.com/view/Konveyor/job/mta/job/konveyor-ui-tiers-all-nightly/)<br>[![E2E Nightly Tests (release-0.9)](https://img.shields.io/github/actions/workflow/status/konveyor/tackle2-ui/nightly-release09-dispatcher.yaml?label=E2E%20Nightly%20Tests%20(release-0.9)&event=schedule)](https://github.com/konveyor/tackle2-ui/actions/workflows/nightly-release-0.9-e2e.yaml)  
**Kantra CLI** | | [![Nightly CLI test for main](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-latest.yaml/badge.svg)](https://github.com/konveyor-ecosystem/kantra-cli-tests/actions/workflows/nightly-main-latest.yaml)


## Using the global-ci github workflow

This repository is home to the [global-ci github workflow](https://github.com/konveyor/ci/tree/main/.github/workflows/global-ci.yml).

To use this workflow in your repository, simply add a job that references it as follows:

```yaml
jobs:
  main-nightly:
    uses: konveyor/ci/.github/workflows/global-ci.yml@main
```

If you would like to test it while swapping out a specific component, you can build that component's docker image, upload an artifact
containing the image as a tar file, and reference the artifact when calling the global workflow. Below is an example, swapping out the
`analyzer-lsp` component:


```yaml
jobs:
  build-component:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: build and save image
        run: |
          podman build -t quay.io/konveyor/analyzer-lsp:latest .
          podman save -o /tmp/analyzer-lsp.tar quay.io/konveyor/analyzer-lsp:latest

      - name: Upload image as artifact
        uses: actions/upload-artifact@v4
        with:
          name: analyzer-lsp    # If uploading multiple artifacts in the workflow, make sure there is a unique name for each
          path: /tmp/analyzer-lsp.tar
          # This prevents too many artifacts from accumulating in your repository
          retention-days: 1

  e2e:
    # This references the job that uploads the artifact, to ensure it exists before the job is run
    needs: build-component
    uses: konveyor/ci/.github/workflows/global-ci.yml@main
    with:
      component_name: analyzer-lsp
```

### Referencing specific references of the test repositories

The `global-ci` workflow supports the `api_tests_ref` and `ui_tests_ref` parameters (both default to `main`). This allows you to reference a specific commit of the tests. For example, to configure a release-0.1 nightly, referencing appropriate versions of the test repositories for the release, your job would look something like this:

```yaml
jobs:
  release-0_1-nightly:
    uses: konveyor/ci/.github/workflows/global-ci.yml@main
    with:
      tag: release-0.1
      api_tests_ref: 95c17ea090d50c0c623aa7d43168f6ca8fe26a88
      ui_tests_ref: mta_6.1.1
```

#### Referencing specific pull requests in the test repositories

For repositories that are testing a subbed out component, it's possible that changes need to be made to the test repositories as well as the core component. In these cases, it is possible to change the reference for the test repositories by simply reference them in your Pull Request description.

To replace the `e2e-api-integration-tests` reference, add the following string to your PR description:

```
API tests PR: 233
```

replacing `233` with the appropriate [konveyor/go-konveyor-tests](https://github.com/konveyor/go-konveyor-tests) pull request number for your tests.


To replace the `e2e-ui-integration-tests` reference, add the following string to your PR description:

```
UI tests PR: 233
```

replacing `233` with the appropriate [konveyor/tackle-ui-tests](https://github.com/konveyor/tackle-ui-tests) pull request number for your tests.


## Code of Conduct
Refer to Konveyor's Code of Conduct [here](https://github.com/konveyor/community/blob/main/CODE_OF_CONDUCT.md).
