# Verification state, evidence and next-run procedure

Updated **2026-10-05**. Latest application implementation audited: `2ae045d`. Documentation changes do not promote earlier fixtures or benchmarks into a new current-code full build. [WORKING_NOTES.md](WORKING_NOTES.md) states permissions; [PROJECT_GUIDE.md](PROJECT_GUIDE.md) explains the pipeline.

## Evidence levels

| Level | What it establishes | What it does not establish |
|---|---|---|
| Parse / command resolution / lint | Source syntax, literal command availability and selected analyzer rules | Native image operations succeed or all dynamic arguments are correct |
| Pure/mocked regression and fake GUI build | Options/plans, registry/control-set guards, failure branches, GUI launch/timing/progress behavior | Real DISM/hive-load launch compatibility or a complete Windows installation |
| Fresh small WIM/ESD fixtures | Real resource export/integrity, logical streams/security/times/hard links, source-derived metadata repair and no-op/conflict behavior | Full Windows package/component servicing, driver boot or target hardware support |
| Fresh complete Windows ISO build | The tested source/options/revision traversed real servicing and mastering | Every requested policy took effect, Setup boots/installs, all other presets/platforms work |
| Independent saved-image inspection | Planned file/app absence/presence, extracted registry values, one container/edition, metadata/data integrity | Runtime policy effectiveness or successful activation/VM/hardware installation |
| Disposable VM boot and installation | Setup and installed-system behavior for the tested firmware/disk/source/options/revision | General compatibility across every Windows build/device/preset |

Do not use a success message or output size as a substitute for the next level. A build with counted warnings needs investigation of the affected patch. No verified target VM installation exists in the saved record.

## Latest application regression results

For `2ae045de3b8a0c4d8dd726534fea906c3cb78b14`:

| Check | Windows PowerShell 5.1 | PowerShell 7 |
|---|---:|---:|
| Core helpers/catalog/answer files/mock stages/fake GUI | 1,918 passed; zero failures | 1,920 passed; zero failures |
| Real file-only WIM/ESD exports | 129 passed | 129 passed |
| ISO metadata / progress / timing fixtures | 23 passed | 23 passed |
| Parse and command resolution | passed | passed |
| Generated-file freshness | passed locally / CI | same generated content checked locally |
| PSScriptAnalyzer | CI passed | local passed |
| GUI tab rendering / fake build | passed | passed |

