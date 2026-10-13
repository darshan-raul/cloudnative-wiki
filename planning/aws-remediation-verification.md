# AWS remediation verification

> This report records the earlier factual/structural remediation snapshot. The subsequent Git review found that those edits removed useful learning depth. [Depth restoration and fresh validation](aws-depth-restoration.md) are now complete; the older counts below describe the earlier snapshot.

Snapshot: 2026-10-12. Corpus: **181 notes** (155 original notes updated, 26 new lessons/indexes); original paths preserved.

## Local checks

| Check                                   | Result                                                                                                                                                                                                                                 |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AWS content validator                   | 0 errors, 0 warnings                                                                                                                                                                                                                   |
| Entire vault validator                  | 0 errors; one pre-existing Go concurrency index stub outside AWS                                                                                                                                                                       |
| npm run test                            | 74 tests passed, including four new AWS note regressions                                                                                                                                                                               |
| npm run check                           | TypeScript, content and whole-repository Prettier checks passed                                                                                                                                                                        |
| Fenced JSON/Python/shell syntax         | 71 checked, 0 parse failures; not executed against AWS                                                                                                                                                                                 |
| Tables/currency rendering AST           | 47 tables, no inconsistent rows; no unintended math nodes in AWS notes                                                                                                                                                                 |
| Selected CLI request models             | EC2 launch-template data, ECS task definition, Batch job definition and DLM policy fields match local AWS CLI 2.34.48 skeletons; dynamic log-option maps allowed                                                                       |
| Pure Lambda fixtures                    | Direct greeting, HTTP-shaped default greeting and invalid numeric input checked locally in independent review                                                                                                                          |
| Synthetic CUR SQL                       | In-memory query produced EC2 total 8 and S3 total 3; no billing query or Athena call                                                                                                                                                   |
| AWS reference availability              | 620 unique retained URLs returned HTTP 200; 0 observed 404/403/unverified URLs                                                                                                                                                         |
| Reference coverage                      | 0 notes without external URLs; 0 notes without owning AWS documentation URLs                                                                                                                                                           |
| git diff --check                        | Passed                                                                                                                                                                                                                                 |
| Final production build and emitted HTML | Production build passed: 998 vault inputs, 3,564 emitted files. All 181 AWS articles present; 957 internal article-link destinations resolve; no invalid math markup; Cognito safety extension and Bedrock production guidance present |

HTTP 200 establishes availability, not claim support or validity of URL fragments. Sources and authoring decisions are in the audit/source-decision reports; exact pricing, quotas and account/Region eligibility must be rechecked before deployment.

The build emitted non-blocking LaTeX compatibility warnings; AWS currency/math regressions pass. The remaining vault stub warning is outside AWS and unchanged.

## Verification boundaries

No live AWS resource calls, credential-document reads, deployments, migrations, cross-account trust changes or deletes were executed. CLI skeleton generation is local model inspection. Many corrected lessons use complete, bounded console/versioned workflows instead of unsupported copy-and-run infrastructure fragments. Their prerequisites, expected evidence, failure handling and cleanup are documented, but are not live-deployment certified.

Original long sections containing fabricated APIs, unsupported universal numbers, duplicate advice or retired deployment recipes were replaced/removed. No note path was deleted. Original tracked versions remain available in Git; no commits or pushes were made. Obsidian workspace changes were not modified.

## Reproduce

```bash
node scripts/check-content.mjs AWS --verbose
node planning/aws-audit-snippets.mjs
npm run test
npm run check
npm run quartz build
node planning/aws-audit-reference-links.mjs
node planning/aws-render-smoke.mjs
node planning/aws-audit-inventory.mjs --json
```

Tests are offline except the explicit reference checker and build-time remote resources. No command above provisions AWS resources.
