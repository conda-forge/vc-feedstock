set YEAR=2015
set VER=14

mkdir "%PREFIX%\etc\conda\activate.d"

echo @echo on > "%PREFIX%\etc\conda\activate.d\vs%YEAR%_compiler_vars.bat"
echo SET "cross_compiler_target_platform=%cross_compiler_target_platform%" >> "%PREFIX%\etc\conda\activate.d\vs%YEAR%_compiler_vars.bat"
type "%RECIPE_DIR%\activate.bat" >> "%PREFIX%\etc\conda\activate.d\vs%YEAR%_compiler_vars.bat"

type "%PREFIX%\etc\conda\activate.d\vs%YEAR%_compiler_vars.bat"
