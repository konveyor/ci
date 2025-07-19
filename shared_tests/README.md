# Konveyor CI shared test cases

Konveyor project affers multiple way of application analysis. There is a shared set of end-to-end basic application analyses that is tested with all relevant components (as an addition to their tests) and this is considered as a source of truth for analysis results.

Component test suites that should use those shared tests are:
- API - E2E tests https://github.com/konveyor/go-konveyor-tests/
- CLI - kantra tests (container&containerless including Windows) https://github.com/konveyor-ecosystem/kantra-cli-tests/
- (optional) UI - E2E tests with cypress https://github.com/konveyor/tackle-ui-tests/

## Format of shared test cases

```
└── shared_tests
    └── analysis_book-server    # `analysis_` + name of the test, usually name of the application
        ├── dependencies.yaml   # analyzer-like dependencies output (produced in full analysis mode)
        ├── output.yaml         # analyzer-like analysis output (contain ruleset with violations/issues reported and optionally Tags on technology usage and discovery)
        ├── tc.yaml             # analysis test definition (application link, sources, targets, etc.)
        └── <input_app>         # Test application binary (or ommited if linked from remote git repo)
```

```
# tc.yaml
---
description: <description of the test, could be just name of the app or more detailed>
input: <input application to be analyzed, absolute link to e.g. github or local path for binary relative to this file>
sources: <array of sources, use [] if empty>
targets: <array of targets, use [] if empty>
options: <optional array of name,value pairs, e.g. for maven settings file and other advanced options>
# Example:
#- name: maven-settings
#  value: ./settings.yaml

```

Check out [book-server test case](analysis_book-server/) as an example.

## Notes

Assertion of output.yaml:
- List of rulesets might be filtered for items that contain `violations` field to get only reported issues (without tags).
- Tags _could_ be tested with filtering `output.yaml` for rulesets names `discovery-rules` and `technology-usage`.
- Incident file paths (`uri` in incident) should be asserted with _end_with_ since its path prefix might been removed already to keep compatibility for container-based and container-less analyses.

More information about shared tests in CI generaly: https://github.com/konveyor/enhancements/pull/228

