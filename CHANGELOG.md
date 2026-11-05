# Changelog

## Unreleased - getting and recognizing the ISO, offline readiness, GUI help (2026-11-05)

- **Assisted near one-click download** (GUI *Get Windows 11...*, `tiny11iso.ps1 -Get`):
  - the app opens Microsoft's page in the browser; the person chooses the language and clicks *Download*;
  - the app then picks up the finished ISO from the real Downloads folder (or a Microsoft link copied after the click, which it downloads itself), and selects, loads and verifies it automatically;
  - it shows the browser's progress while waiting and stops after 45 minutes.
  - Detection is tested (11 new checks).

- **Official ISO recognition (informational, never blocking).** New `lib/tiny11download.psm1` and `tiny11iso.ps1 -Verify`:
  - the ISO's SHA-256 is compared with the per-language table on Microsoft's static Windows 11 download pages (x64 and ARM64, 38 languages, current release);
  - results are *Verified*, *NotListed* (older/Insider releases are not listed) or *Unavailable* (offline);
  - the GUI checks automatically after *Load editions* and stops when a build starts.
  - Live check: the local `Windows11_Client_x64_en-us_26300_9457.iso` matched Microsoft's **26H2 English 64-bit** entry; hashing took 11.6 s.
- **Download from a Microsoft link** (`tiny11iso.ps1 -Url`, GUI *Download from link...*):
  - Microsoft hosts only, checked on every redirect;
  - strong-ETag resume of `.part` files (also with a fresh link);
  - bounded retries, free-space check, optional expected SHA-256, never overwrites.
  - *Get Windows 11...* (formerly *Open download page*) opens Microsoft's page in the browser.
- **Easier ISO selection:** ISOs in Downloads/Desktop listed, drag-and-drop anywhere on the window, Browse starts in the current ISO's folder.
- **Offline readiness:**
  - Build-tab Checks state whether oscdimg/wimlib are on the PC; *Prepare offline tools* / `tiny11iso.ps1 -PrepareTools` fetches them.
  - A missing oscdimg offline now gives an actionable message.
  - Documented that nothing else needs the internet during a build.
- **GUI help:** mouse-over help for every interactive control (81 entries, wrapped and shown for 20 s), enforced by a test. README *Getting the ISO*, *Working offline* and tab descriptions updated.
- **Fixes found in the code pass:**
  - downloading a copied link failed at the first progress update for every real ISO ("Cannot convert value 9062821888 to type System.Int32"): sizes above 2 GB hit the Int32 `[Math]::Max` overload. The GUI and `tiny11iso.ps1` now share `Format-IsoDownloadProgress` (Int64-safe, estimates over 24 h no longer wrap), and a progress display error no longer aborts the transfer (8 new checks with a 9 GB total);
  - closing the window during a build force-killed DISM; it now cancels safely and closes afterwards;
  - cancellation now fires once, so emergency cleanup cannot be interrupted;
  - an output ISO that is mounted/open is refused at the start, and a lock appearing at publish time keeps the verified ISO under a dated name instead of deleting it;
  - the GUI tooltip table pairs were flattened by PowerShell (caught by tests before release);
  - Core's help documented 25 parameters only by reference: all parameters are now documented, and a test enforces `.PARAMETER` help and README coverage for every builder parameter and the GUI-to-builder argument contract;
  - README statements about Cancel, Defender, Core WinSxS and group counts are corrected.
- **Validation:** 46 offline ISO-download/hand-off checks in both shells, plus the core/media/export suites (see VERIFICATION.md). No fresh full ISO build or VM installation of this revision.

## Unreleased - upstream WinUI 0.2 behaviors reimplemented in PowerShell (2026-11-04)

ntdevlabs/tiny11builder became a C#/WinUI 3 app (`winui-preview`, v0.2.0, no license file).
None of its code is copied; the behaviors below were reimplemented and are credited to it.
See [docs/UPSTREAM_MERGE_PLAN.md](docs/UPSTREAM_MERGE_PLAN.md) for the full plan and status.

