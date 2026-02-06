@@echo on

:: Set env vars that tell distutils to use the compiler that we put on path
SET DISTUTILS_USE_SDK=1
:: This is probably not good. It is for the pre-UCRT msvccompiler.py *not* _msvccompiler.py
SET MSSdk=1

SET "VS_VERSION=@{vsver}.0"
SET "VS_MAJOR=@{vsver}"
SET "VS_YEAR=@{vsyear}"

set "MSYS2_ARG_CONV_EXCL=/AI;/AL;/OUT;/out"
set "MSYS2_ENV_CONV_EXCL=CL"

:: For Python 3.5+, ensure that we link with the dynamic runtime.  See
:: http://stevedower.id.au/blog/building-for-python-3-5-part-two/ for more info
set "PY_VCRUNTIME_REDIST=%PREFIX%\bin\vcruntime140.dll"

:: set CC and CXX for cmake
set "CXX=cl.exe"
set "CC=cl.exe"

set "VSINSTALLDIR="
set "NEWER_VS_WITH_OLDER_VC=0"

:: Try to find actual vs2017 installations
for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -version ^[@{vsver}.0^,@{vsver_plus_one}.0^) -property installationPath`) do (
  :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
  set "VSINSTALLDIR=%%i\"
)

if not exist "%VSINSTALLDIR%" (
  :: VS2025+ install but with vs2019/vs2022 compiler stuff installed
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -requires Microsoft.VisualStudio.Component.VC.@{vc_component} -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)
if not exist "%VSINSTALLDIR%" (
  :: VS2022+ install but with vs2017/vs2019 compiler stuff installed
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -requires Microsoft.VisualStudio.ComponentGroup.VC.Tools.@{vcver_nodots}.@{vc_component_name} -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)

if not exist "%VSINSTALLDIR%" (
  :: VS2019 install but with vs2017 compiler stuff installed
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -requires Microsoft.VisualStudio.Component.VC.v@{vcver_nodots}.@{vc_component_name} -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)

if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{vsyear}\Professional\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{vsyear}\Community\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{vsyear}\BuildTools\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{vsyear}\Enterprise\"
)

if not exist "%VSINSTALLDIR%" (
  :: Fallback to latest version of VS
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -latest -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)

IF NOT "%CONDA_BUILD%" == "" (
  :: building packages
  set "INCLUDE=%LIBRARY_INC%;%INCLUDE%"
  set "LIB=%LIBRARY_LIB%;%LIB%"
  set "CMAKE_PREFIX_PATH=%LIBRARY_PREFIX%;%CMAKE_PREFIX_PATH%"
) else (
  :: normal environment
  set "INCLUDE=%CONDA_PREFIX%\Library\include;%INCLUDE%"
  set "LIB=%CONDA_PREFIX%\Library\lib;%LIB%"
  set "CMAKE_PREFIX_PATH=%CONDA_PREFIX%\Library;%CMAKE_PREFIX_PATH%"
)


call :GetWin10SdkDir
:: dir /ON here is sorting the list of folders, such that we use the latest one that we have
for /F %%i in ('dir /ON /B "%WindowsSdkDir%\include\10.*"') DO (
  SET WindowsSDKVer=%%~i
)
if errorlevel 1 (
    echo "Didn't find any windows 10 SDK. I'm not sure if things will work, but let's try..."
) else (
    echo Windows SDK version found as: "%WindowsSDKVer%"
)

set "CMAKE_PLAT=@{target_msbuild_plat}"
set "VCVARSBAT=@{vcvarsbat}"

set "CMAKE_ARGS=-DCMAKE_BUILD_TYPE=Release"
set "MESON_ARGS=-Dbuildtype=release"
IF "%CONDA_BUILD%" == "1" (
  :: for -DPython_FIND_REGISTRY see https://github.com/conda-forge/conda-smithy/issues/2319
  set "CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% -DPython_FIND_REGISTRY=NEVER -DPython3_FIND_REGISTRY=NEVER -DCMAKE_PROGRAM_PATH=%BUILD_PREFIX%\bin;%BUILD_PREFIX%\Scripts;%BUILD_PREFIX%\Library\bin;%PREFIX%\bin;%PREFIX%\Scripts;%PREFIX%\Library\bin"
  set "MESON_ARGS=%MESON_ARGS% --prefix=%LIBRARY_PREFIX% -Dlibdir=lib"
)

:: set CMAKE_* variables
:: platform selection changed with VS 16 2019, but for compatibility we keep the older way
IF @{vsyear} GEQ 2019  (
    set "CMAKE_GEN=Visual Studio @{vsver} @{vsyear}"
    set "USE_NEW_CMAKE_GEN_SYNTAX=1"
) ELSE (
    IF "@{target_platform}" == "win-64" (
        set "CMAKE_GEN=Visual Studio @{vsver} @{vsyear} Win64"
    ) else (
        set "CMAKE_GEN=Visual Studio @{vsver} @{vsyear}"
    )
    set "USE_NEW_CMAKE_GEN_SYNTAX=0"
)

echo "NEWER_VS_WITH_OLDER_VC=%NEWER_VS_WITH_OLDER_VC%"

set /p LATEST_VS=<"%VSINSTALLDIR%\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt"
type "%VSINSTALLDIR%\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt"
dir "%VSINSTALLDIR%\VC\Redist\MSVC\"

if "%NEWER_VS_WITH_OLDER_VC%" == "1" (
  echo "%LATEST_VS%"
  if "%LATEST_VS:~0,4%" == "14.2" (
    set "CMAKE_GEN=Visual Studio 16 2019"
  ) else (
    set "CMAKE_GEN=Visual Studio 17 2022"
  )
  set "USE_NEW_CMAKE_GEN_SYNTAX=1"
)

IF "%CMAKE_GENERATOR%" == "" SET "CMAKE_GENERATOR=%CMAKE_GEN%"
:: see https://cmake.org/cmake/help/latest/envvar/CMAKE_GENERATOR_PLATFORM.html
IF "%USE_NEW_CMAKE_GEN_SYNTAX%" == "1" (
  IF "%CMAKE_GENERATOR_PLATFORM%" == "" SET "CMAKE_GENERATOR_PLATFORM=%CMAKE_PLAT%"
  IF "%CMAKE_GENERATOR_TOOLSET%" == "" SET "CMAKE_GENERATOR_TOOLSET=v@{vcver_nodots}"
)

pushd %VSINSTALLDIR%
if "%LATEST_VS:~0,5%" LSS "@{vcvars_ver}" (
  :: Installed latest VS is older than the conda package version, which means the
  :: lower bound of run_export is too high, but there's nothing we can do.
  :: For eg we have a 14.42 package but sometimes CI has 14.41
  CALL "VC\Auxiliary\Build\vcvars%VCVARSBAT%.bat" -vcvars_ver=%LATEST_VS:~0,5% %WindowsSDKVer%
) else (
  CALL "VC\Auxiliary\Build\vcvars%VCVARSBAT%.bat" -vcvars_ver=@{vcvars_ver} %WindowsSDKVer%
)

:: if this didn't work and CONDA_BUILD is not set, we're outside
:: conda-forge CI so retry without vcvars_ver, because that would
:: fail on local installs that don't match our exact versions
if %ERRORLEVEL% neq 0 (
  if "%CONDA_BUILD%" == "" (
    CALL "VC\Auxiliary\Build\vcvars%VCVARSBAT%.bat"
  )
)
popd

:: after calling vcvars, %VSINSTALLDIR% is in front of our own compilers on the path,
:: which is undesirable e.g. when using clang etc.; move our paths in front again
IF NOT "%CONDA_BUILD%" == "" (
  :: do not break long line without adding `setlocal enabledelayedexpansion` and switching to `!PATH!`
  set "PATH=%BUILD_PREFIX%;%BUILD_PREFIX%\Library\bin;%BUILD_PREFIX%\Scripts;%BUILD_PREFIX%\bin;%PREFIX%;%PREFIX%\Library\bin;%PREFIX%\Scripts;%PREFIX%\bin;%PATH%"
) else (
  set "PATH=%CONDA_PREFIX%;%CONDA_PREFIX%\Library\bin;%CONDA_PREFIX%\Scripts;%CONDA_PREFIX%\bin;%PATH%"
)

IF NOT "@{target_platform}" == "@{host_platform}" (
  set "CONDA_BUILD_CROSS_COMPILATION=1"
  set "CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=@{target_processor}"

  setlocal enabledelayedexpansion
    set CL_DIR1=
    set CL_DIR2=
    set CL_EXE=
    :: Get the first value from where cl.exe
    FOR /F "delims=" %%i IN ('where cl.exe') DO  if not defined CL_EXE set "CL_EXE=%%i"
    call :GetDirName CL_EXE CL_DIR1
    call :GetDirName CL_DIR1 CL_DIR2
    :: CL_DIR2 will have spaces in it, but some build tools like don't really like
    :: CC_FOR_BUILD etc having spaces in it
    :: Here we map CL_DIR2 to Z:
    subst Z: "!CL_DIR2!"
  endlocal

  set "CC_FOR_BUILD=Z:/@{host_msbuild_plat}/cl.exe"
  set "CXX_FOR_BUILD=Z:/@{host_msbuild_plat}/cl.exe"
  call :ReplaceInTargetVariable "%CONDA_PREFIX%/Library/lib;%LIB%" LIB_FOR_BUILD
  call :ReplaceInTargetVariable "%CONDA_PREFIX%/Library/include;%INCLUDE%" INCLUDE_FOR_BUILD
  set "LDFLAGS_FOR_BUILD=%LDFLAGS% /MACHINE:@{host_msbuild_plat}"
) else (
  set "CONDA_BUILD_CROSS_COMPILATION=0"
)

:GetWin10SdkDir
call :GetWin10SdkDirHelper HKLM\SOFTWARE\Wow6432Node > nul 2>&1
if errorlevel 1 call :GetWin10SdkDirHelper HKCU\SOFTWARE\Wow6432Node > nul 2>&1
if errorlevel 1 call :GetWin10SdkDirHelper HKLM\SOFTWARE > nul 2>&1
if errorlevel 1 call :GetWin10SdkDirHelper HKCU\SOFTWARE > nul 2>&1
if errorlevel 1 exit /B 1
exit /B 0

:GetWin10SdkDirHelper
@@REM `Get Windows 10 SDK installed folder`
for /F "tokens=1,2*" %%i in ('reg query "%1\Microsoft\Microsoft SDKs\Windows\v10.0" /v "InstallationFolder"') DO (
    if "%%i"=="InstallationFolder" (
        SET WindowsSdkDir=%%~k
    )
)
exit /B 0

:GetDirName
setlocal enableextensions enabledelayedexpansion
for %%A in ("!%1!") do set "local_dirname=%%~dpA"
if "!local_dirname:~-1!"=="\" set "local_dirname2=!local_dirname:~0,-1!"
endlocal & set "%2=%local_dirname2%"
exit /B 0

:ReplaceInTargetVariable
setlocal enabledelayedexpansion
set "input_var_name=%~1"
set "output_var_name=%~2"
:: We replace paths like C:\Program Files (x86)\Windows Kits\10\\lib\10.0.26100.0\\um\ARM64
:: to contain x64 for use in _FOR_BUILD variables
set "temp_var=!input_var_name:@{target_msbuild_plat}=@{host_msbuild_plat}!"
set "temp_var2=!temp_var:@{target_msbuild_plat_lower}=@{host_msbuild_plat_lower}!"
endlocal & set "%output_var_name%=%temp_var2%"
exit /B 0
