# User constraints and Windows 26H2 verification

Recorded on 2026-10-04.

- The user's host has just been updated to Windows 11 26H2, matching the ISO's Windows version. The source ISO is `Windows11_Client_x64_en-us_26300_9457.iso`.
- The running Windows installation is read-only: never edit its system files, live registry settings, security settings, or other host configuration, even temporarily. Project files, source/destination ISO files, extracted media and offline Windows images may be edited. Normal temporary ISO/image mounts and offline hive attachments used to service those images are authorized; they must be released afterward. Registry writes must target only the offline image, never live host keys.
- The user manages CPU priority themselves. Do not change CPU priority or host settings. The later request explicitly authorizes optimizing the build pipeline and researching APIs online, while retaining maximum compression and minimum final size; measure speed/size tradeoffs rather than silently reducing compression.
- Before restarting a build or diagnostic, stop its previous process tree and confirm it has exited. Never run overlapping attempts against the same image or hive.
- Fix the remaining log errors and verify the result with a real command-line build. Do not claim that all errors are fixed based only on unit tests.
- A reboot must not be the normal recovery procedure. Diagnose failures and make the scripts recover without requiring one where possible.

The earlier verification attempt reached a committed, unmounted install image at `C:\.temp\preserved-tiny11\tiny11\sources\install.wim`. Its recovery export was stopped on request. Three Widgets registry writes still failed, so that attempt is not a clean verified build. Registry ACL changes on a disposable source-hive copy did not resolve the denied writes; the observed key already permitted administrator access. Do not describe the cause as a proven ACL problem.

Earlier tests created temporary scheduled tasks and loaded disposable offline hives before the host read-only restriction was stated. Do not create host scheduled tasks or repeat host-setting diagnostics. Normal temporary attachments of offline image hives during an authorized ISO build are permitted, as clarified below. Remove only outstanding test artifacts created by this task if needed to restore the previous host state, and report that cleanup explicitly.

## Current verification and subsequent requests

- The final ISO `artifacts/tiny11-26300-verified.iso` was completed from the
  earlier committed checkpoint using file-only repairs and exports. It is
  6,248,947,712 bytes; SHA-256
  `aa608492b46071e2a9df562e455437cf713c9b0e633f843de0ff2a9edff9d463`.
  Maximum solid LZMS export took 854.1 seconds. Full image integrity passed.
- Independently extracted SOFTWARE and Default NTUSER from the final ESD and
  confirmed AllowNewsAndInterests, EnableFeeds and TaskbarDa are DWORD zero.
  Original checkpoint and source ISO remain preserved.
- Earlier diagnostic scheduled tasks/hive mounts were cleaned up. New tests
  use project files and offline file APIs; do not repeat those host diagnostics.
- This is not a fresh end-to-end revised builder run, and no VM boot/install
  test has been performed. Never imply otherwise.
- User explicitly requests clearer naming/comments, per-step GUI progress,
  elapsed time/ETA, and continued performance optimization with maximum final
  compression. Do not adjust their CPU priority or lower final compression.
- Latest preference supersedes the cache proposal: even first-time ISO
  detection should be fast. Read tiny image XML directly without mounting or
  persistent metadata caches. A built-in release list supplies filename hints,
  but builds, editions and indexes must come from actual image metadata.
- User requested dependency/package updates for speed. Audit upstream stable
  versions; dependencies remain project-local. Never install/update the host
  ADK, DISM, PowerShell, .NET or security settings without new authorization.
- File-only edition reuse export of the actual checkpoint took 21.9 seconds
  and passed full wimlib verification. WIM/ESD fixture tests cover LZX, XPRESS,
  solid LZMS conversion, edition selection, source preservation and failures.

## First-use and content equivalence verification

Reuse refers to compressed resources in the user's original source ISO, never
previous build outputs or cached patched images. The optimization must work on
a single first build. The existing patch behavior must survive export changes;
only specifically authorized error fixes may alter intended patch results.

Extracted the original ISO's WIM into a new project test folder without mounting
and exported its actual Pro index 6. The optimized edition export took 23.4 s.
All 187,635 paths matched the source edition's logical metadata digest:
41e3771b72fed692d68e5957eb26769524c868371f1f20906eef039a17cdef1a.
The selected WIM passed full data/integrity verification.

