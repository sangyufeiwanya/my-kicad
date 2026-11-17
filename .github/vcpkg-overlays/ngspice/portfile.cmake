vcpkg_check_linkage(ONLY_DYNAMIC_LIBRARY)

# ngspice produces self-contained DLLs
set(VCPKG_CRT_LINKAGE static)

# CMake 3.31 cannot extract ngspice's Unicode example paths under a Chinese Windows locale.
set(_kicad_saved_cmake_command "${CMAKE_COMMAND}")
set(CMAKE_COMMAND "$ENV{KICAD_ARCHIVE_CMAKE}")
vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL https://git.code.sf.net/p/ngspice/ngspice
    REF a80f6e3e95d51534905b1f23410a951802666656
    FETCH_REF ngspice-47
    PATCHES
        fix-winbison-path.patch
        Fix-C2065.patch
        remove-post-build.patch
        remove-64-in-codemodel-name.patch
        fftw3-tweaks.patch
        add-ARM64-arch-to-the-msbuild-projects.patch
)

set(CMAKE_COMMAND "${_kicad_saved_cmake_command}")

vcpkg_find_acquire_program(BISON)

get_filename_component(BISON_DIR "${BISON}" DIRECTORY)
vcpkg_add_to_path(PREPEND "${BISON_DIR}")

# ngspice 47's Windows projects link against libsndfile and libsamplerate.
file(WRITE "${SOURCE_PATH}/visualc/Directory.Build.props" "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<Project>
  <ItemDefinitionGroup>
    <ClCompile>
      <AdditionalIncludeDirectories>${CURRENT_INSTALLED_DIR}/include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
    <Link>
      <AdditionalLibraryDirectories>${CURRENT_INSTALLED_DIR}/lib;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
      <AdditionalDependencies>sndfile.lib;samplerate.lib;%(AdditionalDependencies)</AdditionalDependencies>
    </Link>
  </ItemDefinitionGroup>
  <ItemDefinitionGroup Condition=\"'$(Configuration)'=='Debug'\">
    <Link>
      <AdditionalLibraryDirectories>${CURRENT_INSTALLED_DIR}/debug/lib;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
    </Link>
  </ItemDefinitionGroup>
</Project>")

# Sadly, vcpkg globs .libs inside install_msbuild and whines that the 47 year old SPICE format isn't a MSVC lib ;)
# We need to kill them off first before the source tree is copied to a tmp location by install_msbuild

file(REMOVE_RECURSE "${SOURCE_PATH}/contrib")
file(REMOVE_RECURSE "${SOURCE_PATH}/examples")
file(REMOVE_RECURSE "${SOURCE_PATH}/man")
file(REMOVE_RECURSE "${SOURCE_PATH}/tests")

# this builds the main dll
vcpkg_msbuild_install(
    SOURCE_PATH "${SOURCE_PATH}"
    # install_msbuild swaps x86 for win32(bad) if we dont force our own setting
    PLATFORM ${TRIPLET_SYSTEM_ARCH}
    PROJECT_SUBPATH visualc/sharedspice.sln
    TARGET Build
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
file(COPY "${SOURCE_PATH}/src/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

if("codemodels" IN_LIST FEATURES)
    # vngspice generates "codemodels" to enhance simulation capabilities
    # we cannot use install_msbuild as they output with ".cm" extensions on purpose
    set(BUILDTREE_PATH "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}")
    file(REMOVE_RECURSE "${BUILDTREE_PATH}")
    file(COPY "${SOURCE_PATH}/" DESTINATION "${BUILDTREE_PATH}")

    if("fftw" IN_LIST FEATURES)
        vcpkg_build_msbuild(
            PROJECT_PATH "${BUILDTREE_PATH}/visualc/vngspice-fftw.sln"
            # build_msbuild swaps x86 for win32(bad) if we dont force our own setting
            PLATFORM ${TRIPLET_SYSTEM_ARCH}
            TARGET Build
        )
    else()
        vcpkg_build_msbuild(
            PROJECT_PATH "${BUILDTREE_PATH}/visualc/vngspice.sln"
            # build_msbuild swaps x86 for win32(bad) if we dont force our own setting
            PLATFORM ${TRIPLET_SYSTEM_ARCH}
            TARGET Build
        )
    endif()

    # ngspice oddly has solution configs of x64 and x86 but
    # output folders of x64 and win32
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL x64)
        set(OUT_ARCH  x64)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL x86)
        set(OUT_ARCH  Win32)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL arm64)
        set(OUT_ARCH  arm64)
    else()
        message(FATAL_ERROR "Unsupported target architecture")
    endif()

    #put the code models in the intended location
    file(GLOB NGSPICE_CODEMODELS_DEBUG
        "${BUILDTREE_PATH}/visualc/codemodels/${OUT_ARCH}/Debug/*.cm"
    )
    file(COPY ${NGSPICE_CODEMODELS_DEBUG} DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib/ngspice")

    file(GLOB NGSPICE_CODEMODELS_RELEASE
        "${BUILDTREE_PATH}/visualc/codemodels/${OUT_ARCH}/Release/*.cm"
    )
    file(COPY ${NGSPICE_CODEMODELS_RELEASE} DESTINATION "${CURRENT_PACKAGES_DIR}/lib/ngspice")


    # copy over spinit (spice init)
    file(RENAME "${BUILDTREE_PATH}/visualc/spinit_all" "${BUILDTREE_PATH}/visualc/spinit")
    file(COPY "${BUILDTREE_PATH}/visualc/spinit" DESTINATION "${CURRENT_PACKAGES_DIR}/share/ngspice")
endif()

vcpkg_copy_pdbs()

# Unforunately install_msbuild isn't able to dual include directories that effectively layer
file(GLOB NGSPICE_INCLUDES "${SOURCE_PATH}/visualc/src/include/ngspice/*")
file(COPY ${NGSPICE_INCLUDES} DESTINATION "${CURRENT_PACKAGES_DIR}/include/ngspice")

# This gets copied by install_msbuild but should not be shared
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/include/cppduals")