- **Safety and correctness:**
  - Image files are deleted through backup-semantics handles (`lib/NativeImage.cs`) instead of `takeown`/`icacls`, so ACLs and read-only attributes shared by WinSxS hard links are never rewritten. Paths over 260 characters work, and links are deleted without being followed.
  - Core trims WinSxS in place, after a guard that the native runtime families and store metadata exist. The old sequence (`takeown /R` + `icacls /T` + copy + `cmd rmdir`) rewrote the ownership of System32 files through their hard links.
  - Hives load through `RegLoadKeyW` first (real Win32 codes), with `reg.exe` as fallback.
  - An access-denied registry write now tries a backup/restore handle with readback before the Offreg fallback. Deletes do the same.
  - DISM always gets `/English`, a session log and a work-drive scratch folder.
  - The builder enables servicing privileges on its own token, which DISM children inherit (upstream #660).
  - The servicing-tool gate rejects too-old DISM early (26200/26300 map to the 26100 family). NTFS is now verified on the default drive too, and output/work-folder locations are checked.
  - ISOs are mastered to a partial file, checked for an ISO9660/UDF descriptor, and only then replace the output.
  - GUI Cancel is a safe cancel at stage boundaries; force stop needs a second, explicit confirmation.
- **Servicing:**
  - Component cleanup runs before .NET 3.5 in both builders, which closes the ResetBase/NetFx3 divergence.
  - `0x800F0806` (pending operations) is a reported skip. Core refuses to trim WinSxS while servicing is pending.
  - Capability removals are re-read (`UninstallPending` = deferred).
  - Legacy optional features (XPS printing, Work Folders, IE optional, Recall) are removed with verification.
  - Edge/WebView2 uninstall entries are deleted only when their files are gone and the entry is Microsoft's. Edge removal now also covers `Program Files\Microsoft`.
  - New `EdgePromotions` group (4 documented Edge policies).
- **New options (CLI + WinForms Extras tab):**
  - `-UpdatePackage`: ordered, privately staged, hash-checked CAB/MSU integration. The expected version is re-based within the same servicing family.
  - `-OmitNetFx3Payload`, `-ShrinkBootImage` (Setup-only bootable boot.wim), `-RemoveRedundantData` (pending-aware allow-list) and Standard `-KeepUpdateUninstall`.
- **Presets:** Default now disables Defender and enables Ultimate Performance and fast shutdown (user decision). The built-in table matches the JSON files, and a test enforces that value by value. The GUI refuses to overwrite built-in preset files.
- **References:** the catalog moves ntdevlabs to `winui-preview`. The sync script uses an explicit refspec and reports deleted repositories (namnguyen97x, icis-org) as preserved. Added `NOTICE.md`.
- **Validation:** PowerShell 7: 2,077 core checks passed; Windows PowerShell 5.1: 2,075 passed. 129 real export and 23 media/progress checks passed; generated freshness, parser and lint passed. **No fresh full ISO build or VM installation of this revision.**

## Unreleased - comment and documentation accuracy pass (2026-10-05)

- Correct comments that stated the opposite of the code: the GUI module header
  claimed the window never reads ISO metadata through a file stream (it does, via
  lib\tiny11media.psm1); `lib/AdjPriv.cs` claimed to be what Enable-Privilege
  loads (that function compiles an inline copy); Core's section banner claimed
  Edge's WinSxS payload is removed by Remove-EdgeFiles (it is removed indirectly
  by the WinSxS allowlist rebuild); `Get-PresetFlagNames` claimed to report
  unknown preset keys (the test does that); the preset test comment promised a
  value comparison against the Default table that no assertion performs.
- Document load-bearing behavior that had no comment: the legacy `recovery`/`max`
  compression aliases and what they actually mean; the label-to-stage mapping in
  Invoke-DismChecked; hive ownership tracking in Invoke-RegLoad; the wimlib
  compression-flag table and its fixed index 1; the 0x10d00/0x40000 WIM header
  constants; why the edition export compresses differently on its DISM fallback;
  the 1.5x/20GB scratch rule and that NTFS is unverified on the default scratch
  drive; robocopy's "< 8 is success" convention; the MAX_PARALLEL_JOBS clamp;
  build 26100+ SecHealthUI protection; the MAX_PARALLEL/WinSxS/keepPattern
  dependencies; Standard's -NoResetBase/EnableNetFx3 rule and Core's divergence
  from it; the GUI stage-range table's unreachable payload entry and 99% cap; the
  ETA sampling gates; oscdimg flags and the 32-character label limit.
