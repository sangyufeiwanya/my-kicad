param(
    [Parameter(Mandatory)]
    [ValidateSet('configure', 'build', 'test', 'package')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot/../..").Path
$build = Join-Path $source 'build-msvc'
$deps = Join-Path $build 'vcpkg_installed/x64-windows'
$logs = Join-Path $source 'build-logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

# CTest and KiCad's module loader also need the internal shared libraries.
$env:PATH = "$deps/bin;$build/common;$build/api;$build/common/gal;$build/eeschema;$build/pcbnew;$build/kicad;$env:PATH"
$env:FONTCONFIG_PATH = "$deps/etc/fonts"

switch ($Stage) {
    'configure' {
        $python = Get-Command python -CommandType Application | Select-Object -First 1 -ExpandProperty Source
        cmake -S $source -B $build -G Ninja `
            -DCMAKE_BUILD_TYPE=Release `
            "-DCMAKE_TOOLCHAIN_FILE=$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" `
            "-DVCPKG_OVERLAY_TRIPLETS=$source/tools/custom_vcpkg_triplets" `
            "-DVCPKG_OVERLAY_PORTS=$source/.github/vcpkg-overlays" `
            -DVCPKG_TARGET_TRIPLET=x64-windows `
            -DVCPKG_HOST_TRIPLET=x64-windows `
            -DKICAD_BUILD_QA_TESTS=ON `
            -DKICAD_WIN32_INSTALL_PDBS=OFF `
            -DKICAD_INSTALL_DEMOS=OFF `
            -DX_VCPKG_APPLOCAL_DEPS_INSTALL=ON `
            "-DPYTHON_EXECUTABLE=$python" `
            2>&1 | Tee-Object -FilePath "$logs/configure.log"
    }
    'build' {
        cmake --build $build --parallel 2 2>&1 | Tee-Object -FilePath "$logs/build.log"
    }
    'test' {
        & "$build/qa/tests/eeschema/qa_eeschema.exe" --run_test=OrcadSchImport --log_level=test_suite `
            2>&1 | Tee-Object -FilePath "$logs/orcad-tests.log"
    }
    'package' {
        $out = Join-Path $build 'portable'
        cmake --install $build --prefix $out 2>&1 | Tee-Object -FilePath "$logs/install.log"
        if ($LASTEXITCODE -ne 0) { throw 'KiCad install failed' }

        # Include libraries loaded at runtime, such as ngspice, as well as linked DLLs.
        Copy-Item "$deps/bin/*.dll" "$out/bin" -Force
        Copy-Item "$deps/etc" $out -Recurse -Force
        Copy-Item "$deps/tools/python3/*" "$out/bin" -Recurse -Force
        Copy-Item "$deps/lib/ngspice" "$out/bin/ngspice" -Recurse -Force
        Copy-Item "$deps/share/ngspice/spinit" "$out/bin/ngspice" -Force

        foreach ($dependency in Get-ChildItem "$deps/share" -Directory) {
            $copyright = Join-Path $dependency.FullName 'copyright'
            if (Test-Path $copyright) {
                $licenseDir = "$out/share/dependency-licenses/$($dependency.Name)"
                New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
                Copy-Item $copyright $licenseDir
            }
        }

        @"
KiCad Windows x64 Release
Source: https://github.com/sangyufeiwanya/my-kicad
Commit: $env:GITHUB_SHA

Extract the entire artifact before starting bin/kicad.exe or bin/eeschema.exe.
This package includes the application, runtime DLLs and Python tools.
The standard symbol, footprint and 3D model libraries are separate KiCad downloads.
The local temp/ DSN is not included in this public repository or artifact.
"@ | Set-Content "$out/README.txt" -Encoding utf8

        # A build-tree PATH could hide missing DLLs in the downloadable package.
        Remove-Item Env:KICAD_RUN_FROM_BUILD_DIR -ErrorAction SilentlyContinue
        $env:FONTCONFIG_PATH = "$out/etc/fonts"
        $env:PATH = "$out/bin;$env:SystemRoot/System32;$env:SystemRoot"
        & "$out/bin/kicad-cli.exe" --version 2>&1 | Tee-Object -FilePath "$logs/package-smoke.log"
    }
}

if ($LASTEXITCODE -ne 0) { throw "KiCad $Stage failed with exit code $LASTEXITCODE" }
