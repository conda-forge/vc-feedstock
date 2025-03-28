@@echo on

:: Set env vars that tell distutils to use the compiler that we put on path
SET DISTUTILS_USE_SDK=1
:: This is probably not good. It is for the pre-UCRT msvccompiler.py *not* _msvccompiler.py
SET MSSdk=1

SET "VS_VERSION=@{ver}.0"
SET "VS_MAJOR=@{ver}"
SET "VS_YEAR=@{year}"

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
for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -version ^[@{ver}.0^,@{ver_plus_one}.0^) -property installationPath`) do (
  :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
  set "VSINSTALLDIR=%%i\"
)

if not exist "%VSINSTALLDIR%" (
  :: VS2022+ install but with vs2017/vs2019 compiler stuff installed
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -requires Microsoft.VisualStudio.ComponentGroup.VC.Tools.@{vcver_nodots}.x86.x64 -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)

if not exist "%VSINSTALLDIR%" (
  :: VS2019 install but with vs2017 compiler stuff installed
  for /f "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -requires Microsoft.VisualStudio.Component.VC.v@{vcver_nodots}.x86.x64 -property installationPath`) do (
    :: There is no trailing back-slash from the vswhere, and may make vcvars64.bat fail, so force add it
    set "VSINSTALLDIR=%%i\"
    set "NEWER_VS_WITH_OLDER_VC=1"
  )
)

if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{year}\Professional\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{year}\Community\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{year}\BuildTools\"
)
if not exist "%VSINSTALLDIR%" (
set "VSINSTALLDIR=%ProgramFiles(x86)%\Microsoft Visual Studio\@{year}\Enterprise\"
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

set "CMAKE_PLAT=@{cmake_plat}"
set "VCVARSBAT=@{vcvarsbat}"

set "CMAKE_ARGS=-DCMAKE_BUILD_TYPE=Release"
IF "%CONDA_BUILD%" == "1" (
  set "CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% -DCMAKE_PROGRAM_PATH=%BUILD_PREFIX%\bin;%BUILD_PREFIX%\Scripts;%BUILD_PREFIX%\Library\bin;%PREFIX%\bin;%PREFIX%\Scripts;%PREFIX%\Library\bin"
)

IF NOT "@{target_platform}" == "@{host_platform}" (
  set "CONDA_BUILD_CROSS_COMPILATION=1"
  set "CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=@{target_processor}"
) else (
  set "CONDA_BUILD_CROSS_COMPILATION=0"
)

:: set CMAKE_* variables
:: platform selection changed with VS 16 2019, but for compatibility we keep the older way
IF @{year} GEQ 2019  (
    set "CMAKE_GEN=Visual Studio @{ver} @{year}"
    set "USE_NEW_CMAKE_GEN_SYNTAX=1"
) ELSE (
    IF "@{target_platform}" == "win-64" (
        set "CMAKE_GEN=Visual Studio @{ver} @{year} Win64"
    ) else (
        set "CMAKE_GEN=Visual Studio @{ver} @{year}"
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
:: conda-forge CI so retry without vcvars_ver, which is going to
:: fail on local installs that don't match our exact versions
if %ERRORLEVEL% neq 0 (
  if "%CONDA_BUILD%" == "" (
    CALL "VC\Auxiliary\Build\vcvars%VCVARSBAT%.bat"
  )
)
popd

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