Local engines were 5.1.26100.9549 and 7.6.5. Different shells/platform conditions can change a small number of conditional checks; totals are a dated observation, not a permanent assertion in new tests. [Saved result and source hashes](verification/2026-10-05/post-review-verification.json). [All three CI jobs passed](https://github.com/NairoDorian/tiny11builder_2026/actions/runs/37245856681): PowerShell 5.1, PowerShell 7, XML/JSON.

The new control-set cases simulate Default=2, write/delete/service routing, missing services, denied DWORD fallback destination, invalid/missing selection, cleanup tracking and unload reset. No real mounted SYSTEM hive with Default=2 was serviced in this audit. Source/workspace separation is path-tested before copy/deletion. Oscdimg tests include valid/corrupt/offline/wrong-hash downloads, atomic publish/cleanup, retained-tool precedence and prepared-path mastering. A **fresh actual Microsoft tool download** matched its pin, native help ran, second initialization found it, and the disposable fixture was removed; [download result](verification/2026-10-05/oscdimg-live-check.json). Native help exit 1 is recorded as normal help behavior.

## Full-build history and provenance

| Run | Code / configuration | Time / output | Independent result |
|---|---|---|---|
| Earlier checkpoint plus file-only repairs | A previously committed image, repaired three denied DWORDs, maximum LZMS | 6,248,947,712-byte ISO; final export 854.1 s | Data/integrity and saved DWORDs; historical output deleted |
| Diagnostic fast fresh Standard run | Original 26300.9457 Pro x64/en-US, fast XPRESS, cleanup skipped | 575.8 s; ISO 8,382,115,840 bytes; WIM 7,501,491,111 bytes | App/file/registry/metadata/integrity inspection passed; its process loaded the module before the early-probe edit |
| Fresh none comparison | `7aa45d5aa88e5c2bab9a9df692fe51404357c8ce`, same original input/preset selections, `-Compress none -Fast` | 557.8 s; ISO 14,746,617,856 bytes; WIM 13,865,993,139 bytes | Exit 0, no warnings, finished-image inspection passed |
| Fresh maximum comparison | Same commit/input/selections, `-Compress maximum`, normal cleanup | 1265.9 s; ISO 6,229,929,984 bytes; ESD 5,349,305,984 bytes | Exit 0, no warnings, finished-image inspection passed |
| PR/reference changes after those runs | `cebf4cd` then `2ae045d` | Regression fixtures only | No new complete Windows ISO or VM install |

Input was `Windows11_Client_x64_en-us_26300_9457.iso`, 9,047,330,816 bytes, with 11 editions; selected Pro index 6 becomes output index 1. Kept utilities: Terminal, Calculator, Notepad, Photos. The saved custom GUI preset hash matches across the none/maximum runs. The raw custom preset/logs were deleted during cleanup; surviving argument/preflight/hash reports prove the two runs matched, but do not reconstruct every custom preset flag from a hash. For a new reproducible run, save the **actual flag values** as well as hashes before deleting raw files. Do not silently relabel the historical preset as the built-in Default.

Both comparison outputs were independently checked for all 29 planned app-family removals, four kept utilities, targeted Edge/OneDrive removal, three repaired DWORD zeros, one image/container, complete Pro/en-US metadata and data/integrity. BIOS/UEFI and answer-file presence was inspected, not booted. Earlier logical comparisons preserved stream hashes, security/attributes/times and hard-link memberships while normalizing container offsets/link IDs; excluded repaired hive files were separately read back. See [PERFORMANCE.md](PERFORMANCE.md) for digests and stage times.

The maximum run saved 57.8% of ISO bytes at an additional 708.1 seconds. Cleanup differs by request, so this is a comparison of full configurations, **not** compression alone or byte-identical servicing states. One sample per configuration; filesystem caches were not reset. No measured full old-repository baseline or general 2x speedup exists.

## Where evidence lives

| Directory / file group | Contents |
|---|---|
| `verification/2026-10-04/source-edition.json` | Actual original edition count and selected Windows metadata |
| `none-*`, `maximum-*` | Arguments, source/preset preflight, code hashes, status, independent saved-image checks |
| `benchmark-comparison.json`, `benchmark-hardware.json` | Timings, size deltas, hardware observation and measurement boundary |
| `hive-load-direct/shell/wmi.json`, `failed-build-status.json` | Controlled native hive-load launches and failed-run cost |
| `fast-*`, `checkpoint-*` | Earlier diagnostic/checkpoint evidence; different scope from full comparison |
| `cleanup.json`, dated `post-review-verification.json` | Historical cleanup/output availability and later regression status |
| `verification/2026-10-05/pr604-audit.json` | Exact #604 head/base and reviewed patch |
| `reference-sync.json`, `reference-comparison.json` | All 21 downloaded branch heads, refresh statuses and full source-tree comparisons |
| `post-review-verification.json`, `oscdimg-live-check.json` | Latest application tests/source hashes and actual disposable tool download |

The original source ISO remains. Historical final media/checkpoints/raw logs are deleted or absent at the recorded path. JSON absolute paths describe where a test ran; their existence is not implied. Source/reference audits do not alter upstream issues/PRs or execute fork scripts. See the working notes for current availability and the bug report for causal limits.

## Running development checks

From the repository, use an ordinary Windows shell. Run suites sequentially if they share fixtures/tool-cache writers; do not overlap build/servicing operations. These commands create disposable project/temp fixtures and logs, not a full Windows image build.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\parse-check.ps1
pwsh -NoProfile -File .\scripts\parse-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-core-helpers.ps1
pwsh -NoProfile -File .\scripts\test-core-helpers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-media-progress.ps1
pwsh -NoProfile -File .\scripts\test-media-progress.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-export-pipeline.ps1
pwsh -NoProfile -File .\scripts\test-export-pipeline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-generated.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\linter.ps1
```

The explicit Windows PowerShell command uses a child-process startup flag because direct File invocation was blocked by script policy in this environment. It does not run Set-ExecutionPolicy or persist host policy/registry changes. Do not change machine/user execution policy to make the checks run.

Check process exit codes, not the last printed line after a shell pipeline. Export fixtures need the pinned portable wimlib tool, downloaded into the project if absent; lint may use its pinned project-local fallback. Core/fake-GUI tests do not reproduce actual DISM image mounts or the original native hive launch. Regenerate screenshots only if visible UI changed, through the existing window-only renderer.

For a documentation-only change, validate Markdown links/claims, generated freshness, changed-generator parsing and whitespace; a new full ISO benchmark adds no evidence about prose. If a generator's emitted Markdown changes, regenerate it and ensure the reference XML/module manifests remain unchanged unless intentionally edited.

## Procedure for a later authorized real build

1. Read the host boundary and record current revision, complete effective preset flags, explicit Keep/Remove/Skip choices, source hash/bytes/selected metadata, compression/backend/threads, output/work paths and timing boundary. Do not infer edition index from an old filename or prior build.
2. Inspect previous builder/native writers and owned mount/hive state. If replacing an attempt, stop that specific process tree and verify exit first. Do not terminate unrelated Windows servicing. If state is uncertain, investigate before launching; a new folder alone cannot isolate shared registry aliases.
3. Choose a fresh **isolated** empty WorkDirectory and a new output filename outside the repository. Preserve original input. Use the passing manual launch context if revisiting the reproduced hive condition; changing path length alone did not fix it. Do not create scheduled tasks, change execution policy persistently, Defender, CPU priority or live registry as a workaround.
4. Use DryRun with that isolated directory to examine the plan. It can write logs/attach the source; it skips actual image patching and the early Oscdimg download. A real run exercises the disposable hive preflight and actual mount probe. Capture their native results.
5. Run one builder to completion, capture exit/warnings/stage timings, then finish all writers before inspection. Hash the output, confirm one installation container/edition, verify its full WIM/ESD data, match source metadata and inspect the **saved image** for intended app/file removals, kept utilities and relevant DWORD values. Do not check only the temporary working mount.
6. If installation behavior is the change being verified, boot/install on an explicitly disposable VM/test disk. Record firmware mode, source/output hash, edition selection, Setup result and relevant installed behavior. ZeroTouch can wipe target disk 0. A presence check of boot files is not equivalent.
7. Save compact reproducible evidence, preserve any requested output/sidecars at a verified path, then release owned attachments and clean only owned temporary work after validating absolute targets. If cleanup fails or state is unknown, preserve image files and record the failure rather than recurse through a mount.

No benchmark is pending automatically. The next full/VM run is outstanding validation, not work secretly performed by this documentation refresh.
