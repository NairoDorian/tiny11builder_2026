# Contributing and maintaining the handoff

Read [docs/WORKING_NOTES.md](docs/WORKING_NOTES.md), [the project guide](docs/PROJECT_GUIDE.md) and [verification guide](docs/VERIFICATION.md) first. The [documentation map](docs/README.md) is the reading route for future agents. This is a fork of ntdevlabs with **21 studied checkouts including the original**; source provenance and selective imports are recorded in [REFERENCE_REVIEW.md](docs/REFERENCE_REVIEW.md).

## Ground rules

1. Respect the session's live-Windows read-only boundary. Modify project/offline-image files and owned offline hive attachments only. The optional product `-DefenderExclusion` switch is not authorized here. No scheduled-task/priority/security/toolchain changes on this host.
2. Never overlap builders or image/hive writers, even in separate work folders. Shared z* aliases/global recovery are not protected by a cross-process lock. Before a retry, verify the previous owned process tree has exited and attachments are released. Preserve files when mount state is unknown.
3. Registry writes/deletes go through the offline helpers, which validate aliases and loaded ownership. Catalog `ControlSet001` is a **template** resolved through the image SYSTEM `Select\Default`. Do not use `CurrentControlSet`, hardcode another live host path, or bypass guards with raw registry cmdlets. Deferred protected DWORD entries must receive the resolved subkey.
4. Preserve first-use behavior: compressed-resource reuse means the original ISO's resources, never earlier patched outputs/cache/checkpoints. Maximum final compression remains default. `recovery` aliases maximum; legacy `max` aliases balanced. Any intentional patch-feature change needs explicit rationale and evidence.
5. Distinguish critical failures from counted warnings. Validate options early; mount/commit/export/metadata/mastering failures must stop. A counted app/tweak warning is not proof of a successful patch. Preserve native messages and avoid attributing an unresolved failure to an unproved cause.
6. Keep GUI-to-builder translation accurate. Update visible controls/state/validation/help together when adding an exposed option. Current WorkDirectory is CLI-only; compressor advanced state values have no dedicated selectors. Do not document new controls before they exist.

## PowerShell and native conventions

- Support **Windows PowerShell 5.1 and PowerShell 7**. ASCII-only scripts may be BOM-less; non-ASCII PowerShell source needs UTF-8 **BOM** so 5.1 does not interpret it as ANSI. Preserve the repository's `.gitattributes` line-ending rules and existing encoding when editing.
- DISM under PS7 is imported by `Initialize-DismModule` through Windows PowerShell compatibility. Its objects can be deserialized: compare enum values as strings/read properties, do not call methods or assume original runtime types.
- Use `Get-PowerShellExecutable` for build children to keep the caller's edition. Scripts staged into installed Windows use built-in 5.1; that is a separate environment.
- Use `Invoke-Native` for builder native operations. Do not redirect native stderr directly with `2>$null` / `2>&1` under Stop semantics in 5.1: ordinary progress can become a terminating PowerShell error. Keep numeric status/results separate from log output, inspect exit codes, reject NUL arguments and retain bounded registry timeouts/closed stdin.
- Validate absolute owned offline targets before recursive cleanup. Scratch helpers reject redirected/mounted directories. Core's existing offline WinSxS cmd fallback is a separate legacy path, not evidence all recursion shares those helpers. Do not build deletion commands by enumerating paths in one shell and interpolating them into another.
- New dependency versions stay project-local with official provenance and checksum updates. Do not install/update host DISM/ADK/PowerShell/.NET/modules or poll release feeds on every app launch.

## Change locations and contracts

