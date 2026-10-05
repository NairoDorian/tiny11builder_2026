# Tiny11 build bugs: evidence, upstream reports and verification

Investigation recorded 2026-10-04 for Windows 11 build 26300.9457 (26H2); reconciled with application `2ae045d` on **2026-10-05**. This is a living investigation report. A passing export, a valid ISO filesystem and a successful Windows installation are different checks. Evidence below is labeled accordingly.

## State of this investigation — 2026-10-05

The two requested fresh none/maximum comparison runs **completed** at `7aa45d5`; no benchmark remains pending. Later #623/#628/#622/#604 and reference safeguards passed regression/real small-fixture checks, not a fresh complete latest-code ISO or VM installation. See [current handoff](WORKING_NOTES.md), [implementation guide](PROJECT_GUIDE.md) and [verification matrix](VERIFICATION.md).

| Issue / observation | Implemented response | Remaining evidence limit |
|---|---|---|
| Hive load: filename/extension error | Early disposable probe, real mounted SOFTWARE guard; passing manual CIM launch demonstrated | Root Windows launch-context mechanism unknown; normal GUI is not automatically rerouted or proved repaired |
| Three denied Widgets DWORDs | Owned-hive deferred file-only write/readback after unload, file security preserved | ACL cause not established; saved values proved, policy runtime not VM-tested |
| TaskCache NUL / waiting native command | Strip terminator, reject NUL arguments, close stdin, registry timeout | Do not bypass wrapper/guards with new raw calls |
| Native stderr / mixed return values | Ordinary concurrent progress streaming and clean numeric result paths | Nonzero exit/output absence still fails; logs alone cannot prove installability |
| Protected SecHealthUI on new media | Retain on 26100+, separate offline Defender choices | Disabling Defender under tamper protection is not guaranteed |
| Mount deletion/conflict | Separate driver boot mount, guarded/retried scratch cleanup, preserve files on unsafe state | Legacy global recovery/shared aliases still require one writer; Core WinSxS fallback is a separate code path |
| Missing edition/language XML | Missing-only source-derived wimlib repair with integrity/readback; conflicts fail | Does not establish all Setup/activation/hardware behavior |
| Late Oscdimg readiness / corrupt cache | Early prepared path, verified atomic download/retention | First download can still fail early; not a compression speedup |
| SYSTEM Default differs / source-work overlap | Resolve selected next-boot control set; refuse overlapping copy/deletion trees | Mock/path tests passed; no complete Default=2 Windows installation |

Historical raw logs/checkpoints/media mentioned below were deleted/are absent at the recorded output path. The authoritative retained evidence is compact JSON under `verification/2026-10-04` and `2026-10-05`. Current code, historical successful runs and unresolved causal questions are deliberately separated.

## Current conclusion

The most recent blocking error was an offline registry hive failing to load with `ERROR: The filename or extension is too long.` Shortening the file path to 33 characters did **not** fix it. Loading the same disposable offline SOFTWARE hive from a process created through Windows WMI/CIM succeeded, and that process subsequently launched a fresh build that passed the original failing step. The launch context is therefore involved. The underlying Windows mechanism has not been identified; it is not proven to be a path-length limit, a corrupt source hive, a job-object restriction, an ACL problem or a Windows 26H2 incompatibility.

The user accepts an approximately 5-6 GB final ISO if the intended patches and installation remain correct. There is no target that requires deleting additional Windows features solely to reach a historical 2-3 GB figure. No VM installation test has been performed yet.

## Scope and host boundary

The input is `C:\Users\Z\Downloads\PROJECTS\ISOs\Windows11_Client_x64_en-us_26300_9457.iso`, 9,047,330,816 bytes. Measurements select the original ISO's Pro image, index 6, with the saved GUI preset and utility selections. They do not start from a previously patched image.

