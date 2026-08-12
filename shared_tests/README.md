# Konveyor CI shared test cases

Konveyor project affers multiple way of application analysis. There is a shared set of end-to-end basic application analyses that is tested with all relevant components (as an addition to their tests) and this is considered as a source of truth for analysis results.

Component test suites that should use those shared tests are:
- API - E2E tests https://github.com/konveyor/go-konveyor-tests/
- CLI - kantra tests (container&containerless including Windows) https://github.com/konveyor-ecosystem/kantra-cli-tests/
- (optional) UI - E2E tests with cypress https://github.com/konveyor/tackle-ui-tests/

## Format of shared test cases

```
└── shared_tests
    ├── book-server_deps        # name of the test case
    |    ├── dependencies.yaml   # analyzer-like dependencies output (produced in full analysis mode)
    |    └── output.yaml         # analyzer-like analysis output (contain ruleset with violations/issues reported and optionally Tags on technology usage and discovery)
    └── test_cases.yaml          # analysis test cases definition (top level keys should match to directory names with expected results)
```

Check out [test cases.yml](test_cases.yml)

## Notes

Assertion of output.yaml:
- List of rulesets might be filtered for items that contain `violations` field to get only reported issues (without tags).
- Tags _could_ be tested with filtering `output.yaml` for rulesets names `discovery-rules` and `technology-usage`.
- Incident file paths (`uri` in incident) should be asserted with _end_with_ since its path prefix might been removed already to keep compatibility for container-based and container-less analyses.

More information about shared tests in CI generaly: https://github.com/konveyor/enhancements/pull/228