| Change | Update |
|---|---|
| Registry policy/group | `data/tweaks.psd1`, documented policy path/edition limits, group When/opt-out, meaningful scope checks; regenerate TWEAKS |
| Preset flag | `Get-PresetFlagNames`, preset section/resolution/JSON helpers, all four `presets/*.json`, GUI flag description/state/control and generated matrix |
| New builder parameter | Relevant builder param/help blocks, validation/orchestration, GUI translation/control **if exposed**, README options and project guide |
| Default app prefix | `removePackage.txt`; preserve optional-utility/protected-package rules and test actual inventory matching |
| Optional app defaults | `Get-OptionalUtilities` and resolver; update GUI/APPS and test Keep/Remove precedence |
| Source selection / optical metadata | `lib/tiny11media.psm1`; keep first-use no-mount/no-download path, bounded XML and actual edition authority |
| Native/registry/cleanup shared behavior | `lib/tiny11utils.psm1`, callers in both makers; exercise real or meaningful failure fixtures for the changed contract |
| Image exports / metadata | Export helpers/guard; preserve data, alternate streams, security/times/hard links, integrity and actual source fields; avoid raw XML/header edits |
| Answer files | `New-UnattendXml`; update the allow-list only for verified Windows Setup settings, plus generated x64/ARM64 references |
| GUI / progress | `lib/tiny11gui.psm1`, state/request/tail/timing contracts; explicit stage records remain compatible; render changed visible tabs |
| Payload / browser hooks | Generated SetupComplete/FirstLogon helpers, files under payload/Browsers, option validation/GUI and their READMEs; execute on target, not host |
| Studied references | Catalog + source-only sync + reviewed revision/diff/adoption record; preserve local modified/detached/divergent checkouts |
| Current state / evidence | WORKING_NOTES, affected detailed guide, VERIFICATION, dated compact evidence and CHANGELOG |

## Generated artifacts

Run `scripts/update-generated.ps1` after changing the catalog, app/preset definitions, answer generator, exported functions or emitted Markdown. It owns **docs/TWEAKS.md**, **docs/APPS.md**, **autounattend.xml**, **autounattend-arm64.xml**, **lib/tiny11utils.psd1** and **lib/tiny11gui.psd1**. Edit the source/generator, not the output alone. `-Check` reports stale output without rewriting it. A Markdown-only generator change should not alter answer XML/module manifests.

## Appropriate validation

```powershell
.\scripts\update-generated.ps1
.\scripts\parse-check.ps1
.\scripts\test-core-helpers.ps1
.\scripts\test-media-progress.ps1
.\scripts\test-export-pipeline.ps1
.\scripts\update-generated.ps1 -Check
.\scripts\linter.ps1
```

The [verification guide](docs/VERIFICATION.md#running-development-checks) gives explicit commands for both shells and explains what each test proves. Core checks include catalog/presets, answer-file allow-lists, mock build stages, native/registry failure guards and the actual GUI/launcher driven by a fake builder. Media/export tests are fresh real small file fixtures without a Windows mount or complete install. CI runs both shells, plus generated freshness/lint in 5.1 and XML/JSON validation; it never services a full source Windows ISO.

Run the checks relevant to the change; broaden when new failures/change scope justify it. For documentation-only work, check claims/links, generated freshness and whitespace rather than repeatedly launching a 20-minute build. For changed servicing/installation behavior, report actual source/options/revision and saved-image verification; if no full/VM test was done, state that limitation. The historical full builds at `7aa45d5` do not validate all later changes. Do not require or imply a destructive live-host test to make a documentation change reviewable.

GUI-only hooks are `-PreviewPath`/`-PreviewTab` (window bitmap, not screen grab), `-AutoRun Build` with `-BuilderOverride scripts\fixtures\fake-builder.ps1` / `-Quiet`, and `-InitialState`. Update screenshots only when the visible window changes; the documentation refresh does not change controls.

## Fork study, history and publishing

Reference source lives under ignored `repos/`; the tracked catalog fixes URLs/branches. Use `scripts/sync-reference-repos.ps1` to clone/fetch/fast-forward source, preserve user edits/branch state and save a dated audit. Do not execute reference installers/workflows. Compare to the refreshed original, credit useful ideas and document rejected behavior that would change our product contract. Do not add all cloned Git histories/binaries to the application repository.

`main` retains the original history followed by the user's changes. Here `upstream` points to **NairoDorian/tiny11builder_2026**; ntdevlabs is a studied original, not the push target. Commit/push was authorized in this session. Keep commits focused and describe concrete behavior/validation/limits; never claim a release or successful installation solely because CI passes. Keep version labels unchanged until an intentional release decision.
