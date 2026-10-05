# Working notes and agent handoff

Updated **2026-10-05**. This is the current state, replacing the earlier append-only session log. Historical details remain in the linked reports. Read this file before diagnostics or builds; then read [PROJECT_GUIDE.md](PROJECT_GUIDE.md) for the implementation map and [the documentation index](README.md) for the rest.

## User authorization and non-negotiable constraints

| Area | Instruction |
|---|---|
| Running Windows | Read-only. Never edit its system files, live registry/settings, Defender configuration, scheduled tasks, installed toolchains, or CPU priority, even temporarily. |
| Project / offline media | Project code/docs, source/destination ISO files, extracted media and offline Windows image files may be worked on. Preserve the original input unless an explicit request requires replacing it. |
| Temporary attachments | Normal ISO/offline-image mounts and owned offline hive attachments are explicitly allowed for servicing. Writes target the offline image, never live host keys. Release attachments afterward and verify cleanup. |
| Work location | The user explicitly authorized short offline-work/output paths under `C:\.temp`. It was subsequently cleaned and is currently absent. A future build may use a new isolated folder there; obey the tool's active filesystem permissions as well. |
| Process lifecycle | Before replacing an attempt, stop its **own** process tree and confirm exit, writer/mount/hive state. Do not kill unrelated Windows servicing. Never overlap image/hive writers, even with different work folders: the `HKLM\z*` aliases are shared. |
| Recovery | Rebooting is not the normal solution. Preserve native errors, diagnose the failing step, and retain image files if dismount fails or mount state is unknown. |
| Performance | Optimize the **first build** from the original ISO. No previous patched image, saved checkpoint, application metadata cache or multi-run optimization. Do not promise cold OS filesystem caches; they were not reset in benchmarks. |
| Output behavior | Preserve intended patch/app choices and maximum final compression by default. The user accepts roughly 5–6 GB when correct; do not remove extra features to force a historical 2–3 GB size. |
| Evidence | A unit test, container integrity check, saved-image inspection and successful VM installation are different results. Never claim every original-log error or installation compatibility is proved by unit tests. |
| Source sharing | Commit/push was explicitly authorized. Use the verified existing `main` / `upstream` repository; do not send messages or modify upstream PRs merely because they are references. |

The host boundary was clarified explicitly: editing mounted ISO/image files and their work is allowed; editing the Windows machine currently running is not. Earlier task-created scheduled-task diagnostics occurred **before** that restriction and were cleaned. Do not repeat them. The optional `-DefenderExclusion` feature exists in the product but is **not authorized for this session**. The user controls priority themselves.

## Current application and repository state