The running Windows installation is read-only. Do not edit its system files, live registry settings, Defender configuration, scheduled tasks or CPU priority. The user explicitly permits editing project files, ISO outputs and offline image work files. Normal temporary attachments of those offline images/hives are permitted and must be released. The user explicitly authorized `C:\.temp` for short work/output paths. These permissions do not extend to changing live Windows configuration.

Only one servicing/build attempt may run at a time. Before a replacement attempt, confirm the previous process tree has exited and its images/hives have been released. Do not launch overlapping writers, retry against a live mount, or treat rebooting as normal cleanup.

## 1. Offline hive-loading failure, reproduced step by step

### What failed

The first fresh maximum-compression attempt exported the selected edition and mounted it. `Assert-MountedImage` then tried to load that image's SOFTWARE file at `HKLM\zSOFTWARE`. The native `reg.exe load` returned exit 1 with the filename/extension error. The builder stopped before app removal and registry patching. No final ISO was created.

The original raw log was `logs/manual-verification/fresh-20261004-181134-c4ac4ab7/build.log` and was deleted during cleanup; the final [status](verification/2026-10-04/failed-build-status.json) records exit 1 and zero output bytes. Selected-edition export took 33.2 seconds; mounting took 186.5 seconds. The failed attempt took 553.7 seconds including discarding the mount and deleting work files. That total is a failed-attempt cost, not a completed-build benchmark.

The original error text alone does not establish that the file path actually exceeded a Windows limit. `reg.exe` exposes a command exit code and message here; we did not capture an independent native `RegLoadKeyW` return value or stack trace. Microsoft documents the low-level API and its backup/restore privilege requirements in [RegLoadKeyW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regloadkeyw).

### Controlled tests

After the failed process exited, diagnostics confirmed no earlier DISM/wimlib/Oscdimg writer or mounted image remained. A preserved work folder and scratch folder at the root of C: were moved beneath `C:\.temp\preserved-tiny11`. The original ISO was preserved. The probe copied an existing **offline** SOFTWARE hive into a fresh disposable folder; it never copied or edited the running Windows SOFTWARE file.

The same helper, source hive, administrator identity and 33-character file path structure were used for the following launches:

| Launch method | Process | Result | Evidence |
|---|---:|---|---|
| Direct elevated PowerShell launch | 21356 | Load exit 1, filename/extension error | [short-path-direct.json](verification/2026-10-04/hive-load-direct.json) |
| Shell.Application elevated launch | 28540 | Same load exit 1 | [short-path-shell.json](verification/2026-10-04/hive-load-shell.json) |
| Windows `Win32_Process.Create` through CIM | 28344 | Load exit 0; unload exit 0 | [short-path-wmi.json](verification/2026-10-04/hive-load-wmi.json) |

All three reported `InJob = true` and `RestrictedToken = false`. Consequently, those two boolean observations cannot explain the difference. Administrator elevation alone did not resolve it. The passing method did not alter CPU priority, security settings, privileges persistently, scheduled tasks or live Windows registry values.

An initial CIM creation request used an unsupported combination of startup creation flags and returned 21 (invalid parameter) before creating any child. Removing that flag and using `ShowWindow = 0` produced a successful process creation. This was a launcher-argument mistake, separate from the hive-loading failure. The API contract is documented in Microsoft's [Win32_Process.Create](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/create-method-in-class-win32-process) and [Win32_ProcessStartup](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processstartup).

### What this proves and what it does not

A usable offline hive loaded successfully on the same host without a reboot. This rules out the claim that the host cannot load any offline hive at all. Failure at a 33-character path rules out explaining these particular attempts solely by a long filename. The successful fresh build passed the image SOFTWARE check, app removal and initial registry processing under the Windows-managed launch.

The exact process-context difference remains unresolved. It would require additional native tracing to identify which inherited state changes the result. It is inappropriate to blame Windows 26H2, the sandbox, antivirus, a job object, or registry permissions as an established root cause based on the current evidence.

### Code and workflow changes

