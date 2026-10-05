# Payload package files

Place top-level `.cmd` / `.ps1` scripts and their companion installer/data files here, then build with `-Payload`. The helper copies top-level files except this README into the offline image; **nested directories are not staged**.

Scripts run on the newly installed Windows as SYSTEM at SetupComplete, before first sign-in. All `.cmd` files run before all `.ps1` files; numeric prefixes do not create one mixed-extension global ordering. Use one orchestrator script for dependencies. Companion nonscript files are copied but not automatically executed.

See [../README.md](../README.md) for logs, OEM chaining, first-logon separation, examples and target-system behavior. See [../../docs/WORKING_NOTES.md](../../docs/WORKING_NOTES.md) before testing: these files must not be executed to modify the live build host. This README itself is not copied into the image.
