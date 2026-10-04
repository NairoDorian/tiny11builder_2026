# Build performance and dependencies

Audited on 2026-10-04. Host settings and CPU priority are outside this project's
optimization work. Maximum final compression stays enabled by default.

## Where time is saved

1. Edition selection reads only the optical filesystem directory, WIM header
   and XML resource. It needs no mounted volume, DISM process or metadata cache.
   The Windows release list supplies an instant filename hint, while the image
   XML supplies authoritative edition indexes/builds even for renamed ISOs.
2. An ordinary source WIM's compressed resources are reused during edition
   export, avoiding an unnecessary decode/recompress pass. LZX stays LZX;
   XPRESS stays XPRESS. Solid ESDs must become a non-solid servicing WIM.
3. The final image is exported once with wimlib's parallel solid LZMS compressor
   (high effort 100, 64 MiB solid blocks). Automatic threads respect CPU/memory
   limits. Higher effort can be requested, at extra CPU cost. `Dism` remains
   available through `-CompressionEngine Dism`.
4. Setup hardware checks require only small hive-file edits. Without driver
   injection, extract/update these files with wimlib instead of mounting and
   committing the whole Setup image. Preserve file security metadata.
5. Development checks scan source directories, excluding generated media and
   downloaded tools. The linter uses an existing pinned module or a project
   cache; it never installs modules into the host profile.

Do not run parallel servicing commands against the same image. Cleanup, app
removal and commit mutate shared image state. A newer dependency cannot make
those operations safely concurrent. No host exclusions/priority changes are
needed for the optimizations above.

## Two fresh complete builds

Measured sequentially from the original 9,047,330,816-byte ISO, Pro index 6,
with the same saved GUI preset and code (`7aa45d5`). Each used a new work folder;
no previously patched image or application cache was consumed. Kept utilities:
Terminal, Calculator, Notepad and Photos. The requested fastest uncompressed
configuration also skips component cleanup, so this compares two complete
configurations rather than compression alone.

| Configuration | Complete build | Final ISO | Install image |
|---|---:|---:|---:|
| `-Compress none -Fast` (cleanup skipped) | 9 min 18 sec | 14.75 GB / 13.73 GiB | 13,865,993,139-byte uncompressed WIM |
| `-Compress maximum` (normal cleanup) | 21 min 6 sec | 6.23 GB / 5.80 GiB | 5,349,305,984-byte solid LZMS ESD |

Maximum compression saves **57.8% of ISO bytes** at an extra **11 min 48 sec**.
GB here means decimal bytes/1,000,000,000; GiB means bytes/1,073,741,824.
The 14.75 GB output is expected: an uncompressed 13.87 GB install image plus
about 0.88 GB of Setup/media files. The original ISO stores compressed resources
shared by 11 editions; comparing it to a one-edition uncompressed output is not
a valid test of whether patching worked.

| Timed stage | None / skipped cleanup | Maximum / normal cleanup |
|---|---:|---:|
| Edition export from original ISO | 30.9 s | 26.5 s |
| Install image mount | 75.6 s | 66.1 s |
| Provisioned apps | 90.8 s | 82.6 s |
| Capabilities | 63.4 s | 60.4 s |
| Registry and task changes | 11.2 s | 9.8 s |
| Component cleanup | skipped | 14.2 s |
| Commit/unmount | 117.4 s | 112.3 s |
| Final compression/export | 69.4 s | **838.8 s (13 min 59 sec)** |
| Setup image patch | 2.8 s | 3.7 s |
| ISO writing and checksum | 60.0 s | 18.2 s |

Final compression consumed roughly 66% of the maximum build's total elapsed
time. It compresses the patched Windows installation image, not the whole ISO.
Mount, removal and commit still take several minutes even without it. The
compressor used all 12 logical CPUs exposed by this Windows installation. No
host priority, Defender, CPU topology or settings were changed. The finer
compression timer was 838.1 s; the stage timer includes its surrounding work.

Each timing runs from runner preflight through builder checksum/work cleanup;
independent finished-ISO inspection is additional QA outside that interval.
Both outputs passed complete image integrity/data verification, one-image
metadata checks, all 29 removed app-family absence checks, kept-app presence,
targeted Edge/OneDrive path absence and three saved hive DWORD readbacks. Neither
has been installed/booted in a VM. Results are one sample each; Windows filesystem
caches were not reset, and no general 2x full-build speedup is claimed. Earlier
20–40 minute builds remain plausible with CPU/storage/load and export-engine
variation. The operation improvements below avoid unnecessary export/Setup
work; there is no measured old-repository full-run baseline on this ISO.

