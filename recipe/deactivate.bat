@@echo off
setlocal enabledelayedexpansion

:: restore variables (if they existed prior to activation, they have a value that's not "placeholder")
for %%X in (
    CC CXX CMAKE_ARGS CMAKE_GENERATOR CMAKE_GENERATOR_PLATFORM CMAKE_GENERATOR_TOOLSET
    CMAKE_PREFIX_PATH CONDA_BUILD_CROSS_COMPILATION DISTUTILS_USE_SDK INCLUDE
    LIB MSSdk MSYS2_ARG_CONV_EXCL MSYS2_ENV_CONV_EXCL PY_VCRUNTIME_REDIST
    VS_MAJOR VS_VERSION VS_YEAR
) do (
    if "!_CONDA_BACKUP_%%X!" == "placeholder" (
        set "%%X="
    ) else (
        set "%%X=!_CONDA_BACKUP_%%X!"
    )
    set "_CONDA_BACKUP_%%X="
)