- Application implementation audited at **`2ae045de3b8a0c4d8dd726534fea906c3cb78b14`**, pushed to [NairoDorian/tiny11builder_2026](https://github.com/NairoDorian/tiny11builder_2026). The remote is named `upstream` here; this is the user's repository, **not** `ntdevlabs`.
- Existing product/module version labels remain `2026.09` / `2026.9.0`. October improvements are unreleased commits, not a newly invented release tag. Subsequent documentation-only commits do not create a new full-build validation result.
- Standard and Core builders share `lib/tiny11utils.psm1`; WinForms GUI is `lib/tiny11gui.psm1`; read-only ISO metadata is `lib/tiny11media.psm1` plus bundled DiscUtils. Standard is intended to remain serviceable; Core deliberately removes servicing functionality.
- Both builders support Windows PowerShell 5.1 and PowerShell 7. PS7 imports the DISM compatibility proxy. The latest local tests used 5.1.26100.9549 and 7.6.5; those engine versions do not establish the host OS build. The user reports Windows 11 26H2; verified source image version is **10.0.26300.9457**, Pro x64/en-US, original index 6.
- GUI has seven tabs, asynchronous first-use edition reading, overall/current-step progress, elapsed time and estimated remaining time. Overall progress/ETA is approximate; unknown steps animate. `-WorkDirectory` is currently **CLI-only**. Compression engine/effort/thread fields exist in saved GUI state and are forwarded, but have no dedicated visible controls. See PROJECT_GUIDE.md for these boundaries.
- Maximum means solid LZMS `install.esd`, effort 100 and 64 MiB chunks with wimlib; automatic threads respect memory. `recovery` is its legacy API/CLI alias. Legacy `max` means **balanced LZX**, not maximum.
- First-use ISO edition selection reads actual WIM XML inside the ISO, without mount/download/persistent cache. Filename/build lists are hints, never fabricated edition/index data.
- Initial selected-edition export reuses compatible compressed resources from the **original** WIM. Solid ESD inputs become a mountable ordinary WIM. Final maximum export happens after servicing. Small Setup hive-file updates avoid a boot-image mount when supported and no drivers are requested; driver/fallback servicing uses separate `scratchdir_boot`.

## Implemented fixes and deliberate decisions

| Work | Current implementation | Evidence / details |
|---|---|---|
| Native stderr / mixed return values | Concurrent native output draining, ordinary progress streaming, numeric return values, inspected exit codes. | [BUILD_BUG_REPORT.md](BUILD_BUG_REPORT.md) |
| Registry/task stall | Strip TaskCache ID terminator, reject NUL arguments, close stdin, bound registry operations. | Same report; core tests |
| New protected Windows Security app | Retain `Microsoft.SecHealthUI` on build 26100+; offline Defender policies remain separate. | [APPS.md](APPS.md) |
| Denied Widgets DWORDs | Defer targeted denied DWORDs until owned hive unload; file-only Offreg write/readback and replacement preserving file security. | Saved final-image readbacks; original failure cause is not proven ACL-related |
| Hive-load launch-context failure | Early disposable offline-hive preflight plus real mounted SOFTWARE load/unload guard; preserve native error. CIM launch succeeded in controlled tests. | Underlying Windows cause remains unknown; normal GUI/CLI is not automatically rerouted through CIM |
| Failed cleanup / mount conflict | Isolate install/driver-Setup mounts, reject redirected/still-mounted scratch deletion, bounded retries, retain files when dismount/state is unsafe. | PR #623 adaptation; fixture tests |
| Silent Setup metadata loss | Restore **only missing** source-derived fields via supported wimlib XML properties, preserve languages/integrity, reject conflicts and re-read. | PR #628/#583 adaptation; real WIM/ESD fixtures |
| AI/privacy policies | Three verified Edge additions in optional RemoveAI; cloud-search block in optional Search. Advertising-ID policy was already present. | PR #622 and u0reo review; generated TWEAKS.md |
| Late ISO-writer download failure | Prepare Oscdimg in both real builders before source mounting; atomic pinned portable download, verified retention; final step receives prepared path. | PR #604 adaptation, fresh Microsoft download/native help |
| Wrong control set / source overlap | Read offline SYSTEM `Select\Default`; route template writes/deletes/service checks; reject overlapping source/work trees before copying/deletion. | pi0n00r-inspired safeguards; mocked selection/failure tests |
| Reference imports | Retain existing apps/edition choices. No fleet NVMe overrides, raw WIM-header rewrite, extra framework removals, multi-edition default, Linux recapture/resume, RDP/tunnel host changes. | [REFERENCE_REVIEW.md](REFERENCE_REVIEW.md) |

## What has actually been verified

| Revision / scope | Result | Limit |
|---|---|---|
| Earlier committed checkpoint plus file-only repairs | 6,248,947,712-byte maximum ISO; full image integrity and three repaired DWORD readbacks; logical content comparisons. | Historical checkpoint workflow; deleted output; not a fresh current-script build |
| `7aa45d5aa88e5c2bab9a9df692fe51404357c8ce` / two sequential fresh Standard builds | None/skipped cleanup: **557.8 s**, **14,746,617,856 bytes**. Maximum/normal cleanup: **1265.9 s**, **6,229,929,984 bytes**. Both exit 0, no build warnings, saved-image checks passed. | Cleanup differs; one sample each; no old-repository full-run baseline; no VM install |
| `cebf4cd` / PR #623/#628/#622 changes | Dual-shell regressions, real export fixtures, metadata preservation/readback and cleanup cases passed. | Postdates measured full ISOs |
| `2ae045d` / PR #604 and six new reference branches | **1,920** core checks PS7, **1,918** PS5.1; **129** real export and **23** media/progress checks per shell; parser, generated freshness and PSScriptAnalyzer passed. [CI all green](https://github.com/NairoDorian/tiny11builder_2026/actions/runs/37245856681). | No fresh full ISO or VM installation of this revision; control-set routing is mock-tested |

Saved-image checks independently verified one container/edition, required source metadata, full image data/integrity, absence of all 29 planned removed app families, presence of Terminal/Calculator/Notepad/Photos, targeted Edge/OneDrive absence and the three DWORDs extracted from finished media. File presence of BIOS/UEFI boot material is not a boot test. See [PERFORMANCE.md](PERFORMANCE.md), [BUILD_BUG_REPORT.md](BUILD_BUG_REPORT.md) and [VERIFICATION.md](VERIFICATION.md).

The 23.4-second figure measured **initial source-edition export**, never a full build. The final maximum export consumed about 838 seconds in the fresh maximum run. No measured general 2x full-build improvement is claimed.

## Artifact availability and workspace hygiene

- Original input exists at `C:\Users\Z\Downloads\PROJECTS\ISOs\Windows11_Client_x64_en-us_26300_9457.iso` (9,047,330,816 bytes).
- The historically retained maximum output path was `C:\Users\Z\Downloads\PROJECTS\ISOs\tiny11-26300-maximum-20261004-190253.iso`, SHA-256 `2b1cced1fe91288292b054416f9ce230168ba71eee1849290606b973c1f56808`. It and its sidecars are **absent at that path**, reconfirmed 2026-10-05. Why it disappeared is unknown. Do not offer it as an available download or search private folders indiscriminately.
- `C:\.temp`, checkpoints, other generated media and historical raw diagnostics were deleted on request. The old `logs/manual-verification` and `logs/upstream-audit` paths are historical identifiers, not retained evidence.
- Compact evidence remains in `docs/verification/2026-10-04` and `2026-10-05`. New working logs may be regenerated by tests/app use. Save relevant compact summaries before cleaning owned fixtures.
- The user subsequently requested more reference source. Keep **21** clean checkouts under ignored `repos/`: original plus 20 community projects. Their code is intentionally local; inventory and revision audits are tracked. The six exact branches and all comparisons are in REFERENCE_REVIEW.md. All 15 previously downloaded heads were unchanged when fetched on 2026-10-05.
- Workspace was about **75.75 MB**, including roughly **52.7 MB** of reference source/Git histories after the last application commit. These are dated observations, not size guarantees. Do not remove user-requested references to meet an older cleanup request.

## Next agent: outstanding work and safe starting point

1. Read [PROJECT_GUIDE.md](PROJECT_GUIDE.md), [CONTRIBUTING.md](../CONTRIBUTING.md) and [VERIFICATION.md](VERIFICATION.md). Consult the bug/performance/reference reports for the change being considered. Read an available `RTK.md`; it remains absent from this checkout.
2. Start from current Git status and exact code/preset/options. Use fresh isolated work and original input for any later authorized build. Verify earlier writers/attachments have ended before launching; do not automatically start another benchmark just because historical reports mention one.
3. A fresh full **current-revision** Standard build and a disposable VM boot/install would close the principal validation gap. Installation media can create disk-writing behavior, especially ZeroTouch; use an explicitly disposable VM/test disk and record edition, firmware mode and results. This documentation update did not perform either.
4. The unexplained native hive-load launch-context issue remains unresolved. The preflight detects it early; successful CIM tests do not prove normal GUI launching is repaired. Keep this distinction if revisiting launch integration.
5. ARM64, Core, multilingual and driver-enabled end-to-end builds have not been demonstrated by the x64 Pro benchmarks. Existing fixtures cover some mechanics, not complete platform installation support.
6. GUI visible controls do not yet expose isolated WorkDirectory or dedicated compressor engine/effort/thread selectors. Do not describe this as implemented. Cleanup is best-effort, and some legacy recovery routines use shared aliases/global mountpoint cleanup; isolation is not a cross-process lock. Core's existing offline WinSxS `cmd/rmdir` fallback is separate from the guarded scratch-folder cleanup and deserves review before claiming all deletions use that guard.
7. Preserve measured scope and historical attribution when updating docs. Keep new state at the top, move history to the relevant report, and update generated catalogs through `scripts/update-generated.ps1`, never manual edits that CI will overwrite.
