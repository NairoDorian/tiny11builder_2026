# Upstream merge plan: ntdevlabs WinUI 0.2.0 → Ultimate Tiny11 Builder 2026

Written **2026-11-04**. This is a **plan only**: no application code was changed when it was written. It is the work list for the next implementation sessions. Read [WORKING_NOTES.md](WORKING_NOTES.md) first for the host read-only boundary and evidence rules. They still apply to every task below.

## 0. What happened upstream

`ntdevlabs/tiny11builder` is no longer a PowerShell project. Between **2026-10-12 and 2026-10-30** (10 commits on top of the `00e7d8a` head we last audited) it became a native **C# / .NET 8 / WinUI 3** application:

| Fact | Detail |
|---|---|
| Default branch | `winui-preview` at `38f7ab6` (was `main`; `main` no longer exists). Old head `00e7d8a` survives as branch `tiny11WinUI`. Other branches: `experimental`, `legacy`, `revert-173-powershell_dism`. |
| Releases | Tags `winui-v0.1.0-preview.1`, `v0.1.1`, `v0.1.2`, `v0.1.3`, `v0.2.0` |
| Size | 124 files changed, +22,998 lines: ~5,800 lines of engine (`src/Tiny11Builder.Core`), ~3,500 of app/XAML (`src/Tiny11Builder.App`), ~11,000 of tests (40 xUnit files) |
| PowerShell scripts | `tiny11maker.ps1` / `tiny11Coremaker.ps1` / `autounattend.xml` are **byte-unchanged** since `00e7d8a`. Only README moved to `docs/usage.md`. The WinUI app does not call them. |
| License | **No license file.** Upstream's `NOTICE.md` states no license is assigned and that permission must be confirmed before redistribution. |

Local reference checkout: `repos/ntdevlabs_tiny11builder_upstream` is now on local branch `winui-preview` tracking `origin/winui-preview`. Its fetch refspec was widened to all heads, and local `main` still points at `00e7d8a` for comparison. Fetch audit: [verification/2026-11-04/reference-sync.json](verification/2026-11-04/reference-sync.json).

Other references at the same refresh: **18 unchanged**, `chrisGrando_tiny11maker-reforged` **updated** `b59c1b7 → 5c2d84d` (not yet reviewed). **`namnguyen97x/tiny-auto-builder` and `icis-org/tiny11builder` now return "Repository not found"**: their local checkouts are preserved and are now the only copies we have.

## 1. Decisions recorded on 2026-11-04

| # | Decision | Consequence for this plan |
|---|---|---|
| D1 | **One language: PowerShell.** Do not adopt upstream's C#/WinUI app or its UI code. Bring in all its features, reimplemented in our stack. | The existing small runtime-compiled `Add-Type` P/Invoke shims (`lib/OfflineRegistry.cs`, the inline privilege helper) stay acceptable: no compiler, SDK or `.exe` build. New native calls follow that same pattern. Flag any new shim in review. |
| D2 | **Reimplement behaviors; never copy** upstream C#, XAML, JSON catalogs or translation text. | Each task cites the upstream behavior and file as *study material*. Our code, strings and tests are written fresh. Credit in CHANGELOG/README. |
| D3 | **Resume: on by default, with an opt-out.** | Overrides the earlier "no saved checkpoint" performance rule *for crash recovery only*. Resumed runs are never reported as first-build timings (see C3 and E3). |
| D4 | **Keep the new Default preset** (Defender off, Ultimate Performance, Fast Shutdown). | Phase 0 regenerates TWEAKS/APPS and updates the three failing assertions; README/PROJECT_GUIDE text saying "Default keeps Defender" must change. |
| D5 | **GUI: keep and maintain the WinForms GUI as the working basis; a WPF/XAML wizard comes last**, planned only in a separate `docs/plan_new_ui.md` *after* the user approves the engine fixes and the new features in WinForms. Both GUIs are then maintained. | Section D is deferred; new features go into WinForms first. |
| D6 | **English only** for the interface. | C14 is limited to keeping strings centralizable; no other catalogs. |
| D7 | Protected preferences (`TaskbarDa`, default-user `IsDynamicSearchBoxEnabled`): **both**, the most dependable option. | Keep the policies **and** keep writing the values: `reg.exe` first, then the backup/restore handle with readback, then Offreg (A2). |
| D8 | Order: **engine fixes first**, then new features in the existing UI, then (after approval) the new-UI plan. | Section 4 phases follow this order. |

## 1a. Implementation status (2026-11-04)

| Done (regression-tested, uncommitted) | Not done yet |
|---|---|
| A1 native hive load (`reg.exe` fallback), A2, A3, A4, A5, A7, A9, A11, A12 | A1 per-job unique hive names and journals; A6 job directory/lock |
| B1, B2, B3 (cleanup skip, Core refusal, redundant-data guard), B4 + `-KeepUpdateUninstall`, B9, B10, B11, B12 | B5 family-boundary app matching; B6/B7 legacy Setup and WinRE A/B (need a disposable VM); B8 Core service diff |
| C2 `-UpdatePackage`, C4 `-RemoveRedundantData`, C5 `-OmitNetFx3Payload`, C6 `-ShrinkBootImage`, in the CLI and the WinForms Extras tab | C3 Resume (on by default), C7, C8 inventory, C9–C12, C13 `report.json`/`operations.json` |
| C1 *adapted* (2026-11-05): assisted *Get Windows 11* (official page in the browser + automatic pickup of the finished ISO or a copied link), resumable download from a Microsoft link, per-language SHA-256 recognition of any local ISO, offline tool readiness | — |