- Both builders accept an isolated `-WorkDirectory`. A new or empty local NTFS folder prevents accidental reuse of an earlier patched image and permits short paths under the authorized `C:\.temp` folder.
- `Assert-MountedImage` retains its real SOFTWARE load/unload test. File existence alone is insufficient evidence that servicing can proceed.
- `Test-OfflineHiveLoading` now creates a tiny new disposable hive with Windows Offreg, tests a unique temporary alias, unloads it, and removes only its own probe folder. It runs after dry-run validation and before media copying/mounting. A failure therefore stops before the expensive image work, preserves the underlying error and points to this report. It is a diagnostic guard, not a claim to repair the unexplained Windows condition.
- The manual measurement launcher uses the passing CIM method. The application does not silently change the machine's policy or route every build through WMI.
- Scratch deletion refuses a still-registered mount and validates its absolute target below the selected build root. There is no cross-shell deletion fallback.
- Process priority is inherited. The user manages it.

The fast measurement already running when the preflight was added loaded its module before this edit, so that run tests the passing launch and real image probe, not the newly added early preflight. The subsequent none/maximum comparison runs exercised the then-current guard and completed; later application edits still need their own full-run validation.

## 2. Earlier denied registry writes were a separate failure

The original supplied log had three denied Widgets/feeds DWORD writes: `AllowNewsAndInterests`, `EnableFeeds` and `TaskbarDa`. A disposable source-hive ACL experiment did not resolve them, and the observed key already permitted administrator access. Do not describe the cause as a proven ACL failure or use a registry ownership takeover as the fix.

The targeted implementation records only denied DWORD writes for the tracked offline hive. After its normal unload flushes and releases the file, Windows Offreg opens the file in memory, applies those relative subkey/value entries, reads them back, saves a new hive and atomically replaces the original while preserving file security. Other registry errors still fail. Host hive files and paths outside the allowed offline aliases are rejected.

The previously completed maximum-compressed ESD was independently extracted. All three values were confirmed as DWORD zero in the saved SOFTWARE/default-user files. This checks the resulting image data, beyond merely seeing a successful command in a log. The original raw evidence under `logs/manual-verification` was deleted; compact saved-image/checkpoint results remain under `verification/2026-10-04`. The relevant code is in [OfflineRegistry.cs](../lib/OfflineRegistry.cs) and [tiny11utils.psm1](../lib/tiny11utils.psm1).

### Other original-log failures and misleading output

`Microsoft.SecHealthUI` removal failed on the newer Windows servicing model. On build 26100 and newer, removal planning now retains the protected Windows Security app and logs that choice, even when Defender-related offline preset settings are requested. Avoiding the unsupported removal is deliberate compatibility handling. The corresponding offline settings are still applied, but retaining the app is not a promise that Windows tamper protection can be overridden. The fresh runs removed all 29 **planned** apps; that count does not imply this protected package was removed.

Oscdimg writes ordinary progress on stderr. The old PowerShell treatment made those lines look like `ERROR:` records despite a successful ISO operation. The native wrapper now drains stdout/stderr concurrently and streams both as ordinary progress text. Actual nonzero process exits, missing images and undersized output still fail. Successful mastering and a checksum alone remain insufficient proof of an installable image.

The earlier registry-stage stall was also separate. An offline TaskCache `Id` string contained a terminating NUL; that truncated the native command before its `/f` argument, leaving `reg.exe` waiting for confirmation. The current code strips that terminator, rejects NUL in process arguments, closes native stdin and bounds registry commands to 30 seconds. Task deletion logs identify the current target. These fixes were already in the earlier commit and remain covered by the current tests. Ownership changes used for the offline TaskCache keys are limited to the mounted image's aliases, never host scheduled tasks or live TaskCache.

Return values also previously contained emitted native/hive-unload text instead of only the expected numeric status/ISO size. Streaming/logging output is now separated from those return values. This explains why normal native output could produce a PowerShell conversion error after an otherwise completed image step.

## 3. Upstream compression regression: a successful but larger export

