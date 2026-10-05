# Bundled DiscUtils optical reader

DiscUtils 0.16.13, .NET Framework 4.0 assemblies from the official NuGet packages.
Used only for read-only UDF/ISO9660 filesystem access. Bundled so even the first
ISO selection works offline, without installing or downloading dependencies.

Source: https://github.com/DiscUtils/DiscUtils/tree/59d7cadab839c6d8dfcf52f8be5efe6d2ced190f
Packages: https://www.nuget.org/packages/DiscUtils.Udf/0.16.13
License: MIT, included in LICENSE.txt.

SHA-256 of distributed assemblies:

| File | SHA-256 |
|---|---|
| DiscUtils.Core.dll | 943BE4526DE97B20938777512B1AEDFA83A87998DDBD60372B503B14AFA9183D |
| DiscUtils.Iso9660.dll | 0B8847975614F6511EDF9ABBA56226D6B94806CE7985BE2B0CE15CF1D6A89ABC |
| DiscUtils.Streams.dll | 5273D509BF0B3E6082302830F045A27CF9A588F8861C65ADD7808C07A758FC48 |
| DiscUtils.Udf.dll | 1B5A3AF12F13E6E20D9C4B39B449DC679782BA7FC25E00B624221E166305E512 |

## Runtime contract and maintenance

The configured pin is 0.16.13, not a permanent claim that it is the newest available package. `lib/tiny11media.psm1` loads these assemblies to open the ISO read-only, select UDF or ISO9660, then read only the embedded install-image header/XML. This path does not attach the ISO, launch DISM, download libraries on first use or cache guessed editions. XML/resource bounds and actual source fields remain authoritative.

The original input and metadata are never modified by this reader. Unsupported optical/image encodings fail rather than substitute a filename-based edition list. Assemblies are .NET Framework-targeted for the supported PowerShell 5.1/7 paths; the project test matrix records what was actually exercised.

On an intentional dependency update, obtain official packages, keep matching Core/Streams/Iso9660/Udf versions, preserve the license, replace and verify every hash, then run metadata fixtures in both shells. Do not install a host-wide library to make first selection work. See [the project guide](../../../docs/PROJECT_GUIDE.md), [verification](../../../docs/VERIFICATION.md) and [performance/dependencies](../../../docs/PERFORMANCE.md).
