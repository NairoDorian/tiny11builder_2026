# Reference branches and fork review — 2026-10-05

Current application incorporation: **`2ae045d`**, with [all CI checks passed](https://github.com/NairoDorian/tiny11builder_2026/actions/runs/37245856681). The branch heads/statuses below are snapshots of the 2026-10-05 fetch, not promises they never change. Start with [WORKING_NOTES.md](WORKING_NOTES.md), [PROJECT_GUIDE.md](PROJECT_GUIDE.md) and [VERIFICATION.md](VERIFICATION.md) for product/permissions/evidence. The new references are intentionally retained locally despite the earlier request to clean generated media; reference source is not patched-image cache data.

Downloaded the six requested branches and fetched all 15 existing reference checkouts. The reference set now contains **21 checkouts: the original and 20 community projects**. The 15 existing heads did not change on refresh; the six new branches were cloned at the revisions below. Their scripts were inspected as source, never executed. Source is available locally under Git-ignored `repos/`; the tracked [inventory](../data/reference-repos.json) and [sync script](../scripts/sync-reference-repos.ps1) make the set reproducible without committing duplicate repositories.

The original baseline is `ntdevlabs/tiny11builder/main` at `00e7d8a151a39ccffccab4a267bb81fb3756a01d`. Comparisons use the full tracked source trees against this refreshed original, including deleted original files, rather than assuming every fork contains the latest original commit. [Fetch audit](verification/2026-10-05/reference-sync.json) and [per-file/blob comparison](verification/2026-10-05/reference-comparison.json) record exact branches, full SHAs, line counts and recent commits. Recent commit lists may include shared original history.

## Newly requested references

| Reference / requested branch | Reviewed head | Files different from original | Result here |
|---|---|---:|---|
| [u0reo — feature/25h2-patch](https://github.com/u0reo/tiny11builder/tree/feature/25h2-patch) | `81475d33a3a04a57ab271a5736945fa7aa1ba43f` | 4 | Add the missing documented cloud-search policy under the existing Search choice. Most other useful policies already exist. |
| [luyingwei80 — Tony-patch-multi](https://github.com/luyingwei80/tiny11builder/tree/Tony-patch-multi) | `da9f5ace4cb542f08baee8b300dcb7cfd4e63f84` | 2 | Study its selected-edition loop and multilingual handling; retain our faster single-edition workflow and existing language/architecture handling. |
| [pi0n00r — deployment/2026-26h2](https://github.com/pi0n00r/tiny11builder/tree/deployment/2026-26h2) | `fe73f6e834c3c7b30b631982e57a19f1b1076f15` | 9 | Resolve the image's default control set and reject overlapping source/work trees in both builders. |
| [391546581 — main](https://github.com/391546581/tiny11builder/commits/main/) | `8d43b220bd8b21e013e77959efa5500a1aca698c` | 4 | Workflow changes only. Both makers and the original answer file are unchanged; no new patch/performance fix to import. |
| [icis-org — main](https://github.com/icis-org/tiny11builder/commits/main/) | `7bff69b4a759bf831253bf3474627af91efabe38` | 1 | Only `.github/workflows/build.yml` differs. No new builder fix; its image-format text replacement is unsuitable. |
| [lexp-hub — tiny11builder.sh/main](https://github.com/lexp-hub/tiny11builder.sh) | `f1911ff61dc41cfb9af4b7f72ff9083dd105ee3d` | 4 | Study the Linux/macOS port. Our file-only boot patch already avoids the costly mount; full filesystem recapture/resume is not adopted. |

### u0reo: broader 25H2 removal and policy patch

Changes add Japanese documentation, answer-file settings, more app families, AI/privacy registry entries, optional-feature removals and a raw WIM XML repair. The current branch also reverts some aggressive AI service/task and Settings restrictions; comparing only an older patch would misrepresent its current behavior.

The existing Advertising ID group already contains `DisabledByGroupPolicy=1`; there is no duplicate addition. The Search group now contains `AllowCloudSearch=0` at the documented Windows Search policy path, closing the gap between web-search blocking and the stated local-search intent. [Microsoft documents](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowcloudsearch) that zero blocks cloud sources such as OneDrive and SharePoint on supported Pro/Enterprise/Education editions. Home enforcement is not promised. The setting follows `DisableAds` and can be excluded with `-SkipTweak Search`, just like the other Search entries.

Photos remains selectable and retained by the measured preset. We did not silently add removals of printing/XPS components, generic AI frameworks or unrelated services. Those would change the patch feature set and require dependency/install validation. Existing Edge/Notepad/Paint/Recall/Widgets policies already cover much of this branch. Paint keeps the documented policy path rather than the alternate path in the fork.

The raw-header XML repair in this fork clears integrity metadata and handles only a first language. Our earlier #628 adaptation instead uses supported wimlib properties, preserves all source languages/default language and integrity information, refuses conflicting metadata, and requires readback. See [UPSTREAM_PR_REVIEW.md](UPSTREAM_PR_REVIEW.md). No raw container rewrite was imported.

### luyingwei80: multiple editions and deployment payload

Its original `tiny11maker.ps1` is unchanged; new `win11-multi.ps1` supplies Chinese prompts, selected-index processing, export/appending multiple patched editions to one ESD, language detection and deployment script/certificate payload handling. The other changed file is `autounattend.xml`.

A multi-edition build repeats servicing and commit work per selected edition and retains more content. It cannot be claimed as a faster or smaller replacement for our selected-edition build. Our existing options already choose the actual edition and handle architecture, languages, answer files and bounded hive unloads. We did not copy its raw native stderr redirection (fragile under PowerShell 5.1) or its `/Set-ImageInfo` call; our final metadata is validated and repaired through the supported wimlib interface. Imported certificates/payload commands would introduce new deployment behavior and were not added.

### pi0n00r: deployment safeguards, with a narrow target

This branch targets a particular Windows 11 Pro x64 build-26300 fleet, preserves Edge/WebView/Defender/Update for its applications, and adds deployment/playbook documents, checks and CI. We retain our configurable apps, editions and architectures rather than replacing them with that fleet's choices.

Two ideas address actual gaps:

- Catalog `ControlSet001` entries were previously always literal. An offline SYSTEM hive can designate another set in `Select\Default` for its next boot. After loading the owned `zSYSTEM` image hive, we now read and validate that selection and translate catalog writes, deletes, service presence checks and service start writes to it. `Default=1` behaves as before. Missing/invalid selection or a nonexistent selected set fails before guessing; the loaded hive remains tracked for cleanup. Selection resets after unload. `Setup\LabConfig`, other hives and explicit other control sets are unchanged. Deferred protected DWORD writes receive the already-resolved image subkey.
- Both builders now reject a work tree inside the source tree, or a source inside the work tree, before workspace deletion/copying. Canonical paths, case, trailing separators and parent segments are handled. This prevents a recursive copy or accidental source deletion. An ISO file stored on C: still works normally: its mounted source volume and C: workspace are separate trees.

NVMe FeatureManagement overrides are **not** an ISO-building speed optimization: they alter the installed Windows storage-driver behavior. The fork's own [deployment evidence](https://github.com/pi0n00r/tiny11builder/blob/fe73f6e834c3c7b30b631982e57a19f1b1076f15/docs/deployment-2026-26h2.md) states that its first three overrides did not enable the driver on 26300.9457, and the four-override experiment demonstrated binding in a VHD test but then reached Recovery during Setup. That is insufficient evidence for silently enabling the flags here. No override, live-host change or build-version restriction was copied.

### 391546581 and icis-org: CI changes, not new servicing fixes

Byte hashes confirm both makers and `autounattend.xml` match the refreshed original in both forks. `391546581` adds RDP/tunnel debugging, GUI screenshot CI and a private/self-hosted workflow plus settings documentation. Our CI already exercises the GUI and PowerShell 5.1/7 without modifying the live local host. RDP, firewall/account changes and external tunnels do not help our local build and were not copied.

`icis-org` modifies only its build workflow. It accepts an ISO URL, uses a hardcoded expiring Microsoft download URL and substitutes `install.esd` with `install.wim` in script text. Renaming strings cannot convert an image container or repair Windows Setup metadata. A fixed Pro/Home index label is also unreliable across ISOs. Our builder reads real indices and uses an explicit compression profile/native argument list. No such substitution was imported.

### lexp-hub: Linux/macOS filesystem recapture

This port adds Bash plus a Python/hivex registry editor and uses 7-Zip, wimlib and xorriso. It extracts/applies the selected installation image into an ordinary filesystem, deletes content/edits hive files, and captures a new LZMS image. It also updates small boot-image hive files with wimlib. Its work-directory reuse is useful for its environment, but conflicts with the user's requirement that improvements work on the first build without previous patched output.

Its capture call supplies a generic image name and compression without restoring source Windows edition/product/language XML. No equivalent DISM component-store servicing or logical security/stream/hard-link equivalence validation is shown. It therefore cannot establish the same patched image behavior or solve our earlier silent Setup metadata bug by itself. Our existing optimized first export reuses resources from the **original input ISO**, never earlier runs; our final compression preserves the serviced image, and boot patching already updates small hive files with strict metadata preservation. Those mechanisms were retained. The Windows GUI/project is not relabeled as cross-platform.

## Existing references, refreshed and compared

These heads remain unchanged after fetch. Their previously adopted contributions are recorded in the [README credits](../README.md#history-and-credits); no new upstream commits appeared to import on this refresh. Counts include documentation/workflows and deleted original files, so they are not a count of useful fixes.

| Local reference checkout | Head | Files different from original | Existing contribution / review scope |
|---|---|---:|---|
| `AhmedLolyProductions_Loly11` | `d641372305f4b2bb6cd06be3869ba7dfb30f1a05` | 6 | Package-list entries |
| `bedlaj_tiny11builder` | `6bcd07d03f0fe351e5660871c230b6ab3b46ef39` | 4 | ADK registry lookup |
| `bluecloud122_tiny11builder` | `ed0af96b0152bededa81e541d4cac5c246e496c8` | 8 | Low-RAM profile and source sanity checks |
| `chrisGrando_tiny11maker-reforged` | `b59c1b749455d7edd047b54aeb095f154af34fd5` | 13 | GUI/launcher, ISO mounting and ESD export |
| `DFwindows11_builder` | `7b96e5e2383e4c6180b06c106926da880615e05b` | 6 | Browser payloads and language-independent ACL handling |
| `keepitupkitty_tiny11builder` | `802e7d998ccfb4a7ae8c403a0a772c7f62d3ccf8` | 1 | Paint/Notepad policies and Edge/OneDrive leftovers |
| `MOPELotus_tiny11builder` | `834ca1a183fe2034531312f7c32538c92f1b2369` | 21 | Payload/SetupComplete, OOBE and lifecycle handling |
| `namnguyen97x_tiny-auto-builder` | `4f9632e8da5e09b9e1fe10c98d5b7ff3f9812a24` | 51 | Presets, drivers and bounded unload retries |
| `ntdevlabs_tiny11builder_upstream` | `00e7d8a151a39ccffccab4a267bb81fb3756a01d` | 0 | Original baseline; no diff |
| `prismatecas-ui_tiny11builder` | `c7dd8ac88365eaf158700466fa950c2f8b93b62a` | 6 | GUI options and app inventory |
| `SamHimmy_tiny11builder` | `ebdb5b84bd1e1f0835a460740cb65cd5b753134c` | 4 | AI, Recall and Widgets policies |
| `user129233_tiny11builder` | `0fe96cbddc72b558c608ed87b25369d42d53f6e6` | 6 | Specialize commands and answer-file cleanup |
| `vinisebold_tiny11builder-revamped` | `4091abd48876d065f2646f5ef39742d606914330` | 11 | Shared module, offline tasks and app selector |
| `YmlyZA_tiny11builder` | `b79056703ab64aafc8e592d2426a522476f71e72` | 28 | Tests, linter, summary and utility choices |
| `zPoche_tiny11builder-v2` | `9fa3c67d910ca6dde3c50b315ccf606c75effcb7` | 7 | Preflight, dry run, ARM64 and mount lifecycle |

## Update command and verification limits

Run `powershell -NoProfile -File .\scripts\sync-reference-repos.ps1 -ReportPath docs\verification\reference-sync.json` when another refresh is wanted. The helper uses the catalog's exact branches, validates local targets/origins, fetches source only, and fast-forwards clean checkouts. Dirty, detached, different-branch or divergent checkouts are preserved and reported rather than reset. It refuses redirected checkout/root directories. Reference source stays Git-ignored to keep the published project small; all six requested code checkouts are available locally.

The separate [PR #604 review](UPSTREAM_PR_REVIEW.md#pr-604-early-iso-writer-preparation--2026-10-05) also prepares Oscdimg before image work and retains its small verified portable download. Tool retention is not patched-image caching and brings no first-run compression shortcut.

Tests cover selected-control-set writes/deletes/service checks, invalid selections and cleanup tracking, source/work overlap, policy opt-out, early dependency download and cache corruption/offline/atomic failure paths. Fresh small WIM/ESD fixtures validate the unchanged export/metadata path. Full test counts are saved in [the check summary](verification/2026-10-05/post-review-verification.json).

These changes improve correctness and prevent wasted work; they do **not** establish a new measured speedup or a 2–3 GB target. The prior fresh full builds and size/time measurements remain historical results, not builds of this revision. No new complete Windows ISO build or VM installation was performed for this reference audit. All edits target project/offline-image work; the running Windows system remains read-only.
