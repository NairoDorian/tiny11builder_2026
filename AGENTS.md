# Agent entry point

Read the following before build, diagnostic or implementation work:

1. [docs/WORKING_NOTES.md](docs/WORKING_NOTES.md): current state, exact user boundary, verification and open work.
2. [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md): architecture and complete build/GUI/data contract.
3. [docs/README.md](docs/README.md): documentation map; then [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/VERIFICATION.md](docs/VERIFICATION.md) for the proposed change.

The user referenced `@RTK.md`. It is absent from this checkout as of 2026-10-05. If provided later, read it; do not invent its instructions.

The running Windows installation is read-only: never edit its system files, live registry/settings, Defender, host scheduled tasks, installed toolchains or CPU priority. Project/offline ISO/image work and normal temporary owned offline attachments are authorized, with cleanup. The product's optional host Defender-exclusion feature is not authorized in this session.

No overlapping build/image/hive writers. Stop and verify the previous owned process tree before a replacement; separate work folders do not isolate shared z* aliases. Do not use rebooting as normal recovery or reuse previous patched images to claim first-run speed. Preserve intended patch choices and maximum compression. Historical full builds predate current fixes; no current-code VM installation is proved.

Keep current state in WORKING_NOTES.md, architecture in PROJECT_GUIDE.md, evidence scope in VERIFICATION.md, and chronology in CHANGELOG.md. Update generated APPS/TWEAKS through scripts/update-generated.ps1. Preserve the user-requested local reference sources under ignored repos/. Do not execute fork scripts or copy their host-changing workflows.