[Issue #317](https://github.com/ntdevlabs/tiny11builder/issues/317) reported substantially less reduction than expected. A [specific comment](https://github.com/ntdevlabs/tiny11builder/issues/317#issuecomment-2591938012) traced it to [commit bba078c](https://github.com/ntdevlabs/tiny11builder/commit/bba078c34bd2108188a09653ea1de32edffe7a93), which replaced a DISM recovery export with PowerShell Fast compression. [PR #319](https://github.com/ntdevlabs/tiny11builder/pull/319) proposed fixes including restoring the stronger export. Its presence is not evidence that the proposed change was merged.

[PR #197](https://github.com/ntdevlabs/tiny11builder/pull/197) is an earlier related maximum-versus-recovery compression change. These are relevant mentions of size behavior, not evidence that every oversized ISO has the same cause.

WIM/ESD exports can succeed using different compression algorithms. A filename or a success message cannot prove maximum compression was used. Our user-facing default is named **maximum**. The backend's historical DISM term `recovery` is retained only where its API requires it and for compatibility with old arguments. The wimlib maximum path uses solid LZMS compression, level 100 and 64 MiB chunks. Fast uses XPRESS; balanced uses LZX; none produces an uncompressed WIM.

The final compression operates on the patched Windows installation image, including its files, streams, metadata and sharing relationships. Oscdimg then packages that image alongside Setup/boot media into the ISO; it does not apply another general compression layer to the entire disc. Removing compression can greatly enlarge `install.wim` without changing which logical Windows files are present.

### Why the uncompressed test is about 15 GB

This is an expected result of the requested `none` setting, not evidence of duplicate images. The inspected uncompressed ISO is 14.7466 decimal GB, of which 13.8660 GB is its single uncompressed installation WIM and 0.8806 GB is the rest of the disc. The original 9.0473 GB Microsoft ISO uses compression and resource sharing, so it is not an uncompressed-size baseline.

The inspected none image has no compression-type flags in its WIM header (`0x80` includes the other header flags). The diagnostic fast image uses XPRESS (`0x20082`); the earlier maximum ESD uses LZMS (`0x80082`). These container observations agree with the selected modes. Integrity verification and saved file/hive inspection passed for the none output. A large uncompressed container does not mean the removed apps were silently restored.

An uncompressed final export still reads/decompresses the working WIM, writes the remaining unique file data, records integrity information, masters the larger ISO and hashes it. Its measured final export took 69.4 seconds; ISO writing took 37.1 seconds and hashing took 22.9 seconds. Therefore disabling compression does not remove every final-stage cost or guarantee a large total speed gain compared with fast compression.

## 4. Upstream duplicate images: both original and patched files in one ISO

[Issue #318](https://github.com/ntdevlabs/tiny11builder/issues/318) reported a Core ISO larger than the official input. A [log analysis](https://github.com/ntdevlabs/tiny11builder/issues/318#issuecomment-2587056878) identified failure to delete an original WIM while it remained locked. Later comments identified `install.wim`, `install2.wim` and an ESD in the output, and the [reporter eventually confirmed improvement](https://github.com/ntdevlabs/tiny11builder/issues/318#issuecomment-2590487842) after resolving the image-file handling. That thread supports a duplication failure; it does not establish a universal 2-3 GB expected size.

Our copy stage excludes the original `install.wim`/`install.esd`, and the final image replacement must succeed before mastering. `New-Tiny11Iso` now refuses to create an ISO unless `sources` contains exactly one installation-image file, named `install.wim` or `install.esd`. Leftover `install2.wim` and duplicate/split installation containers trigger failure. The current builder handles a single WIM/ESD, so allowing stray SWM files would hide a defect.

The previously completed ISO was inspected directly through the read-only optical-filesystem reader. It contains exactly one `sources\install.esd`, 5,348,371,930 bytes, with one image index. Its total size is 6,248,947,712 bytes (6.25 decimal GB / 5.82 GiB). Therefore duplicate installation images do not explain that ISO's size. See [verified-iso-layout.json](verification/2026-10-04/checkpoint-iso-layout.json).

## 5. Upstream component cleanup: an unsupported parameter could be missed

[Issue #321](https://github.com/ntdevlabs/tiny11builder/issues/321) and [issue #589](https://github.com/ntdevlabs/tiny11builder/issues/589) describe attempts to pass `-StartComponentCleanup` to `Repair-WindowsImage`, where that parameter was unsupported. Continuing after such an error can leave the component store uncleared while the surrounding script prints a misleading completion message.

Our normal cleanup uses native `dism.exe /Cleanup-Image /StartComponentCleanup /ResetBase` against the **offline mount**. The native result is inspected and a failed cleanup is reported. Component cleanup and final compression are separate costs and effects: cleanup removes superseded component payloads; compression encodes the surviving image data more densely.

The explicitly requested fast/none comparison skips component cleanup for both runs. It is useful for comparing the fastest fresh-build variants, but it must not be represented as an identical servicing-state result to the normal cleaned maximum-compression build. Skipping cleanup is an explicit test option, never a hidden change to the default.

## 6. Upstream silent installation failure: lost edition/language XML

[Issue #583](https://github.com/ntdevlabs/tiny11builder/issues/583) reports a build that completes but Setup rejects product-key validation. A contributor's [diagnosis](https://github.com/ntdevlabs/tiny11builder/issues/583#issuecomment-5346111545) and [PR #628](https://github.com/ntdevlabs/tiny11builder/pull/628) attribute affected images to missing edition/language XML after export. That PR was open when inspected; its proposed fix is not being presented as merged or independently verified on all Windows versions.

The fields named in that report are `EDITIONID`, `INSTALLATIONTYPE`, `PRODUCTTYPE`, `PRODUCTSUITE` and `LANGUAGES`. An image can still have an image name and `FLAGS` while lacking this Windows metadata. Data-integrity verification alone would not detect an incorrect edition description: it confirms container/data consistency, not successful Setup edition selection.

Our previously completed image retains `FLAGS=Professional`, `EDITIONID=Professional`, `INSTALLATIONTYPE=Client`, `PRODUCTTYPE=WinNT`, `PRODUCTSUITE=Terminal Server`, and `LANGUAGES` containing/defaulting to `en-US`. The raw-header/image-XML report is [verified-iso-layout.json](verification/2026-10-04/checkpoint-iso-layout.json), with selected edition details in [verified-edition.json](verification/2026-10-04/checkpoint-edition.json).

This rules out the particular missing-fields symptom for that inspected output. It does **not** prove that Windows Setup installs successfully, and it does not certify every future input ISO. Do not hard-code Pro/en-US XML into an arbitrary edition or patch raw header lengths using an unverified snippet. Validate the actual source and output edition metadata.

## 7. Other relevant upstream mentions and limits of the search

- [Discussion #522](https://github.com/ntdevlabs/tiny11builder/discussions/522) is the user's referenced size discussion. A newer ISO or another user's successful result cannot establish that our output is correct.
- [Issue #611](https://github.com/ntdevlabs/tiny11builder/issues/611) discusses limited size reduction relative to an official ISO. It is a size report, not proof of a single known cause.
- [Issue #625](https://github.com/ntdevlabs/tiny11builder/issues/625) reports a 12 GB Core image and includes an export suggestion. It is not a demonstrated reproduction of our hive-loading problem.
- Upstream regular Tiny11 and Tiny11 Core have different removal/serviceability policies. A smaller Core or older image is not an equivalent baseline for this regular preset.

The audit examined the upstream open/closed issue/PR inventory and targeted comments originally saved under `logs/upstream-audit`; that raw audit was deleted during cleanup. This is the relevant set found, not a claim to have found every historical mention on GitHub or the web. Source statuses are a snapshot as of the inspection date. Public read-only queries were used; no upstream comments or messages were posted.

## 8. Why earlier runs could take 20-40 minutes

Initial edition selection/export, mounting, app and capability removal, registry/file patches, component cleanup, committing the mount, final compression, boot-image patching, ISO mastering and hashing all consume time. Servicing mutates one shared component store and cannot safely be made concurrent by issuing several DISM removals against the same image.

The older supplied run took approximately 34 minutes 5 seconds. The earlier measured maximum LZMS export alone took 854.1 seconds (14 minutes 14 seconds), using 12 threads. A previously quoted 23.4 seconds measured only the **initial selected-edition export**, not a full build. A fast initial export and a slow final maximum export are consistent: the former can copy existing compressed resources from the original ISO; the latter must encode the changed image into a new solid container.

Resource reuse here means copying suitable compressed resources from the user's original input during the first build. It does not mean reusing a previous patched output or persistent application cache. The source-selected image passed full integrity verification and a logical metadata comparison covering 187,635 paths. Later source-versus-output checks also compared stream hashes, security, attributes, times and hard-link membership, normalizing only container-specific offsets and numeric link IDs. See [PERFORMANCE.md](PERFORMANCE.md) for those digests and checks.

More logical CPU threads can help compression, within available RAM. They do not eliminate disk throughput limits or servicing dependencies. The builder does not change host priority; adding unsafe parallel writers would compromise correctness. Measurements are reported per stage and as complete fresh-run totals, rather than extrapolating a whole-build speedup from one export.

## 9. Verification status and follow-up measurements

The older verified ISO was completed from an earlier committed checkpoint with targeted file-only repairs. It is not a fresh end-to-end run of the latest script. Its SHA-256 is `aa608492b46071e2a9df562e455437cf713c9b0e633f843de0ff2a9edff9d463`, and full image data/integrity verification passed.

The diagnostic fast-compression fresh run finished successfully: 575.8 seconds (9 min 36 sec), ISO 8,382,115,840 bytes (8.38 GB), install.wim 7,501,491,111 bytes (7.50 GB). Both component cleanup and maximum compression were explicitly disabled for this diagnostic. The [saved-image inspection](verification/2026-10-04/fast-inspection.json) independently confirmed:

- Full installation-image data/integrity verification passed.
- One installation container and one edition, with the source's Pro/en-US fields intact.
- All 29 removed app families have zero remaining WindowsApps paths.
- Terminal, Calculator, Notepad and Photos still have image files.
- The selected Edge, EdgeCore, EdgeUpdate and OneDriveSetup paths are absent.
- The three previously denied DWORDs read back as zero from the hives extracted from the **finished ISO**.
- BIOS and UEFI boot files and the answer file are present. This is a file-presence check, not a boot test.

The source Pro edition's reported uncompressed XML size is 26,770,709,765 bytes; the fast patched edition reports 23,110,349,644 bytes, about 3.66 GB less. These are image metadata totals, not installed physical disk-use measurements. The full original ISO has 11 editions sharing resources; the output has one. Comparing those compressed disc sizes alone cannot quantify app removal.

The user requested, and both runs have now completed, two fresh benchmark configurations: **none + skipped cleanup** for the fastest uncompressed setting, and **maximum + normal cleanup** for the normal smallest-image setting. Both use the same original ISO, Pro index, preset and patch selections. New folders and code/preset hash snapshots exclude previous patched-data reuse. The total comparison includes cleanup's effect; it must not be described as a compression-only controlled comparison or as byte-identical outputs.

The none run finished in 557.8 seconds (9 min 18 sec), with a 14,746,617,856-byte ISO and 13,865,993,139-byte uncompressed WIM. Its [saved-image inspection](verification/2026-10-04/none-inspection.json) passed all app/file/registry/integrity/metadata checks. The maximum run finished in 1265.9 seconds (21 min 6 sec), with a 6,229,929,984-byte ISO and 5,349,305,984-byte ESD; its [saved-image inspection](verification/2026-10-04/maximum-inspection.json) passed the same checks. Both recorded exit 0 with no build warnings. Maximum compression saves 57.8% of ISO bytes at an extra 11 min 48 sec. It used 12 threads and took 838.1 seconds (838.8 including stage overhead). Normal component cleanup took only 14.2 seconds in this sample.

The second builder started only after the previous builder/verifier exited. Its preflight again recorded zero earlier writers, mounts and offline hives. The four saved builder/catalog file hashes match between the two runs. The [full comparison](PERFORMANCE.md) explains configuration differences, timing boundaries, stage durations and why 14.75 GB without compression does not imply a removal failure.

Both builds captured the actual source XML and validated the final installation image before ISO mastering; their metadata was complete. Subsequently, the [review of PRs #623/#628/#622](UPSTREAM_PR_REVIEW.md) extended this guard to restore only missing source-derived edition/product/language fields using wimlib's supported API. Existing conflicts and invalid architecture/version/flags still fail. Readback is mandatory, integrity metadata is retained, and file data is not recompressed for the repair. This is fixture-verified on WIM and solid ESD; the retained benchmark ISO predates the PR adaptations. No raw WIM header/XML rewrite is used.

## Cleanup and retained output

On explicit user request, the original ISO was left intact and the final maximum ISO plus checksum/JSON sidecars were moved to `C:\Users\Z\Downloads\PROJECTS\ISOs\tiny11-26300-maximum-20261004-190253.iso`. SHA-256 was verified before and after moving:
`2b1cced1fe91288292b054416f9ce230168ba71eee1849290606b973c1f56808`.

**Follow-up at 20:01 CEST:** the previously recorded maximum ISO and its sidecars are absent from the ISOs folder and other recorded project/output locations. The original source ISO still exists. The user was asked whether the final output was moved or deleted. The cleanup JSON is a historical record; it does not establish current file availability. See [follow-up status](verification/2026-10-04/post-review-verification.json).

The entire task-created `C:\.temp` folder, earlier checkpoint, fast/uncompressed outputs, repository `artifacts`/raw `logs`, and downloaded development caches were removed after confirming no writers or mounts remained. The repository then occupied approximately 72.5 MB including Git and existing reference clones. [Cleanup evidence](verification/2026-10-04/cleanup.json) records the removed paths and preserved source/output. Historical paths in this report identify earlier tests; their raw files no longer exist. Compact JSON evidence was preserved before deletion.

No ISO has yet been booted/installed in a VM as part of this verification. That remains the limit on claims of installation success even when image/container/metadata checks pass.

Shareable summaries and controlled-test results are committed in [verification/2026-10-04](verification/2026-10-04). Raw logs and intermediate files were intentionally deleted during cleanup; the historically retained ISO is now absent at its recorded path. Historical filesystem references describe the executed tests, and the saved JSON summaries provide the remaining evidence.

## October 5 dependency and reference follow-up

The #604 readiness change catches unavailable/corrupt fallback tools before source image work and retains only a small tool binary. Both builders pass the prepared path to mastering; disappearance fails without a late download. A fresh Microsoft download/hash/help check passed. This addresses a late-failure risk, not the unexplained `reg load` mechanism.

The new pi0n00r-inspired `Select\Default` resolver prevents silently patching the wrong SYSTEM control set. The source/work guard rejects overlapping trees before workspace deletion/copy. The u0reo-inspired cloud-search addition is confined to the existing Search choice; machine Advertising ID protection already existed. These changes do not silently remove extra features or change the compression/default edition workflow.

See [UPSTREAM_PR_REVIEW.md](UPSTREAM_PR_REVIEW.md) and [REFERENCE_REVIEW.md](REFERENCE_REVIEW.md) for exact heads and decisions. New app regression counts/CI are in [VERIFICATION.md](VERIFICATION.md). Those newer fixtures do not turn either historical ISO into a build of the newer code. No normal-launch root-cause trace, fresh latest-code Windows ISO or target VM install was performed by this documentation update.