Compared the patched checkpoint against the final maximum-compressed ESD:
171,122 unchanged paths and 34,003 hard-link groups match (205,125 canonical
records). Digest: 36C42CFFEAF9BB4614C3D38D3985543EA89D7D94C6268653E4635DA3599FDE5C.
Only SOFTWARE and Default NTUSER, intentionally repaired for the three denied
DWORDs, were excluded; their saved DWORD values were independently verified.
Physical container offsets/compressed sizes and numeric hard-link IDs were
normalized; hard-link memberships, security, times, attributes, stream hashes
and uncompressed sizes were compared. Reports live in logs/manual-verification.

WIM/ESD regression tests now also verify final maximum compression preserves
alternate streams, metadata, security and actual hard-link membership. The
upstream script already does /ResetBase cleanup and recovery compression, so
those costly stages are not new. New step-duration logs expose slow stages.

## Fresh measurement authorization

The user clarified that offline ISO files, work files and normal offline-image
mounts are authorized. The restriction applies to system files/settings of the
running Windows machine. Do not alter those, create host scheduled tasks,
change Defender configuration, or set CPU priority.
Fresh measurement uses a new isolated project WorkDirectory and the original
ISO/preset, with maximum compression; never consumes previous patched outputs.

## Upstream oversized-image and silent-install regressions

- [Issue #317](https://github.com/ntdevlabs/tiny11builder/issues/317#issuecomment-2591938012)
  identifies commit bba078c replacing DISM recovery compression with PowerShell
  Fast compression. Our final maximum export explicitly uses solid LZMS.
- [Issue #318](https://github.com/ntdevlabs/tiny11builder/issues/318#issuecomment-2587056878)
  records locked originals/intermediates remaining alongside the final image.
  Our source copy excludes installation images; final replacement fails on
  error; ISO mastering now refuses multiple/temporary installation images.
- [Issue #321](https://github.com/ntdevlabs/tiny11builder/issues/321) and
  [#589](https://github.com/ntdevlabs/tiny11builder/issues/589) describe an
  unsupported Repair-WindowsImage -StartComponentCleanup parameter. We call
  DISM.exe /Cleanup-Image /StartComponentCleanup /ResetBase directly and report
  its result. Cleanup is a distinct operation from final compression.
- [Issue #583](https://github.com/ntdevlabs/tiny11builder/issues/583) and the
  still-open [PR #628](https://github.com/ntdevlabs/tiny11builder/pull/628)
  report lost edition/language XML causing a product-key validation failure
  at installation despite successful build. The existing verified ESD has
  Professional, Client, WinNT, Terminal Server and en-US metadata. This is an
  image inspection, not proof of a successful VM install.

A newer source alone is not sufficient evidence that a larger ISO is correct.
Check actual compression, duplicate installation images, successful removals/
cleanup and edition metadata. Do not promise a fixed 2-3 GB output size.

The user explicitly authorized C:\.temp for shortened offline-work paths and
ISO outputs. Preserved C:\tiny11 and C:\scratchdir work may be moved beneath
C:\.temp after confirming no image writers/mounts remain. Source ISO stays
preserved. This authorization does not permit editing running Windows files.
Latest request: measure fresh no-compression and fastest builds, compare size/
time, and fix the remaining offline hive-loading error before proceeding.

The preserved checkpoint and old scratch folder were moved into C:\.temp\preserved-tiny11 on explicit user request, after no writers/mounts remained. A disposable SOFTWARE copy still failed reg load at a 33-character path; do not attribute this failure to path length alone. The first fresh maximum build stopped after mounting, produced no ISO, cleaned up, and exited (553.7 s including failure cleanup). Edition export took 33.2 s and mount took 186.5 s.


For the detailed investigation, controlled hive-loading tests, related upstream reports and evidence limits, see [BUILD_BUG_REPORT.md](BUILD_BUG_REPORT.md). The user accepts approximately 5-6 GB if correctness is verified; do not chase a historical size by changing the patch feature set.

Fresh diagnostic fast build completed cleanly in 575.8 s (8,382,115,840-byte ISO); independent final ISO inspection verified all 29 removed app families absent, all four kept utilities present, targeted Edge/OneDrive paths absent, three DWORD repairs, image integrity and edition/language metadata. No VM install test. User's requested benchmark comparison is now two fresh builds: none/skip-cleanup versus maximum/normal-cleanup. None started 18:54:07. Code/preset hashes are saved per run; keep builder code unchanged between these two measurements.