See [machine-readable comparison](verification/2026-10-04/benchmark-comparison.json),
[hardware](verification/2026-10-04/benchmark-hardware.json), and the independent
[none](verification/2026-10-04/none-inspection.json) / [maximum](verification/2026-10-04/maximum-inspection.json)
inspection summaries. The maximum ISO and its sidecars were retained outside
the repository at `C:\Users\Z\Downloads\PROJECTS\ISOs\tiny11-26300-maximum-20261004-190253.iso`.
A follow-up path check at 20:01 CEST found that this recorded final ISO is now
absent. The user was asked whether it was moved/deleted; the source and saved
verification summaries remain. This report records historical measurements,
not a currently downloadable output. See [follow-up status](verification/2026-10-04/post-review-verification.json).
`C:\.temp`, other generated images, raw logs and task-created development caches
were removed on the user's request. Saved JSON evidence remains in Git.

## Earlier checkpoint measurements

| Operation | Measured result |
|---|---|
| Read all 11 editions from the original 9.05 GB ISO | 268 ms in a fresh PowerShell process, no application cache |
| Read the finished ISO's one edition | 84 ms |
| First export from the original ISO WIM, Pro index 6 | 23.4 seconds; standard LZX WIM; 187,635 paths logically identical; full verification passed |
| Final maximum solid LZMS export | 854.1 seconds (14 min 14 sec), 12 threads; 5,348,371,930-byte ESD |
| Finished ISO | 6,248,947,712 bytes; image data integrity passed |

These earlier operation timings used the committed checkpoint plus file-only repairs.
The complete fresh measurements above supersede their verification limitation.
The checkpoint and old output were deleted during the authorized cleanup.

Overall GUI percentages use stage weights and total ETA is explicitly rough.
Native percentages/counts measure the current step. Step ETA needs several
seconds of observed progress and disappears when that progress becomes stale.
Unmeasurable steps show an animated bar rather than invented percentages.

## Dependency audit

| Dependency | Project version/action | Performance relevance |
|---|---|---|
| [wimlib](https://www.wimlib.net/index.html) | 1.14.5, current official stable; ZIP/executable/DLL SHA-256 pinned | Main compression/export engine; parallel LZMS and compressed-resource reuse |
| [DiscUtils](https://www.nuget.org/packages/DiscUtils.Udf/0.16.13) Core, Streams, Iso9660, Udf | 0.16.13, latest stable packages; MIT assemblies bundled with hashes/license | Read-only ISO metadata without mounting or first-use downloads |
| [PSScriptAnalyzer](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0) | 1.25.0, current stable; pinned project-local fallback | Development checks only; no effect on ISO compression |
| [actions/checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) | Updated from v5 to v7.0.1 | CI dependency/security updates; no local build acceleration |
| [actions/upload-artifact](https://github.com/actions/upload-artifact/releases/tag/v7.0.1) | Updated from v4 to v7.0.1 | CI screenshot uploads; no local build acceleration |
| [Microsoft ADK / Oscdimg](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) | Installed ADK tools are preferred; pinned standalone Oscdimg 2.56 fallback retained | ISO mastering already uses duplicate-file elimination; no unverified speed claim from replacing it |
| Windows DISM, Storage, WinForms, .NET and Offreg | Read the existing host components; no host upgrade/install | Host servicing compatibility; tools remain read-only outside offline images |
| Firefox / Chrome optional first-login installers | Existing vendor `latest` URLs | Installed on the resulting Windows system, outside the ISO build's compression path |

Microsoft lists ADK 10.1.26100.9457 for Windows 26H2/25H2/24H2. Installing it
would change the host and was therefore not performed. The host's DISM was
observed as 10.0.26100.8457. Bundled or downloaded tools are kept inside this
repository, and builds do not poll release feeds on startup.

Reproduce file-only regression checks with `scripts/test-media-progress.ps1`
and `scripts/test-export-pipeline.ps1`. The latter uses the pinned wimlib
backend and verifies LZX, XPRESS and solid LZMS input handling.

## Correctness and first-use verification

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


For the detailed investigation, controlled hive-loading tests, related upstream reports and evidence limits, see [BUILD_BUG_REPORT.md](BUILD_BUG_REPORT.md). The user accepts approximately 5-6 GB if correctness is verified; do not chase a historical size by changing the patch feature set.