- Correct stale help text: `update-generated.ps1` now lists all five generated
  files (it documented two, including that the module manifests are generated);
  `tiny11maker.ps1` no longer claims PowerShell 5.1 only; Core's `.NOTES` now
  lists the three compression parameters it actually accepts; Core's `.PARAMETER
  Preset` and `.DESCRIPTION` state the full forced-flag set.
- Add a "Reading the source" section to the documentation index mapping each
  source file to the contract its comments carry, plus the three easy-to-miss
  facts (Offreg means offreg.dll not offreg.exe; z* aliases are shared; APPS/TWEAKS
  are CI-generated).
- Record in WORKING_NOTES/PROJECT_GUIDE the scratch-space rule, the NTFS
  verification gap, the drive-vs-ISO edition-reading difference, the stage-range
  coupling, the compression aliases, and Core's missing -NoResetBase guard as an
  open item rather than a settled behavior.
- Comments and documentation only. No patch feature, preset value, generated
  catalog, answer XML, module manifest or visible GUI control changed.
- Fix README accuracy found in a second audit: document the real oscdimg
  resolution order (ADK, script-local, PATH, then warm cache, download last) rather
  than "otherwise it is downloaded"; add the missing `-Help` option row; state
  that the legacy `recovery`/`max` aliases do not match their names; and flag
  that `presets\*.json` is the authority for preset behavior, so the preset table
  and "Default keeps Defender" must be read against the current files.
- Correct my own count: `update-generated.ps1` owns **six** generated files, not
  five (two answer XML files plus two module manifests), matching CONTRIBUTING.md.
- Add comments for two more undocumented decisions: why `Invoke-Native` has two
  execution paths (concurrent pipe draining vs. direct call, and the different
  argument-quoting rules that follow), and that `Invoke-SafeOfflineRegistryUnload`
  bypasses the deferred-DWORD retry because it is the never-throw emergency path.
- Document duplicated state that can silently drift: the offline hive name list
  exists in both `Dismount-OfflineHives` and `$Script:OfflineHiveNames`, and
  `Get-AvailableImageIndex` is legacy DISM-text scraping kept for compatibility
  while the builders use structured WIM reads.
- Verified: parse-check, linter, test-core-helpers (1918 passed with the tracked
  presets\default.json), test-media-progress (23) and test-export-pipeline (129).
  The 3 preset/catalog failures and stale `docs/TWEAKS.md` seen with the
  uncommitted GUI-save overwrite of presets\default.json are unchanged by this
  pass; see WORKING_NOTES item 9. No full build or VM installation was performed.

## Unreleased - complete Markdown handoff and state reconciliation (2026-10-05)

- Replace append-only working notes with current permissions, implementation,
  verified revisions/results, artifact availability and concrete open work.
- Add documentation index, complete architecture/pipeline/GUI/dependency guide,
  and verification matrix/run procedure so future agents can understand the
  project from Markdown before reading implementation details.
- Reconcile user/contributor/extension documentation with actual behavior:
  WorkDirectory is CLI-only; advanced compressor values are profile state;
  DryRun can write logs/attach source; cleanup is best-effort; legacy max means
  balanced; payload staging is top-level and CMD/PS1 execute as separate groups.
- Update generated APPS/TWEAKS through their generator, including control-set
  routing/scope and a corrected uninterrupted preset table. No patch features,
  preset values, answer XML, module manifests or visible GUI controls changed.
- Date dependency/PR/reference claims, remove stale pending benchmark wording
  and deleted-raw-log availability claims, and consolidate latest application
  CI/tests separately from historical full builds and unresolved VM/launch gaps.

October application improvements are unreleased commits. Existing version labels
remain 2026.09 / 2026.9.0. Earlier entries below describe the code at their own
revision/date; superseded cleanup/tool/GUI claims are not current guarantees.
Use docs/WORKING_NOTES.md and docs/PROJECT_GUIDE.md for the current contract.

## Unreleased - reference refresh and early dependency readiness

- Download the six requested reference branches; fetch all 15 existing
  checkouts. Track the 21-project inventory, source-only fast-forward refresh
  helper, exact revisions and detailed fork/original comparison.
- Adapt PR #604 in both makers: obtain Oscdimg before source/image work,
  retain the small checksum-pinned portable tool, verify cache integrity,
  publish downloads atomically, and use the prepared path for final mastering.
  Dry runs do not download; first-use image optimizations remain unchanged.
- Read offline SYSTEM Select\Default for catalog registry/service writes and
  deletes; refuse invalid/missing selections rather than silently changing the
  wrong control set. Reset state after unload and preserve cleanup tracking.
- Reject overlapping source/work trees before destructive workspace cleanup
  or recursive copying. Add documented cloud-search blocking under the
  existing optional Search group; Advertising ID protection already existed.
- Preserve single-edition processing, app choices and maximum compression.
  No unverified NVMe overrides, extra framework removals, CI host/RDP changes,
  raw XML rewrites, prior patched-image reuse or Linux recapture were imported.

## Unreleased — upstream PR adaptations and measured builds

- Adapt upstream #623: separate driver-enabled Setup mount, bounded native
  PowerShell folder cleanup, refuse mounted/redirected directories, and retain
  image files after failed dismount or unknown mount state.
- Adapt #628/#583: restore missing Setup edition/product/language fields from
  the actual source using wimlib XML properties; retain integrity/compression,
  reject conflicts and require saved-image readback. Valid metadata is a no-op.
- Adapt verified missing #622 Edge AI policies under the existing RemoveAI
  option; preserve Photos choices and the documented Paint policy path.
- Record two fresh Windows 26H2 builds: 9m18s / 14.75 GB uncompressed versus
  21m06s / 6.23 GB maximum, with independent saved-image verification. Preserve
  compact benchmark/cleanup evidence and keep generated media outside the repo.

## Unreleased - fresh-build safety and diagnostics

- Add isolated `-WorkDirectory` support, preserving other build folders and
  permitting short offline-work paths without changing live Windows settings.
- Test a disposable offline hive before copying/mounting the installation image;
  preserve native errors and explain the reproduced launch-context failure.
- Validate the final image's edition, language, product and version XML against
  its source before ISO creation. Refuse duplicate/intermediate install images.
- Remove the automatic CPU-priority adjustment and the cross-shell scratch
  deletion fallback; refuse deleting an image that remains mounted.
- Document controlled hive-load tests, upstream compression/duplicate-image/
  cleanup/Setup reports and independent inspection of a fresh patched ISO.

## Unreleased - faster image preparation and clearer progress

- Reuse compressed resources when exporting an edition from an ordinary WIM;
  convert solid ESDs to a standard servicing WIM. Keep maximum compression for
  the final export. Preserve sources and refuse unfinished destination files.
- Prefer pinned wimlib 1.14.5 for parallel solid LZMS final compression, with
  CPU/memory autodetection, configurable effort/threads and a DISM fallback.
- Patch Setup's small registry hive files without mounting the entire boot WIM
  when no drivers need injection; preserve file security metadata.
- Rename compression choices to `maximum`, `balanced`, `fast`, `none`;
  retain legacy command/profile compatibility and required DISM API names.
- Read ISO editions from the WIM/ESD XML resource through bundled DiscUtils
  0.16.13. No mount, cache, first-use download or DISM scan. Filename release
  hints appear immediately; actual image metadata determines builds/indexes.
- Load editions asynchronously, cancel/dispose the previous reader before
  another starts, and invalidate edition selections when the source changes.
- Add overall and step progress bars, native percentages, item counts,
  indeterminate loading bars, elapsed time and explicitly estimated ETAs.
- Update checkout/upload-artifact to 7.0.1. Pin PSScriptAnalyzer 1.25.0 and
  download only into the project if missing. Development checks skip build
  media instead of traversing the entire workspace.
- Add real WIM/ESD exports, malformed ISO/XML and GUI timing regression tests.

## Unreleased - Windows 11 build 26300 compatibility

- Verify the mounted SOFTWARE hive can load and unload before app servicing.
  Report the underlying registry error instead of DISM's generic parameter
  error; refuse a conflicting offline hive from another build.
- Identify build 26300 as Windows 11 26H2 and build 28000 as 26H1;
  unknown future builds are labelled explicitly instead of silently using 25H2.
- Stream Oscdimg stdout and stderr as ordinary text in both builders and the
  GUI. Progress on stderr no longer produces false `ERROR:` lines. Nonzero
  exit codes and missing or undersized ISOs still fail the build.
- Defer access-denied offline DWORD writes until hive unload, then use the
  Windows offline registry library to edit the image file and verify readback.
  Save atomically; leave registry permissions and host settings unchanged.
- Keep the protected Windows Security app on build 26100 and newer even when
  the Defender-off preset is selected; log the retention explicitly. Defender
  registry settings remain separate and are not a guarantee against tamper protection.
- Add regression coverage for native stderr, exit codes, timeouts, version
  detection and Windows Security removal planning.

## Unreleased - registry stall diagnostics

- Bound registry writes and deletions to 30 seconds. A blocked `reg.exe` now
  fails with the command/key instead of leaving the GUI waiting indefinitely.
- Close stdin for bounded commands and drain stdout/stderr concurrently;
  preserve native error text for failed writes.
- Log each scheduled task before removing its registry entries.
- Add regression tests for timeout, stdin EOF, output capture and exit codes.
- Root cause of the stall: offline hives store the task `Id` with its
  terminating NUL. The NUL cut the `reg.exe delete` command line short, so
  `/f` was lost and `reg.exe` waited on its Yes/No prompt. The NUL is now
  stripped, and process arguments containing a NUL are refused.
- `Plain`/`Boot`/`Logon`/`Maintenance`/`Tree` TaskCache keys have their own
  protected ACLs; ownership is now taken per key before deleting, so telemetry
  tasks are fully unregistered (previously only `Tasks\{GUID}` was removed).
- `Remove-RegistryValue` warns on "Access is denied" instead of treating every
  exit code 1 as "key not found".
- Fix "op_Addition" crash after patching boot.wim: the hive-unload messages
  leaked into `Invoke-BootImageStage`'s return value.
- Fix "Cannot convert System.Object[] to System.Int64" after ISO creation:
  oscdimg's output leaked into `New-Tiny11Iso`'s return value.
- **PowerShell 7 support** (tested on the Microsoft Store PowerShell 7.7 preview).
  Natively loaded, every DISM cmdlet that services a mounted image failed with
  "Class not registered" and left a `DismHost` holding the image lock.
  `Initialize-DismModule` now loads DISM through the Windows PowerShell
  compatibility session under PowerShell 7 (5.1 is unchanged). Elevation
  relaunches and the GUI's builder process use the current edition
  (`Get-PowerShellExecutable`); module manifests declare `Desktop` and `Core`.

All notable changes to Tiny11 Builder - Ultimate Edition. The project is a fork of
[ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder), whose full history is
kept on `main`, and it incorporates improvements from 15 community forks. Versions are
`year.month[.n]`. The format follows [Keep a Changelog](https://keepachangelog.com/).

Read the older entries as a record of their time. Several features listed in the
"Initial Build" entry were later found not to work, and were fixed in Round 4 (2026.09).

---

## [2026.09.2] - 2026-09-23 - Round 6: documentation and screenshots

### Changed
- **README rewritten** for the current project:
  - highlights, quick start and requirements;
  - a GUI guide with a screenshot of every tab and of a finished build;
  - Standard vs Core, presets;
  - the complete command-line reference, grouped by purpose;
  - the build pipeline, after-install notes, customising, troubleshooting;
  - project layout, development workflow, history and credits.
- **CONTRIBUTING rewritten**: ground rules (host safety, PS 5.1 pitfalls), where each kind of
  change goes, the checks to run, how to test the GUI without a build, and history etiquette.
- All GUI screenshots regenerated (`docs/gui-*.png`), plus the new `gui-build-done.png`.

### Added
- `scripts/update-screenshots.ps1` re-renders every screenshot reproducibly.
  - It uses window-only rendering (`DrawToBitmap`), never a screen grab, so nothing else on the
    desktop can end up in an image.
  - The log panel, which `DrawToBitmap` cannot paint, is drawn onto a temporary overlay.
  - The finished-build image comes from the real window, run with the fake builder.
- The fake-builder fixture can print a realistic log (`T11_FAKE_DOCS=1`).

### Fixed
- `Start-GuiBuild` now resolves relative builder and log paths. The launcher runs in the
  builder's folder, so a relative `-BuilderOverride` failed before.
- The GUI now reports "the builder finished but no ISO was found" instead of "dry run
  finished" when a real build exits 0 without an ISO.
- The build log keeps its dark background (a read-only RichTextBox resets `BackColor`).

---

## [2026.09.1] - 2026-09-23 - Round 5: the GUI becomes the main builder

### Added
- **Tabbed builder window with every option** (`lib/tiny11gui.psm1`), in seven tabs:
  - **Source**: editions with build, architecture, language and size.
  - **Preset & features**: every preset flag as a checkbox; load/save
    preset files; changed flags become a custom preset automatically.
  - **Apps**: the grouped removal list with checkboxes, your own prefixes,
    import/export, optional apps, keep everything. Entries a preset flag
    overrides (Xbox with "Keep Xbox") are greyed.
  - **Tweaks**: all catalog groups; uncheck to skip, check a greyed group to
    enable its flag; per-group value viewer.
  - **Setup & account**:
    - local admin with password confirmation, or account created in OOBE;
    - locale picker, time zone list, computer name;
    - zero-touch and custom answer file;
    - preview or save the generated `autounattend.xml`.
  - **Extras**: .NET 3.5, driver folder with `.inf` count, browser, payload
    file list, low-RAM, driver updates, Defender exclusion.
  - **Build**: plan, validation, the copyable equivalent command line.
- **Builds run inside the window**:
  - A hidden, non-interactive `powershell.exe` runs the builder with `-Yes`.
  - Its output is streamed into a colour-coded log with stage progress and
    elapsed time.
  - **Cancel** kills the process tree, then discards the mounted image and
    unloads the hives.
  - Arguments (including the password) travel through a CLIXML file that
    the launcher deletes immediately.
- **Validation before building**: missing ISO or edition, password mismatch,
  invalid user/computer name or locale, missing folders, not enough space on
  the work drive. Warnings cover zero-touch, Core, no antivirus, WebView2 and
  Mark-of-the-Web.
- **Profiles**: save/load the whole configuration; the last session is
  remembered in `gui-settings.json` (never the password).
- `ConvertTo-PresetJson` / `Get-PresetFlagSection` in the utils module (the
  inverse of `ConvertFrom-PresetJson`).
- **Tests**:
  - ~55 GUI checks: state -> builder arguments, validation, tweak toggling,
    progress parsing, settings round-trip, log tailing;
  - the launcher run against `scripts/fixtures/fake-builder.ps1` (exit code
    and output capture, args file deleted);
  - the whole window driven end to end with `-AutoRun` and the fake builder;
  - every tab rendered.
- The generator also maintains `lib/tiny11gui.psd1`; per-tab screenshots are in `docs/`.

### Fixed (found by the new tests and renders)
- The progress-stage table was flattened by PowerShell array unrolling, so the
  progress bar received character codes.
- WinForms raises `ItemChecked` for every ListView item when the handle is
  created, which silently skipped tweak groups. The handler is now idempotent.
- Controls anchored to the bottom grew past their tab page; ampersands in group
  titles were swallowed as mnemonics; truncated labels.

---

## [2026.09] - 2026-09-23 - Round 4: correctness audit, shared build library, catalog-driven tweaks

A full audit of the builders against all 15 reference forks (all re-pulled; the
upstream ntdevlabs repository was added to `repos/`) found that several
headline features never ran and that some defaults would break a real build.
Both builders were rebuilt on a tested shared library.

### Fixed - builds that failed or silently did nothing
- **ESD-only ISOs always failed**: `install.esd` was deleted before it was
  converted. The builders now export only the chosen edition, straight from the
  source `install.wim`/`install.esd`, which is also faster and needs less space.
- **Mount failed on a first run**: `Initialize-ScratchWorkspace` never created
  the mount folder when it did not exist.
- **`Apply-ExtendedTweaks` aborted every build**: it wrote to `HKLM\z\...` and
  `CurrentControlSet`, which do not exist offline; mouse/keyboard, firewall,
  driver-blocklist and power-plan values used wrong keys or formats. It was
  replaced by the tweak catalog (below).
- **`-User`, `-Password`, `-TimeZone`, `-ZeroTouch` did nothing**: the static
  answer file was always copied. The answer file is now generated per build.
- **The static `autounattend.xml` would stop Windows Setup**: the local account
  was in the `offlineServicing` pass, `<Power>` is not a Shell-Setup setting,
  `<ComputerName>` and `<DisableAutoDaylightTime>` sat in `oobeSystem`, and there
  was an invented `c:offlineClient` element. `New-UnattendXml` also used a wrong
  `wcm` namespace.
- **`-Keep` / `-Remove` had no effect**: they were resolved after apps had
  already been removed, and `removePackage.txt` removed Terminal and Notepad
  anyway.
- **24H2 detection never worked**: the version was queried from `HKLM\zSOFTWARE`
  before the hive was loaded. It is now read from the WIM metadata.
- **TaskCache GUIDs were hard-coded**: those GUIDs differ per image, so they
  never matched. Tasks are now resolved by path through `TaskCache\Tree`.
- **Language packages and capabilities never matched**: they used 2-letter
  codes and prefixes as full identities, and targeted the `Basic` language
  features. They are now matched against what is installed, and
  spell-check/typing are kept.
- **`recovery` compression was never used**: it silently became `max`.
  `recovery` now produces `install.esd`.
- **PS 5.1 hazard**: `& tool 2>$null` throws under `$ErrorActionPreference='Stop'`
  as soon as the tool writes to stderr. All quiet native calls now go through
  `Invoke-Native`.
- **Wrong registry keys**: TIPC, InputPersonalization and Personalization
  settings; the Notepad AI policy (`Policies\WindowsNotepad`); per-user search
  highlights; and the real `UScheduler_Oobe` trigger keys for Outlook and Dev Home.
- **Core**: one failing `/Remove-Package` aborted the build; the WinSxS swap
  could fail silently, leaving both copies in the image; `$input` was used as a
  variable; Defender and Windows Update both set `SettingsPageVisibility`, so
  the second overwrote the first.
- **Regular build**: no longer deletes Edge WebView from WinSxS, which damaged
  serviceability.
- **Misc**: `removePackage.txt` had typos (`Microsoft.Windows.CrossDevice`,
  `...Edge.Stable_8wekyb3d8bbwe!App`); GUI crashed on PS 5.1 (`Join-Path` with
  two child paths) and assumed contiguous edition indexes; build summary
  dropped hours; arguments with spaces/quotes/empty values broke the UAC
  relaunch; `takeown /D Y` and `Administrators` only worked on English Windows.

### Added
- **`data/tweaks.psd1`**: one catalog of every registry change, in 28 groups
  switched by preset flags. It is validated by tests, documented automatically in
  `docs/TWEAKS.md`, and `-SkipTweak` can leave groups out. New groups:
  - 24H2/25H2 AI: Recall, Click to Do, Settings agent, generative-AI app
    access, Paint/Notepad/Edge AI.
  - Widgets/News, Bing search, "finish setting up" nags, the personal-data-export
    OOBE page, the first-logon animation.
  - GameDVR (no more `ms-gamingoverlay` pop-ups), Edge Active Setup/updater
    services, OneDrive Run keys, Defender cloud reporting.
  - A valid telemetry firewall rule and a real Ultimate Performance plan
    (applied at first boot).
- **Deprovisioning**: removed apps are also marked deprovisioned, so feature
  updates do not reinstall them.
- **Answer-file generator**:
  - no account at all with `-InteractiveOobe`;
  - `-Locale` (or ask in OOBE, instead of forcing en-US keyboards);
  - `-ComputerName`, passwords stored Base64 (not plain text), and
    `net accounts /maxpwage:UNLIMITED`;
  - BypassNRO in the specialize pass, `DynamicUpdate` off;
  - answer files deleted after the first sign-in.
- **New options**:
  - `-Edition Pro`, `-EnableNetFx3` (Standard too), `-DriverPath` (install +
    Setup images), `-Browser Firefox|Chrome` (at first sign-in, waits for the
    network);
  - `-Payload` (whole `payload\packages` folder), `-NoPrompt` (efisys_noprompt),
    `-OutputIso`, `-PackageList`, `-UnattendFile`;
  - `-DefenderExclusion` (opt-in, reverted), `-Compress max`, custom
    `-Preset file.json`.
- **Build artifacts**: `<iso>.json` manifest (source, options, flags, removed
  apps, tweak groups) and `<iso>.sha256`. ISO volume label such as
  `TINY11_25H2_AMD64`. ARM64 ISOs are UEFI-only (`-bootdata:1`).
- **Robustness**:
  - retrying hive unload and dismount;
  - recovery from stale hives and mount points before a build;
  - mount sanity check, ISO minimum-size check, retrying install-image
    replacement;
  - `oscdimg` located through the ADK registry key; the downloaded copy is
    pinned by SHA-256.
- **Safety**: the registry helpers refuse any path outside the offline `HKLM\z*`
  hives, and refuse to write unless such a hive is actually loaded.
- **GUI**: one window with source, edition, Standard/Core, preset, compression,
  browser, work drive, output path, account, time zone, locale, options and
  optional apps. `-PreviewPath` renders it headless, for CI and docs.
- **Protected apps**: winget, frameworks and codecs are never removed; the Store
  and the Windows Security app go only with Minimal-VM/Core.
- **Tooling**:
  - ~1700-check test suite: data validation, answer-file allow-list, mocked
    build stages, static lint;
  - `parse-check.ps1` now resolves every command;
  - `update-generated.ps1` produces `docs/TWEAKS.md`, `docs/APPS.md`, the
    reference answer files and the module manifest;
  - linter over all files;
  - CI on Windows PowerShell 5.1; `.gitattributes` (CRLF).

### Changed
- Both builders share the same stages (`Invoke-AppRemovalStage`,
  `Invoke-RegistryStage`, `Export-FinalInstallImage`, `Invoke-BootImageStage`,
  `New-Tiny11Iso`). Core's default preset is `Minimal-VM`.
- Presets:
  - UTC hardware clock is opt-in everywhere;
  - Mark-of-the-Web is kept except in Minimal-VM;
  - PrivacyPlus keeps Defender on but disables cloud reporting;
  - Gaming keeps the Xbox stack;
  - WebView2 is kept except in Minimal-VM/Core.
- App matching uses name prefixes instead of substrings. Optional utilities
  moved out of `removePackage.txt`.
- The mid-build "disable driver updates?" prompt became `-DisableDriverUpdates`.
  Core asks its questions before the build starts.
- ISO mount state is passed as an object, not through `$Global:` variables.
- Logs go to `logs\`.

### Removed
- `payload/SetupComplete.cmd` (generated per build now), `docs/lista_de_apps.md`
  and `docs/lista_simples_apps.txt` (replaced by the generated `docs/APPS.md`),
  the hard-coded TaskCache GUID lists, and the unused helpers
  `Resolve-InstallImageIndex`, `Resolve-OscdimgSource`,
  `Test-ImageIndexAvailable`, `Test-ScratchDiskSpace` and `Unload-LoadedRegistries`.
- `tiny11LegacyProfile.ps1` is now a shim over the `LowRam` catalog group.

### Known limitations
- No end-to-end ISO build was run for this round: it needs an elevated session
  and a Windows ISO. Everything below that level is covered by the test suite.

---

## [26.09.2026] - Ultimate Edition Initial Build

### Overview
Complete rearchitecture of the tiny11builder ecosystem, combining the best
improvements from 14+ reference forks while fixing bugs inherited from the
NairoDorian base. Built using a research-then-build workflow: all reference
forks were cloned into `repos/` and studied (reforged + revamped prioritized).

### Added

#### Modular Architecture
- **`lib/tiny11utils.psm1`** — 45 utility functions extracted into a shared module
  (inspired by the revamped fork's `lib/tiny11utils.psm1`)
- **`lib/tiny11gui.psm1`** — Windows Forms GUI module (ported from the reforged
  fork's `tiny11gui.psm1`)
- **`lib/AdjPriv.cs`** — C# privilege helper reference for TrustedInstaller
  ownership escalation (from reforged/rearmed forks)
- **`lib/tiny11utils.psd1`**, **`lib/tiny11gui.psd1`** — Module manifests for
  proper PowerShell module integration

#### Builder Script Enhancements (`tiny11maker.ps1`)
- **Presets system** (`-Preset` parameter) with 4 profiles: Default, Gaming,
  Minimal-VM, PrivacyPlus (from namnguyen97x/tiny-auto-builder)
- **Interactive package selector** (`-Custom`) via `Show-PackageSelector` with
  console TUI (from vinisebold/revamped, zPoche v2)
- **Dry-run mode** (`-DryRun`) to preview without modifying the image
- **Configurable compression** (`-Compress recovery|fast|none`)
- **Fast mode** (`-Fast`) to skip DISM component cleanup
- **Zero-touch install** (`-ZeroTouch`) with dynamic autounattend.xml generation
- **Low-RAM profile** (`-LowRam`) for 1 GB-class machines
- **Keep/Remove flags** (`-KeepApps`) for custom package overrides
- **Auto ISO mounting** — accepts either a drive letter or an `.iso` file path
  (auto-mounts with `Mount-DiskImage`)
- **Auto-download oscdimg.exe** if Windows ADK is not installed
- **Auto-download autounattend.xml** if missing (from reforged)
- **Stale-mount cleanup** — cleans up previous scratch directories before building
- **ISO auto-ejection** — ejects the source ISO after build when auto-mounted
- **Robocopy** for efficient ISO file copying
- **Build summary** with elapsed time, ISO size, apps removed, and warning count
- **NTFS filesystem verification** for the scratch disk
- **Scratch disk space validation** (≥ 1.5× image size)

#### Hardened TaskCache Cleanup (from revamped)
- **ACL takeover** of the `ScheduleTaskCache` registry key before deletion
  (takes ownership from TrustedInstaller)
- **Version-gated TaskCache GUIDs** — different GUID sets for 24H2 builds vs
  older builds (per PR #289 from the revamped fork)
- **Safe task file deletion** — removes both task definition files AND
  TaskCache registry entries

#### Privilege Escalation
- **C#-backed `Enable-Privilege`** via inline Add-Type code (AdjPriv.cs) for
  `SeTakeOwnershipPrivilege`, `SeSecurityPrivilege`, etc.
  (from revamped/reforged)

#### Emergency Cleanup Trap
- **`trap` block** guarantees registry hives are unloaded and mount points
  are cleaned up on any error (from revamped/zPoche v2)
- **`Invoke-SafeDismountImage`** — safe wrapper around `Dismount-WindowsImage`
- **`Invoke-SafeOfflineRegistryUnload`** — safe wrapper around `reg.exe Unload`
- **`Invoke-ScriptCleanupOnFailure`** — guaranteed cleanup of scratch dirs
- **Tracked registry hives** — `Invoke-RegLoad`/`Invoke-RegUnload` track
  loaded hives for safe cleanup

#### GUI Mode (`tiny11gui.ps1`)
- **Windows Forms wizard** with two-stage flow: mount mode → edition selection
  (from reforged)
- **Splash screen** with application icon and version info
- **Auto-detection** of mounted drives containing Windows setup images
- **Auto-elevation** — self-relaunches as admin if not elevated
- **Execution policy fix** — prompts to set Bypass if restricted

#### Core Builder (`tiny11Coremaker.ps1`)
- **Bug fixes** from the NairoDorian base:
  - Fixed `$ScratchDisk` variable error in registry loading section
  - Fixed `"$mainOSDrive\scratchdir"` WinSxS rename path bug
  - Fixed `>null` → `> $null` output redirection
  - Fixed hardcoded `C:\scratchdir` path
- **Modular function integration** — uses `Set-RegistryValue`,
  `Remove-RegistryValue` from the utils module
- **Architecture-aware** WinSxS preservation list
- **WinRE removal**
- **Post-OOBE Windows Update blocking** via `SetupComplete.cmd` RunOnce entries
- **Windows Defender disabling**
- **ESD export** with recovery compression

#### Low-RAM Profile (`tiny11LegacyProfile.ps1`)
- 1 GB-class low-RAM profile with memory-saving tweaks
  (ported from bluecloud122/tiny11builder)

#### Enhanced `autounattend.xml`
- **RunSynchronous TPM/SecureBoot/RAM bypass** (from user129233) — critical for
  hardware compatibility during Windows Setup's windowsPE phase
- **Compact install** — reduced ISO size (from zPoche v2)
- **Local admin account** creation with AutoLogon
- **OOBE bypass** — skips EULA, network, account, privacy screens
- **FirstLogonCommands** — disables AutoLogon after first login, applies
  network bypass registry tweak
- **Multi-architecture** — amd64 + arm64 variants
- **Dynamic autounattend.xml generation** via `New-UnattendXml` function

#### Package Management
- **Externalized `removePackage.txt`** — human-readable, comment-supported
  (from revamped/zPoche v2)
- **Comprehensive package list** combining entries from DFwindows11_builder,
  zPoche v2, revamped, and 24H2-compatible IDs from keepitupkitty/SamHimmy
- **AI/Copilot packages** — removes Copilot, Recall, DevHome, WindowsAI (24H2+)
- **`docs/lista_de_apps.md`** — human-readable package reference
- **`docs/lista_simples_apps.txt`** — machine-readable removal list

#### Payload System
- **`payload/SetupComplete.cmd`** — runs after first login (from MOPELotus)
- **`payload/` subdirectories** — Fonts, DirectX, VCRedist, DotNet, PowerShell,
  Store, Wallpapers, XboxInstaller
- **`payload/README.md`** — documentation for payload structure

#### Browser Management
- **`Browsers/` directory** with browser installer scripts and documentation
  (from DFwindows11_builder)

#### CI/CD
- **`.github/workflows/ci.yml`** — validates PowerShell syntax, XML, and JSON
  (from YmlyZA)
- **`scripts/linter.ps1`** — PSScriptAnalyzer with high-signal rules only
- **`scripts/parse-check.ps1`** — static parse + function resolution check
- **`scripts/test-core-helpers.ps1`** — unit tests for utility functions
- **`scripts/test-core-helpers.ps1`** — AST-based tests for pure functions

#### Documentation
- **`README.md`** — comprehensive documentation with feature matrix, usage,
  parameters, presets, and per-fork attribution
- **`CHANGELOG.md`** — this file
- **`CONTRIBUTING.md`** — contributor guide

### Fixed
- **`$ScratchDisk` variable** — base script referenced undefined `$ScratchDisk`
  in the registry loading section
- **Syntax error** — `"Prevent installation of New Outlook":` (string + colon)
  instead of `Write-Output`
- **`>null`** — incorrect output redirection instead of `> $null`
- **WinSxS rename** — `-NewName` used full path instead of just the folder name
- **Hardcoded paths** — `C:\scratchdir` replaced with variables
- **`offlineClient` namespace** — added `xmlns:c` declaration for the
  `c:offlineClient` element in autounattend.xml
- **Autounattend.xml naming** — fixed inconsistency between `autounattend.xml` and
   `autounattend.xml` filenames

#### Post-Build Bug Fixes
- **`Apply-ExtendedTweaks -Preset`** — the function had no `-Preset` parameter;
  the maker and coremaker both called it with `-Preset $preset`, which would
  throw a parameter binding error at runtime. Added a `[hashtable]$Preset`
  parameter with backward-compatible key-name aliasing (DisableThirdParty→
  DisableThirdPartyTelemetry, EnableUltimatePerf→EnableUltimatePerformance).
- **`Show-PackageSelector -DefaultAll`** — the `-DefaultAll` parameter did not
  exist on the function and would throw a binding error. Removed the invalid
  argument (the function already defaults all items to selected).
- **`$SplashPictureBox` scope** — `tiny11gui.ps1` referenced this variable
  outside the function that created it (`$null`). Changed to a `Global`-scoped
  variable set inside `Invoke-MainForm`.
- **`autounattend.xml` cleanup** — both maker and coremaker unconditionally
  deleted the source `autounattend.xml` on cleanup. The maker now only removes
  it if it was auto-downloaded during this run; the coremaker never deletes it.
- **`$PSScriptRoot` in module** — `Resolve-AutounattendFile`, `Test-Prerequisites`,
  `Initialize-Oscdimg`, and the cleanup function used `$PSScriptRoot` which
  resolves to `lib/` when called from the module. Added `$repoRoot` (parent of
  `lib/`) and updated all data-file path references.
- **Module manifest `FunctionsToExport`** — 5 functions (`Get-MaxParallelJobs`,
  `Get-OptionalCapabilitiesToRemove`, `Get-AdditionalWindowsPackagesToRemove`,
  `Remove-BloatwareFiles`, `Apply-ExtendedTweaks`) were missing from the
  manifest, preventing proper module import via manifest.
- **`KeepApps` parameter semantics** — the parameter was `[string[]]` that added
  packages to the removal list, contradicting its name and the README ("skip
  ALL Appx package removal"). Changed to `[switch]` that skips all Appx removal.
  Updated help text, usage, and UAC-relaunch forwarding in both scripts.
- **Preset key mismatches** — `Resolve-BuildPreset` used `EnableUltimatePerf`
  and `DisableThirdParty` while `Apply-ExtendedTweaks` expected
  `EnableUltimatePerformance` and `DisableThirdPartyTelemetry`. `EnableDriverBlocklist`
  was missing from all presets entirely. Standardized all key names and added
  the missing field.
- **JSON preset loading** — presets were hardcoded as hashtables despite JSON
  files existing in `presets/`. The hardcoded defaults drifted from the JSON
  (e.g., Gaming had `BlockFirewallTelemetry = $false` but JSON had `true`).
  Rewrote `Resolve-BuildPreset` to load from JSON with hardcoded fallback.
- **Duplicate `Microsoft.YourPhone`** — appeared twice in `removePackage.txt`.
- **Coremaker UAC parameter forwarding** — the admin-relaunch block was missing
  `-Preset` (and the maker was missing `-Preset`, `-Keep`, `-Remove`, `-TimeZone`).
- **Coremaker build summary** — `Format-BuildSummary` was called with hardcoded
  `AppsRemoved=0` / `AppsTotal=0`. Added proper tracking of removed/total app
   counts and per-package error handling with warning increments.
- **GUI state variable scope** — `tiny11gui.psm1` variables (`$WINDOW_CLOSED`,
  `$MODE_SELECT`, `$SCREEN_STAGE`, `$AppVersion`) were at `Scope Script` (with
  `AllScope` removed) but `tiny11gui.ps1` (the parent scope) reads them without
  `$Script:` prefix. `AllScope` at Script scope does not propagate to the parent
  importing scope, so the GUI could never detect form closure, mode selection,
  or reset the screen stage. Changed all four to `Scope Global` and updated all
  `$Script:` references in module functions to `$Global:`. `$SplashPictureBox` was
  already Global and serves as the correct pattern.
- **Coremaker architecture validation** — `tiny11Coremaker.ps1` did not validate the
  detected `$architecture` (no null check after the detection loop). If architecture
  detection failed, the script would silently fall through to amd64 defaults,
  potentially producing a broken arm64 ISO. Added the same guard that
  `tiny11maker.ps1` already had.
- **`dism /English` quoting** — `tiny11maker.ps1` called `dism /English /Get-Intl` with
  unquoted arguments while `tiny11Coremaker.ps1` used `'/English'`. Standardized to
  `& 'dism' '/English' '/Get-Intl'` in the maker for cross-script consistency.

---

## [Base] NairoDorian/tiny11builder_2026

The upstream base is the ntdevlabs tiny11builder, which provides:
- `tiny11maker.ps1` — regular builder (serviceable image)
- `tiny11Coremaker.ps1` — core builder (ultra-trimmed for VMs)
- `autounattend.xml` — OOBE bypass answer file
- Release date: 09-07-25
