# Documentation map

Updated **2026-10-05**, reflecting the application implementation at `2ae045d` and the saved verification records. Begin here when you need to understand the repository from Markdown alone.

## Read in this order

| Read | What it establishes |
|---|---|
| [WORKING_NOTES.md](WORKING_NOTES.md) | User constraints, host read-only boundary, current revision, artifact availability, verified results and open work. Required before diagnostics/builds. |
| [PROJECT_GUIDE.md](PROJECT_GUIDE.md) | Product modes, architecture, source/data ownership, complete build pipeline, GUI/CLI contract, native/registry safety and dependencies. |
| [../README.md](../README.md) | User-facing setup, UI tabs, presets and command options. |
| [VERIFICATION.md](VERIFICATION.md) | Evidence levels, test/CI matrix, full-build provenance, known gaps and a safe verification procedure. |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Where to change code/data, dual-PowerShell conventions, generated documents and checks. |

## Detailed references

| Document | Use it for | Status |
|---|---|---|
| [PERFORMANCE.md](PERFORMANCE.md) | First-use optimizations, compression semantics, actual timings/sizes, dependency versions, progress/ETA limits | Current mechanisms with explicitly historical benchmark results |
| [BUILD_BUG_REPORT.md](BUILD_BUG_REPORT.md) | Original log errors, controlled launch/hive tests, oversized images, silent Setup failures and unresolved causes | Living investigation; historical raw logs were deleted |
| [UPSTREAM_PR_REVIEW.md](UPSTREAM_PR_REVIEW.md) | Decisions and tests for #623/#628/#622/#604 | Dated snapshots; PR state is not a live feed |
| [REFERENCE_REVIEW.md](REFERENCE_REVIEW.md) | All 21 reference checkouts, six requested branches, source differences and selective adoption | Revision-pinned audit, with update instructions |
| [TWEAKS.md](TWEAKS.md) | Every catalog registry value, group condition, service setting and scheduled task | Generated from code/data; update the generator/source |
| [APPS.md](APPS.md) | App prefixes, optional utilities, protected apps, preset and capability behavior | Generated from code/data; absence on one ISO is normal |
| [../CHANGELOG.md](../CHANGELOG.md) | Chronological evolution and upstream/fork attribution | New work above; earlier entries are historical, not current guarantees |
| [../payload/README.md](../payload/README.md) | What runs on the newly installed system at SetupComplete/first sign-in | These hooks are staged during a build, not executed on the build host |
| [../payload/packages/README.md](../payload/packages/README.md) | Payload selection/ordering and file placement | Top-level files only |
| [../Browsers/README.md](../Browsers/README.md) | Optional first-sign-in Firefox/Chrome installers | Network/install time happens after Windows installation |
| [../lib/vendor/DiscUtils/README.md](../lib/vendor/DiscUtils/README.md) | Bundled reader provenance, hashes and license | Pinned reader, no first-use dependency download |

## Which record wins

Current user instructions take precedence over an older note. WORKING_NOTES.md records the session boundary; PROJECT_GUIDE.md describes the implementation; VERIFICATION.md states what is actually proved. Dated measurements/audits retain their original scope. Generated APPS/TWEAKS describe current catalog data, not a guarantee that every setting is effective on every Windows edition/version. If documents disagree, verify the relevant source/evidence and correct the documents rather than silently treating a historical statement as current.

Full human-readable context is here in Markdown. Supporting JSON under `verification/` preserves exact hashes, arguments, app/file checks and timings for reproducibility; you do not need to open it to learn the project, but you do need it to substantiate a precise historical claim. Reference code under ignored `repos/` is supplementary study material, never part of the executable application pipeline.

## Keeping the handoff useful

After a meaningful code change, update current state, affected user documentation, verification scope and the changelog. Record the code revision and input configuration for fresh builds. Distinguish a complete run from a fixture, a patched checkpoint from a first build, and retained files from deleted historical paths. Save compact evidence, then clean only owned work after writers/attachments have ended. Do not append a new “latest request” beneath stale pending instructions.
