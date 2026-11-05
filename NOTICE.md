# Attribution and licensing notice

Tiny11 Builder Ultimate Edition 2026 began as a fork of the PowerShell scripts in
[ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder) and adapts
ideas from the community forks listed in [docs/REFERENCE_REVIEW.md](docs/REFERENCE_REVIEW.md).

- The [MIT license](LICENSE) covers the contributions made in this repository.
- The original ntdevlabs repository has **no license file**. Portions that derive from
  its original scripts keep whatever rights their authors hold; this notice does not
  grant or change those rights.
- In October 2026 ntdevlabs replaced its scripts with a C#/WinUI application that also
  has no license. **None of that application's code, XAML, translation catalogs or
  images is included here.** Behaviors adopted from it were reimplemented in our own
  PowerShell code and are credited in [CHANGELOG.md](CHANGELOG.md) and
  [docs/UPSTREAM_MERGE_PLAN.md](docs/UPSTREAM_MERGE_PLAN.md).
- Bundled third-party binaries keep their own licenses: DiscUtils (MIT, see
  [lib/vendor/DiscUtils/README.md](lib/vendor/DiscUtils/README.md)). Tools downloaded
  at build time (wimlib, Oscdimg) are fetched from their publishers and are not
  redistributed by this repository.
- Windows installation media, and the use and activation of Windows, remain subject
  to Microsoft's terms. This project does not distribute Windows.
