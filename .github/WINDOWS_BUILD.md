# Windows builds for this fork

`Windows build` runs on pushes to `master` and from **Actions → Windows build → Run workflow**.
It builds all standard KiCad Release targets on `windows-2022`, runs the `OrcadSchImport`
test suite (including the Chinese encoding regression), and installs a portable application.

After a successful run, download `kicad-windows-x64-<commit>` from **Artifacts** and extract
the entire archive. Start `bin/kicad.exe` or `bin/eeschema.exe`. Standard symbol, footprint,
and 3D model libraries are distributed separately. Logs are uploaded even when a build fails.
Artifacts are retained for 14 days. No personal access token or custom repository secret is needed.

The dependency setup follows the [KiCad Windows build guide](https://dev-docs.kicad.org/en/build/windows-msvc/).
vcpkg is pinned to `66c0373dc7fca549e5803087b9487edfe3aca0a1`; its bundled CMake and
PowerShell versions match much of KiCad's public binary cache. Completed dependencies are
also cached in GitHub Actions, including completed packages from failed configuration attempts.
Each attempt saves a new cache snapshot so a partial cache can grow on the next run.
Initial builds can take significantly longer than cached builds.
Dependency compilation reports the latest internal build log every minute, including Ninja's
completed/total task count when available. This makes long OpenCascade builds visible in Actions.
The dependency/configuration step has a three-hour timeout; completed binary packages are saved
even after cancellation so later attempts can reuse them.

Two MIT-licensed vcpkg port overlays preserve the requested dependency versions:

- `ngspice` is copied from KiCad registry tree `8ca27c66b4a76f6c38536842e9e7ad09708bb228`.
  It uses CMake 4.4.4 only for source extraction to handle Unicode example paths, then restores
  vcpkg's CMake. The upstream source and patches are unchanged.
- `pcre2` is copied from Microsoft vcpkg tree `53bb7f4499d752b9e4d725b8b419ff225fef76e6`.
  PCRE2 10.49's SLJIT commit is pinned to the verified `deps/sljit` gitlink
  `de0259c7aaf36aa40cba8014f3fad3edde9307f9`, avoiding a checksum of mutable GitHub API JSON.
  Both source archive SHA-512 checks remain enabled.

The private `temp/` DSN remains local. Cloud tests use repository fixtures and generic byte
strings; importing that local sample and inspecting Chinese glyphs in the GUI remain desktop checks.