No fresh full ISO build or VM installation of this revision has been performed.

## 2. Side-by-side: what each project has

| Area | Ours (`2ae045d` + uncommitted work) | Upstream WinUI 0.2.0 | Merge action |
|---|---|---|---|
| Language / UI | PowerShell 5.1+7, WinForms 7 tabs | C# WinUI 3, 6-step wizard | WPF wizard in PowerShell (D) |
| Modes | Standard, Core, 4 presets, Custom flags/prefix lists | Tiny11, Tiny11 Core, Custom (groups + per-item expert actions) | Keep ours, add expert inventory (C8) |
| Source | ISO or drive; DiscUtils edition read without mount | ISO/folder; attach read-only via virtdisk; **official Microsoft download** | Add download (C1); keep DiscUtils |
| Edition export | wimlib/DISM, reuses original compressed resources | DISM export, keeps source compression; Turbo → fast working WIM | Keep ours; evaluate fast working WIM for Core (C17) |
| Final compression | **wimlib solid LZMS effort 100, 64 MiB chunks** (maximum), balanced, fast, none | DISM recovery / max / fast | Keep ours (stronger) |
| Metadata | Guard + supported wimlib repair of missing fields | Identity check with servicing-family equality (22621↔22631, 26200/26300↔26100) | Add family equality (B12) |
| Hive loading | `reg.exe load` at shared `HKLM\z*` aliases | `RegLoadKeyW` at unique `HKLM\Tiny11Builder_Offline_<guid>` + per-job journal | **Adopt** (A1) |
| Protected registry writes | Deferred Offreg file-only DWORD fallback; TaskCache ACL rewrite | `RegCreateKeyEx(REG_OPTION_BACKUP_RESTORE)` + `RegSetValueExW` + readback | **Adopt** as first path; keep Offreg as fallback (A2) |
| File deletion | `takeown` + `icacls /T` + `Remove-Item` | Backup-semantics handle + POSIX delete; **no ACL change on hard links**; extended paths; WOF/WIM tags allowed | **Adopt** (A3) |
| DISM child privileges | Not handled | Enables SeBackup/SeRestore/SeSecurity before launch (#660, error 1314) | Adopt (A4) |
| DISM flags | `/English` in a few places only | Always `/English /ScratchDir /LogPath /LogLevel:2` | Adopt (A5) |
| Job model | Transcript, manifest, `-WorkDirectory`; no cross-process lock | `tiny11-<guid>` job dir, exclusive `job.lock`, `job.json`, `operations.json`, `timings.json`, `report.json` | **Adopt** (A6, C13) |
| Cancel | `taskkill /T /F` on builder tree, then global `Clear-StaleBuildState` | Never kills DISM mount/commit; stops at stage boundary; discards own mount only | **Adopt** (A12) |
| Capabilities | Remove; count failures | Batch remove, re-read state; *Uninstall Pending* = deferred warning | Adopt (B1) |
| Optional features | None removed | XPS, Work Folders, IE optional, Recall: batch disable + verify | Adopt (B2) |
| Pending servicing | Not modelled | pending.xml/reboot.xml/registry markers; `0x800F0806` skip; Core refuses pruning | Adopt (B3) |
| Component cleanup | `/StartComponentCleanup /ResetBase` (Standard), Core ResetBase | Tiny11 **without** ResetBase; Core with | Keep ResetBase default; add opt-out (B4) |
| App matching | Prefix match against inventory + protected list | DisplayName equality + `PackageName` starts with `<name>_` | Add family-boundary matching (B5) |
| Core Setup | Modern Setup; zero-byte `winre.wim` placeholder | **Legacy Setup** via `winpeshl.ini` + `ProductKey WillShowUI=Always` (#645/#648) | Adopt, VM-gated (B6) |
| Edge cleanup | Deletes uninstall keys unconditionally when RemoveEdge | Deletes keys only when files are gone + identity/publisher checks | Adopt (B10) |
| Windows updates | None | Ordered local CAB/MSU, staged + hashed, verified inventory | Adopt (C2) |
| Resume / recover | None | Committed + compressed checkpoints, Resume, Recover workspace | Adopt, on by default (C3) |
| Redundant data | — | Allow-listed caches/logs/dumps, pending-aware | Adopt (C4) |
| Omit `sources\sxs` | — | Optional (~68 MiB) | Adopt (C5) |
| Smaller boot.wim | File-only hive patch (no mount) | Export Setup index only, bootable, max | Adopt via wimlib (C6) |
| Tweak catalog | **28 groups**, conditions, generated TWEAKS.md | ~13 policy groups in code | Keep ours; add the four missing Edge policies (B11) |
| Answer file | Accounts, password, locale, TZ, computer name, ZeroTouch, OOBE modes | Compact, local-account preference, product-key UI in legacy mode | Keep ours; add legacy-mode ProductKey (B6) |
| Payload / browsers / drivers | SetupComplete, FirstLogon, browsers, driver injection | — | Keep |
| Telemetry tasks / control set | Offline TaskCache removal; `Select\Default` routing | Writes services in all control sets; uses `Select\Current` | Keep ours (more correct) |
| Tool trust | Oscdimg pinned SHA; host DISM | Authenticode/catalog check of DISM + providers; servicing-version gate; Oscdimg pinned SHA | Adopt the gate + signature check (A9) |
| Output | Manifest + SHA-256; Oscdimg | ISO descriptor check, never overwrite, atomic/verified publish | Adopt (A11) |
| Localization | English only | en + zh-Hans JSON, validated, fallback | Adopt the mechanism, our own text (C14) |
| Tests / CI | ~1,920 PS checks, real WIM fixtures, dual-shell CI | xUnit suite, opt-in real-image tests | Keep ours; port test *scenarios* |

**Preserve these advantages of ours.** Upstream has none of them: wimlib maximum LZMS, no-mount DiscUtils edition read, file-only boot patch, metadata repair, the 28-group catalog and generated docs, presets/profiles, the full answer-file generator, payload/browsers/drivers, telemetry task removal, `Select\Default` routing, dual PowerShell 5.1/7, DryRun, equivalent command line and ETA.

Do not compare headline sizes. Upstream's 3.26 GB figure is a **Core** Turbo build; our 6.23 GB figure is a **Standard** maximum build with Photos/Terminal/etc. kept.

## 3. Workstreams and tasks

Each task gives the upstream study source, our target, and its acceptance tests. Priorities: **P1** correctness or safety, **P2** major feature, **P3** polish.

### A. Engine safety foundation

**A1 — Native, uniquely named offline hives (P1).** Study: `OfflineRegistry.cs` (`OfflineHive`), `BuildEngine.RecoverAsync`.
- Replace `reg.exe load/unload` in `Invoke-RegLoad`/`Invoke-RegUnload` with `RegLoadKeyW`/`RegUnLoadKeyW` through an `Add-Type` shim, inside a scoped SeBackup/SeRestore privilege enable.
- Use per-job key names such as `HKLM\T11_<jobid>_SOFTWARE`. The catalog's `HKLM\zSOFTWARE…` strings stay as **templates**, resolved the way `ControlSet001` already is. Telemetry-task, Offreg-deferred and test code paths follow the same resolver.
- Write a journal `<job>\hives\<key>.json` before the load and delete it after the unload. Recovery unloads only keys journalled by that job; `Clear-StaleBuildState` loses its blind z* sweep.
- For inspection-only reads (services inventory, pending probe), load a **private copy** of the hive plus its `.LOG1/.LOG2` files so transaction logs never replay into the image.
- Why: closes the documented "z* aliases are shared, not a lock" gap. It also returns the *native* `RegLoadKeyW` code for the still-unexplained `reg load` "filename or extension is too long" failure (BUILD_BUG_REPORT §1). That bypasses `reg.exe` but does not prove the root cause.
- Tests: mocked shim (success, error 1314/206/5), journal recovery, two concurrent fake jobs never collide, catalog template resolution, and a disposable real hive load/unload.

**A2 — Backup/restore registry writes with readback (P1).** Study: `OfflineRegistry.Set`, `OpenWriteKey`, `DeleteKeyTree`.
- `Set-RegistryValue`/`Remove-RegistryValue` open keys with `RegCreateKeyEx(..., REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS)` and write with `RegSetValueExW`, then read back.
- Access-denied DWORDs still fall back to the existing Offreg deferred path.
- `Enable-TaskCacheWriteAccess` ACL rewriting becomes unnecessary for deletions done through backup/restore handles; keep it only if tests show a remaining need.
- Decide whether protected preferences `TaskbarDa` and the default-user `IsDynamicSearchBoxEnabled` remain. Upstream deliberately drops them and relies on `Dsh\AllowNewsAndInterests` / `EnableDynamicContentInWSB` policies. Recommendation: keep them but try backup/restore first, then Offreg, and document either outcome.

**A3 — ACL-preserving native deletion (P1, also performance).** Study: `ImageFileAccess.cs`, `ImageOperations.DeleteTree/Remove`.
- New `Remove-OfflineImagePath`: `CreateFileW` with `FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT` on an extended `\\?\` path, then `SetFileInformationByHandle(FileDispositionInfoEx, DELETE|POSIX_SEMANTICS|IGNORE_READONLY_ATTRIBUTE)`, children first.
- Accept only WOF (`0x80000017`) and WIM (`0x80000008`) reparse tags inside the owned mount; refuse other reparse points.
- Replaces `takeown`/`icacls /T`, which today **rewrites ACLs and read-only attributes shared by WinSxS hard links** in a serviceable Standard image.
- Also replaces Core's separate `cmd /rmdir` WinSxS fallback (open item WORKING_NOTES #6).
- Upstream measured 3.55–4.12 s (ACL path) vs 0.69–0.75 s (native) for 4,000 files. That is *their* benchmark; re-measure ours.
- Tests: fixtures with hard links (ACL and read-only of the surviving link unchanged), long paths >260 chars, junction refusal, a WOF-compressed file, and the owned-mount guard.

**A4 — DISM child privilege inheritance (P1).** Study: `ProcessRunner.RunAsync` (#660).
- Around `Invoke-Native` for `dism.exe`, enable SeBackup/SeRestore/SeSecurity before `Process.Start` and restore them right after, on the same thread.
- Test: mocked privilege shim (enable, restore, restore failure still reaps the child).

**A5 — DISM invocation hygiene (P1).** Study: `DismClient.RunAsync/ParseImage`.
- Every `Invoke-DismChecked`/raw DISM call adds `/English`, `/ScratchDir:<job>\scratch`, `/LogPath:<job>\dism.log` and `/LogLevel:2`. Exit 3010 counts as success.
- Decode native output with the OEM code page, honouring a BOM, so localized (for example Cyrillic CP866) edition names parse. Check what `Invoke-Native` does today under a hidden GUI child versus a console.
- Tests: CP866 / UTF-8-BOM / UTF-16 fixtures.

**A6 — Job directory and cross-process lock (P1).** Study: `BuildJob.cs`, `JobCheckpoint.cs`.
- Each run creates `<WorkDirectory|scratch>\tiny11-<guid>\` containing `job.lock` (exclusive `FileStream`, held for the whole run), `job.json` (state and stage, atomic replace), `build.log`, `dism.log`, `recipe.json` (the effective request) and the `mount`, `media`, `scratch` and `setup` folders.
- Map our existing `tiny11` / `scratchdir` / `scratchdir_boot` layout into it, keeping old CLI paths working through a compatibility shim for one release.
- A second builder on the same job refuses to start. A global refusal (another job's mount is registered) protects the shared DISM state.
- This closes "isolation is not a cross-process lock".

**A7 — Path-safety parity (P1).** Study: `PathSafety.cs`, `BuildHost.cs`.
- Workspace must not be a drive root, profile root or Windows/Program Files.
- Output must be a **new** `.iso` outside system dirs, on a non-FAT32 drive, with ≥12 GiB free if on another volume. Existing output files are refused, never overwritten.
- Reject network paths and alternate data streams.
- NTFS becomes a hard failure when it cannot be verified. Today the default scratch drive is never checked (PROJECT_GUIDE §1).
- Reject reparse points in source/work/output chains. Keep our existing source/work overlap guard.

**A8 — Space admission (P2).** Keep `Get-RequiredScratchBytes` as the single authority. Add `3 × total update-package bytes` (C2) and the output-drive check. Record upstream's 2×-ISO rule in PERFORMANCE.md as a comparison, not a replacement.

**A9 — Servicing-tool trust and version gate (P1).** Study: `ToolLocator.cs`, `MicrosoftToolTrust.cs`.
- Locate System32 and ADK `dism.exe`. Verify a Microsoft signature, embedded or catalog, with `Get-AuthenticodeSignature`: PowerShell does this natively, no P/Invoke.
- Read the servicing engine version from `dismcore.dll`/`DismApi.dll` (the lower of the two), map the image build to its servicing base (22631→22621; 26200/26300→26100), and fail **before** any copy with ADK guidance when the tools are too old.
- Choose the newest trusted DISM.
- Our Oscdimg pin uses symbol key `3D44737265000`; upstream pins `688CABB065000` (SHA-256 `2000160B…BA861`). Compare both binaries' version resources before deciding. Default: keep ours.

**A10 — Media copy tuning (P3).** Robocopy already uses `/MT`. Optionally sort large files first and record copied/omitted bytes in the report (C13).

**A11 — Verified publication (P1).** Study: `BuildEngine.Tail` `VerifyAndPublishAsync`, `PublishFileAsync`, `IsoStructure.cs`.
- Master to `<job>\output.iso`. Validate size ≥ 34,816 bytes and a multiple of 2,048, plus an ISO9660/UDF descriptor (`CD001`/`BEA01`/`NSR02`/`NSR03`) at sector 16, then hash it.
- Same volume: no-overwrite rename. Other volume: copy to a unique `.partial`, flush to disk, re-hash, then no-overwrite rename.
- The manifest and sidecars are written after publication. Post-publication problems become warnings, never a failed build.
- Optional `-IsoSizeLimit` refuses publication and keeps the file (C7).

**A12 — Safe cancellation (P1).** Study: `ProcessRunner` (`finishOnCancellation`), `BuildSession.Stage`, `FailAsync`.
- Replace `Stop-GuiBuild`'s `taskkill /T /F`: the GUI writes a cancel request (`<job>\cancel.request`) that the builder polls at stage boundaries and between DISM operations. DISM mount/commit/export is **never killed**.
- On cancel: discard the owned mount, unload journalled hives, save logs and state, and report "Recovery required" if the discard fails. ISO mastering and downloads stay killable.
- Remove the global `Clear-StaleBuildState` from the GUI cancel path. Keep a hard kill only behind a second explicit confirmation, with a recovery warning.

### B. Servicing correctness

**B1 — Verified capability removal (P1).** Study: `DismClient.RemoveCapabilitiesAsync`, `BuildEngine.Capabilities.cs`.
- Batch repeated `/CapabilityName` arguments, then re-read `/Get-Capabilities`.
- *Not Present* means absent. *Uninstall Pending* means deferred: warn, and count it as kept. Anything else fails. Already-pending capabilities are reported, not re-requested.

**B2 — Optional feature removal (P2).** New catalog entries, gated by preset flags: `Printing-XPSServices-Features`, `WorkFolders-Client`, `Internet-Explorer-Optional-<arch>` and `Recall` (only if DISM lists it).
- Batch `/Disable-Feature /FeatureName:… /Remove`, then verify each state: *payload removed*, *disabled, payload retained*, *disable pending* or a failure.
- Add them to APPS.md generation.

**B3 — Pending-operation model (P1).** Study: `PendingOperations.cs`, `BuildEngine.Cleanup.cs`, `OfflineDataCleaner.AssessRegistryPending`.
- Detect `WinSxS\pending.xml`/`reboot.xml`, packages/features whose state ends in *Pending*, and the CBS `RebootPending`/`PackagesPending`/`RebootInProgress` and WU `RebootRequired` keys (read from a private hive copy).
- Component cleanup exit `0x800F0806`: Standard skips it with a warning; Core refuses.
- Core WinSxS pruning and Edge WinSxS removal are refused while anything is pending. Pending work is never deleted or reverted.

**B4 — Reorder servicing and fix the Core NetFx3 divergence (P1).** Adopt upstream's order: updates → apps → features/capabilities → **component cleanup** → **.NET 3.5** → registry → payload removals (with pending check) → Core pruning → commit.
- Enabling NetFx3 *after* `/ResetBase` removes the open item that Core's ResetBase can drop the NetFx3 payload (WORKING_NOTES #8). If NetFx3 leaves pending work, Core stops with an explanation.
- Keep `/ResetBase` as Standard's default (smallest image; matches the size/compression priority). Add `-KeepUpdateUninstall` (no ResetBase), which is upstream's Tiny11 behavior.

**B5 — Package-family-boundary app matching (P2).** Match `PackageName` against `<prefix>_` (family boundary), or the exact DisplayName, instead of a bare prefix, so `Microsoft.People` cannot match `Microsoft.PeopleExperienceHost`. An explicit `*` suffix in `removePackage.txt` keeps today's prefix behavior. Test against recorded 26300 inventories.

**B6 — Legacy Windows Setup for Core and payload removals (P1, VM-gated).** Study: `SetupInstaller.cs`, `UnattendBuilder.cs`.
- When Core or any Custom WinSxS/file-payload removal is selected, write `Windows\System32\winpeshl.ini` (`[LaunchApps]`, `%SYSTEMROOT%\System32\wpeinit.exe`, `%SYSTEMDRIVE%\sources\setup.exe`, or `setup_old.exe` when present) into the Setup index of boot.wim.
- Use our **file-only** path (`wimlib-imagex update` add/replace), so there is still no boot mount. Fail if the matching classic `setup.exe` is absent. Never borrow binaries from another release.
- In that mode only, the answer file adds `UserData/ProductKey/WillShowUI=Always` without a key. This is upstream's fix for "Windows cannot read the `<ProductKey>` setting" (#645/#648).
- Acceptance requires a disposable UEFI VM boot to the Setup wizard for Core 26300 x64. It cannot be claimed from unit tests.

**B7 — WinRE placeholder A/B (P2, VM-gated).** Ours keeps a zero-byte `winre.wim`; upstream deletes it outright. Decide by VM test of both on Core.

**B8 — Core service/policy parity (P2).** Disable `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `WinDefend`, `WdNisSvc`, `WdNisDrv`, `WdFilter` and `Sense` in the image's selected control set. Upstream writes all control sets; we write `Select\Default`, which is more correct. Keep that, and optionally also write other existing sets. Also set `NoAutoUpdate`, `DisableWindowsUpdateAccess`, `DisableAntiSpyware` and `DisableRealtimeMonitoring`. Diff against our `WindowsUpdateOff`/`DefenderOff` groups and fill gaps.

**B9 — Core WinSxS keep-list guard (P1).** Compare `Assert-WinSxSRebuild`'s keep patterns with upstream's, which preserves metadata dirs `Catalogs`, `FileMaps`, `Fusion`, `InstallTemp`, `Manifests`, `SettingsManifests` and `Temp`, plus `common-controls`, `gdiplus`, `isolationautomation`, `proxystub`, `vcNN.crt` and the servicing stack. Adopt the refusal "native-arch common-controls/gdiplus/servicing family not found → prune nothing".

**B10 — Guarded Edge removal (P1).** Study: `ImageOperations.RemoveOriginalFiles`, `EdgeRegistration.cs`.
- Also remove `Program Files\Microsoft\{Edge,EdgeCore,EdgeUpdate,EdgeWebView}`.
- Move the uninstall-key deletions out of the unconditional `EdgeRemoval` catalog `Delete` list. Delete `Microsoft Edge`, `Edge Update` and `EdgeWebView`/`WebView2 Runtime` entries in both 32/64-bit Uninstall views **only when their files are verifiably gone** and `DisplayName`/`Publisher=Microsoft Corporation` match. Otherwise retain and log.
- WebView2 rules (preset `RemoveWebView`) stay ours.

**B11 — Missing Edge policies (P3).** Add `HideFirstRunExperience=1`, `ShowRecommendationsEnabled=0`, `UserFeedbackAllowed=0` and `SpotlightExperiencesAndRecommendationsEnabled=0` (HKLM Policies\Microsoft\Edge) to a documented group, with Microsoft policy links, and regenerate TWEAKS.md. Every other upstream policy and app target is already in our catalog (verified 2026-11-04).

**B12 — Servicing-family identity (P2).** `Assert-InstallImageMetadata` accepts a build change within one family (22621↔22631; 26100/26200/26300) only when edition, installation type, architecture and revision still match (#669). Tests cover accepted transitions and rejected unknown families such as 26340 (#638).

### C. New features

**C1 — Official Microsoft ISO download (P2).** Study: `LatestWindowsMedia.cs`, `OfficialImageDownloader.cs`, `OfficialTransport.cs`.
- `-DownloadLatest [-Architecture x64|arm64] [-DownloadLanguage]` resolves Microsoft's current Windows 11 ISO through the official software-download flow. Unsupported languages fall back to English with a message.
- `-DownloadUrl <link> -DownloadSha256 <hash>` takes a manual link for other languages or Insider builds.
- Rules:
  - HTTPS only, with a host allow-list checked on **every** redirect: `www.microsoft.com`, `vlscppe.microsoft.com`, `ov-df.microsoft.com`; ISO hosts `software.download.prss.microsoft.com`, `software-download.microsoft.com`, `download.microsoft.com`.
  - Strong-ETag resume of `.part` files. Expiring link tokens are never persisted.
  - 32 GiB cap and a 1 GiB free-space margin.
  - Bounded retries with a TLS 1.2 fallback after a handshake reset. Certificate validation is never disabled.
  - ISO structure check, then SHA-256 against the published hash when given. Never overwrite.
- Works on PS 5.1 (`System.Net.Http`) and 7. Downloads land in the project/workspace, never system folders.
- Risk: Microsoft changes this flow. Fail clearly and link the official page.

**C2 — Offline Windows update integration (P2).** Study: `WindowsUpdates.cs`, `BuildEngine.BuildAsync`.
- `-UpdatePackage <path[]>`, applied in the given order: `.cab`/`.msu` only, ≤100, no duplicates, no folder scanning, no downloads.
- Packages are copied into `<job>\updates\NNN\` with a SHA-256 copy check, then `/Add-Package /PackagePath /NoRestart` runs before removals.
- Afterwards, re-read `/Get-Packages` and record each package's hash, outcome and post-inventory in the report. Pending items feed B3.
- Package lists and order are saved in profiles. A resume after commit does not need the package files.
- GUI: an ordered list with Add/Remove/Move up/Move down.

**C3 — Resume and Recover workspace, on by default (P2; D3).** Study: `BuildEngine.Tail` checkpoints, `BuildEngine.Resume.cs`, `JobCheckpoint.cs`.
- After a successful commit, write an atomic, flushed `checkpoint.json` containing the effective-request hash, source identity, image identity, working-WIM length+SHA-256 and a hashed manifest of staged media.
- After final compression, a second checkpoint records the compressed container. That saves the ~838 s maximum LZMS export on a retry of mastering.
- Setup-image edits work on a private copy, with "replacing → applied" states recorded around the swap.
- `-Resume <job.json>` re-verifies the lock, hashes, tools, request hash and output path before continuing. Changed choices, stale or corrupt checkpoints, active jobs and pre-checkpoint jobs are refused.
- `-RecoverJob <job.json>` discards one job's mount, hives and staging, and refuses a checkpointed job unless `-DiscardSavedProgress` is given.
- Opt-out: `-NoResume` / GUI toggle "Save resumable progress". It skips the hashing cost.
- `timings.json`/the manifest mark `Resumed=true`, and resumed runs are **excluded** from first-build benchmarks.
- Measure the added hashing time on the 26300 input and record it.

**C4 — Redundant offline data cleanup (P2).** Study: `OfflineDataCleaner.cs`.
- `-RemoveRedundantData` (off by default) uses a fixed allow-list: `SoftwareDistribution\Download`, `Windows\Temp`, default-user Temp, `Logs\CBS\CbsPersist_*.cab|.log`, `Logs\DISM\*.bak`, `MEMORY.DMP`, `Minidump\*.dmp`, WER ReportArchive/ReportQueue.
- Servicing-sensitive targets are retained when pending state is pending or unknown (B3). Root folders are kept.
- The report records logical bytes removed, not compressed savings.

**C5 — Omit the .NET 3.5 setup payload (P2).** `-OmitNetFx3Payload` excludes `sources\sxs` from the staged media (~68 MiB on 26300 per upstream).
- `-EnableNetFx3` must then read `sxs` from the **attached source**, not the staged copy. Today both makers use `$workRoot\sources\sxs`.
- Warn that adding .NET 3.5 later needs matching media.

**C6 — Smaller boot.wim (P2).** `-ShrinkBootImage` exports only the Setup index (the one named Setup, else index 2) into a fresh bootable LZX-maximum WIM with wimlib `--boot`. LZMS is not bootable.
- Verify one image, a boot index of 1 at header offset 120, and that identity matches. Then apply our file-only hive patch and B6.
- Record before/after bytes. Upstream saw 611,776,274 → 597,781,118 on 26300 x64.

**C7 — Optional ISO size limit (P3).** `-IsoSizeLimit <bytes>` (64 MB–4 GB): an oversize result stays in the job, unpublished but resumable.

**C8 — Advanced component inventory and expert actions (P2).** Study: `ImageInventory.cs`, `ImageOperations.ReadNativeInventory`, `FilePayloadCatalog.cs`, `InventoryAsync`.
- `-Inventory -OutputList <file.txt>` mounts the selected edition read-only (an ESD is first exported to a fast WIM) and lists:
  - provisioned apps, `Windows\SystemApps`, features, capabilities and packages;
  - services, from a private SYSTEM copy;
  - WinSxS component folders and file-payload folders.
- It then discards the mount and writes a UTF-8 export with stable English headings.
- `-ExpertActions <json>` takes Disable/Remove for features and services, Remove for the rest, and requires `-AcceptExpertRisk`. Each action is revalidated against the actually mounted image at build time. Removing a service deletes its registration, never shared binaries.
- GUI: "List all components…" with search, a type filter, the risk consent and "Export complete list".

**C9 — Custom-only direct payload groups (P3, dangerous).** Study: `NativePayloadOptions.cs`.
- Groups: remove 32-bit support (SysWOW64/SysArm32), desktop .NET, IME files, speech/OCR files, printer/scanner driver-store folders (`prn*`/`scan*`/`mfd*`), and wallpapers/sounds/help/cursors.
- Each requires Custom, the expert acknowledgement and B6 legacy Setup. Never in a built-in preset.

**C10 — Extreme VM preset (P3).** An optional `presets/Extreme-VM.json` combining Core and C9 groups, with an optional size target. Clearly labelled VM-only, not guaranteed to boot.

**C11 — Upstream recipe import (P3).** `data/upstream-recipe-map.psd1` maps upstream `SelectedOptions` ids (for example `copilot-app`, `edge-files`, `hardware-bypass`) to our flags and groups. `-ImportRecipe <json>` reports unmapped ids and never silently drops them. This is interoperability only; it uses no upstream code.

**C12 — Preset transparency (P2).** A read-only "What this preset does" view per mode/preset, generated from the same planners: app families, capabilities, features, tweak groups and files. It is labelled "configured actions, not confirmed present in this image".

**C13 — Structured reports (P2).** Study: `BuildOperationTracker.cs`, `CompleteAfterPublish`.
- Extend `Write-BuildManifest` into `report.json`: image identity, flags, compression/engine, capability/feature outcomes, cleanup bytes, copied/omitted media bytes, boot.wim before/after, updates, warnings, `Resumed`, `BootValidated=false`.
- Add `operations.json`: id/stage/title/state/detail/duration per operation, **including failures**.
- Add `timings.json`: per-stage durations.
- Emit operation ids through the existing `__TINY11_PROGRESS__` protocol for the GUI stage board.

**C14 — Interface localization (P3).** `gui/Languages/en.json` is the baseline. Optional files are discovered at startup and validated: same keys, placeholders preserved, ≤2 MiB, plain text only. Missing strings fall back to English, and the choice is saved in GUI settings. Our own text only, so upstream's zh-Hans catalog is not copied. Languages beyond English are an open question.

**C15 — Edition default (P3).** When no `-Index`/`-Edition` is given in GUI first use, preselect Pro, else index 1. A saved profile's edition wins if it still exists. Never fabricated.

**C16 — Compatibility statement (P3).** Document host requirements (Windows 10 2004+ with a current ADK for 26100-family images) and that Server images are refused. `Get-ImageInfo` should reject `Installation != Client`.

**C17 — Core fast working image (P3, measure first).** Upstream's Turbo uses a fast-compressed working WIM for Core/Fast builds: Core commit went from 29m38s to 3m54s in their runs. Our first export reuses the original LZX resources. Benchmark an XPRESS working WIM for Core only. Final maximum LZMS is unchanged.

### D. WPF/XAML wizard GUI (pure PowerShell)

Replace the WinForms tabs with a wizard that follows upstream's *layout ideas*, built from our own XAML and code, and carries every option we already expose.

| Step | Content |
|---|---|
| Sidebar | Numbered steps, selected-image badge ("source files are not modified"), Resume build, Recover workspace, Appearance (System/Light/Dark), Interface language, links |
| 1 Welcome | Three large mode cards: **Standard**, **Core** (caution badge), **Custom**. Choosing one opens step 2 |
| 2 Windows image | "Download latest Windows 11" card with progress; local ISO/folder card with **Load editions** (DiscUtils, no mount) and edition picker; "Other official downloads" expander (link + SHA-256) |
| 3 Components | Preset picker (Default, Gaming, PrivacyPlus, Minimal-VM, custom file); read-only plan expander; app list with Keep/Remove utilities; capabilities/features; advanced inventory (C8) behind consent |
| 4 Tweaks | Our 28 catalog groups as cards with the per-value detail pane we have today |
| 5 Setup & account | Answer-file options; ZeroTouch with a disk-0 warning banner; OOBE modes; local account; compact install |
| 6 Extras | Payload, browsers, drivers, .NET 3.5, ordered update packages (C2), DefenderExclusion (hidden when not authorized) |
| 7 Build settings | Workspace — **exposes `-WorkDirectory`**; output ISO; compression with an advanced expander for **engine/effort/threads** (closes the "no visible selectors" item); toggle cards: Save resumable progress (on), Remove redundant data, Omit .NET payload, Shrink boot.wim, Keep update uninstall, Keep working files, Quick test build, Boot without key prompt, Dry run |
| 8 Review | Cards for image / mode+removals / output+workspace / options, full plan text, equivalent command line with Copy, Save/Load profile |
| 9 Create image | Overall + current-step bars, our ETA, a stage board with expandable operation rows (pending/running/completed/skipped/failed/not run), live log expander, **Cancel safely** (A12) and a result card (path, SHA-256, size, warnings, open folder/report, copy log) |

Engineering rules:
- XAML lives in `gui/*.xaml`, logic in `lib/tiny11wpf.psm1`. Loaded with `[Windows.Markup.XamlReader]`; requires an STA thread, so the launcher relaunches with `-STA` when needed.
- Themes are two ResourceDictionaries. The system light/dark choice is **read** from the user's settings; nothing on the host is written.
- `ConvertTo-GuiBuildRequest`, the CLIXML launch file, `__TINY11_EXIT__` and the log tail are reused unchanged, with a `DispatcherTimer` replacing the WinForms timer.
- Sidebar and Next share one validation function that explains what blocks a step.
- Accessibility names, keyboard navigation (Alt+Left = Back), high-contrast fallback.
- Test hooks are kept: `-PreviewPath` (window render through `RenderTargetBitmap`, not a screen grab), `-PreviewTab`, `-AutoRun Build` with the fake builder, `-InitialState`. Port every existing GUI assertion, then regenerate `docs/gui-*.png`.
- Migration: `tiny11gui.ps1` opens WPF; `-LegacyGui` keeps WinForms for one release, then remove it.
- PS 5.1 (.NET Framework WPF) and PS 7 (.NET WPF) are both supported. No Mica; solid theme colors.

### E. Data, references and documentation

- **E1** Update `data/reference-repos.json`: ntdevlabs branch `winui-preview`. The sync script must fetch an explicit `+refs/heads/<branch>:refs/remotes/origin/<branch>` so single-branch clones survive a branch change, and must report vanished repositories (namnguyen97x, icis-org) as `unavailable (preserved)` instead of failing. Review chrisGrando `5c2d84d`.
- **E2** Add an upstream WinUI 0.1–0.2 section to REFERENCE_REVIEW.md (or a dedicated review file) with the adopted/excluded table, the issue mapping (#638–#670) and attribution. Add the CHANGELOG credit.
- **E3** WORKING_NOTES/VERIFICATION: Resume on by default (D3); resumed runs excluded from benchmarks; the new Default preset (D4); this plan's status.
- **E4** Add a `NOTICE.md` explaining that the original upstream scripts carry no license, our MIT applies to our contributions, and no upstream WinUI code is included.

## 4. Phases and order

| Phase | Tasks | Gate before moving on |
|---|---|---|
| **0 Housekeeping** | Run all suites on the 15 uncommitted files and commit them; apply D4 (regenerate, fix 3 assertions, README/guide wording); E1, E4 | All suites green in both shells; `update-generated -Check` passes |
| **1 Engine foundation** | A1, A2, A3, A4, A5, A6, A7, A11, A12, A9 | New fixtures green; one fresh DryRun + one real Standard build from the original ISO; saved-image inspection |
| **2 Servicing correctness** | B1, B2, B3, B4, B5, B8, B9, B10, B11, B12 | Fixtures + catalog tests; fresh Standard **and** Core builds; image inspection |
| **3 Build features** | C2, C3, C4, C5, C6, C13, C7, A8 | Resume tests (kill at each boundary in fixtures); measured hashing cost; fresh builds with each toggle |
| **4 Legacy Setup** | B6, B7 | **Disposable UEFI VM** boot to the Setup wizard for Core; record the Panther result |
| **5 Source acquisition** | C1 | Offline-mocked transport tests; one live download check (resolve + partial resume) |
| **6 Expert** | C8, C9, C10, C11, C12 | Read-only inventory on a real image (source timestamp unchanged); expert actions on fixtures |
| **7 WPF GUI** | D, C14, C15 | All GUI assertions ported; fake-builder build in both shells; screenshots regenerated. Can start in parallel once Phase 1 fixes the job/operation/progress model |
| **8 Validation** | C16, C17, full matrix | Fresh Standard + Core builds of the final revision; VM install for each; ARM64/driver/multilingual where possible; PERFORMANCE.md update |

Phase 1 comes first because A1/A3/A6/A12 change shared helpers that every later task relies on, and they fix existing safety gaps (shared aliases, ACL rewrites on hard links, killing DISM mid-commit).

## 5. Risks and constraints

- **Host boundary.** Everything targets offline image files or project/workspace folders. `RegLoadKeyW` temporarily attaches *owned image hives*, which is already authorized. No host registry, Defender, task, priority or toolchain change. Downloads write only to the workspace.
- **No overlapping writers.** Even with A6's lock, the developer workflow still runs one builder at a time.
- **P/Invoke shims.** Each new `Add-Type` adds startup compile time and must work on PS 5.1 and 7. Group the shims into one source file, as with `OfflineRegistry.cs`.
- **Catalog path templating (A1)** touches every `HKLM\z*` entry, the TaskCache code and many tests. Do it in one focused change with the regenerated TWEAKS.md diff reviewed.
- **Microsoft download flow (C1)** is undocumented and can change without notice.
- **Legacy Setup (B6)** behavior on 26H2 is unproved here until VM-tested. Upstream's own evidence is a boot-to-wizard check, not a completed install.
- **Resume (C3)** adds hashing time to every default build. Measure it. If it is large, revisit the default with the user.
- **Evidence levels** from VERIFICATION.md apply. Unit tests never stand in for a fresh build or a VM install.

## 6. Open questions for the user

1. Should the dangerous direct-payload groups (C9/C10) be exposed at all, or left out?
2. May a disposable VM be used to validate B6 (legacy Setup for Core) and a fresh full build of this revision?

Answered 2026-11-04: D5 (WinForms kept; WPF later via `plan_new_ui.md` after approval), D6 (English only), D7 (both), D8 (engine first).
