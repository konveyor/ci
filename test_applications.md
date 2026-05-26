# Test Applications

This document provides an overview of applications used in Konveyor test suites (API, UI, CLI), organized by their testing tier, more important, lower number and first in the table below. An application can have multiple test cases this table just covers reliable sources for each application.

| Application Name | Repository URL | Branch/Tag | Path | Tier | Type |
|------------------|----------------|------------|------|------|------|
| Tackle Testapp Public | https://github.com/konveyor/tackle-testapp-public | - | - | 0 | Source |
| Customer Tomcat Legacy | https://github.com/konveyor/example-applications.git | - | example-1 | 0 | Source |
| Coolstore | https://github.com/konveyor-ecosystem/coolstore | konveyor-tests | - | 0 | Source |
| Daytrader 7 EE | https://github.com/WASdev/sample.daytrader7.git | - | - | 0 | Source |
| Acmeair Webapp | Binary upload (/binary/acmeair-webapp-1.0-SNAPSHOT.war) | - | - | 0 | Binary |
| Tackle Testapp Public Binary | mvn://io.konveyor.demo:customers-tomcat:0.0.1-SNAPSHOT:war | - | - | 0 | Binary |
| Book Server | https://github.com/ibraginsky/book-server | - | - | 1 | Source |
| Coolstore | https://github.com/konveyor-ecosystem/coolstore | quarkus | - | 1 | Source |
| Administracion Efectivo | Binary upload (/binary/administracion_efectivo.ear) | - | - | 1 | Binary |
| Petclinic | https://github.com/savitharaghunathan/spring-framework-petclinic.git | legacy | - | 2 | Source |
| Seam Booking 5.2 | https://github.com/windup/windup.git | master | test-files/seam-booking-5.2 | 2 | Source |

## Branching

In order to keep applications sources consistent for long-term testing, we should use non-detault branches, proposing `konveyor-ci` or `ci-<TIMESTAMP_OR_VERSION>`.

When default branches are used, guard workflows or other approval/head-up process need to be in place.

## Tier Definitions

- **Tier 0**: Should never fail - These are the most stable applications used for basic testing
- **Tier 1**: Should work - Applications that are expected to work reliably
- **Tier 2**: Great if works - Applications that are more complex or experimental
- **Tier 3**: Internal/private infrastructure - No applications currently defined

## Notes

- **Source applications** are Git repositories that are cloned and analyzed
- **Binary applications** are either uploaded binary files or downloaded from Maven repositories
- Some test cases may be skipped due to technical issues (noted with Skip flags in test definitions)
- Note that Coolstore appears in both Tier 0 and Tier 1 but uses different branches (konveyor-tests vs quarkus)
