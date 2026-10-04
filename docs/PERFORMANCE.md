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

## Measurements on the user's Windows 26300.9457 media

| Operation | Measured result |
|---|---|
| Read all 11 editions from the original 9.05 GB ISO | 268 ms in a fresh PowerShell process, no application cache |
| Read the finished ISO's one edition | 84 ms |
| First export from the original ISO WIM, Pro index 6 | 23.4 seconds; standard LZX WIM; 187,635 paths logically identical; full verification passed |
| Final maximum solid LZMS export | 854.1 seconds (14 min 14 sec), 12 threads; 5,348,371,930-byte ESD |
| Finished ISO | 6,248,947,712 bytes; image data integrity passed |

These are operation timings, not a controlled old/new full-build comparison.
Filesystem caching and machine load affect them. The finished ISO came from
the earlier committed checkpoint plus file-only repairs; no fresh end-to-end
revised builder run or VM install/boot test has been performed.

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
