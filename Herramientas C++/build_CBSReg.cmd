@echo off
title Building CBSReg.exe (Native C++ Binary)
echo ============================================================
echo Compiling CBSReg.exe (x64)
echo ============================================================
echo.

set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

if exist "%VCVARS%" (
    call "%VCVARS%" >nul
) else (
    echo Error: Could not find vcvars64.bat. Please ensure Visual Studio C++ Build Tools are installed.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo Compiling CBSReg.exe...
cl.exe /nologo /O2 /EHsc CBSReg.cpp /link /out:CBSReg.exe Advapi32.lib Shell32.lib User32.lib

if %errorlevel% equ 0 (
    if not exist "..\W10UI\bin" mkdir "..\W10UI\bin" 2>nul
    if not exist "..\uup-converter-wimlib\bin" mkdir "..\uup-converter-wimlib\bin" 2>nul
    copy /y CBSReg.exe "..\W10UI\bin\CBSReg.exe" >nul
    copy /y CBSReg.exe "..\uup-converter-wimlib\bin\CBSReg.exe" >nul
    del CBSReg.exe 2>nul
    del CBSReg.obj 2>nul
    echo [SUCCESS] CBSReg.exe compiled successfully to W10UI\bin\ and uup-converter-wimlib\bin\
) else (
    echo [FAIL] CBSReg.exe compilation failed.
    pause
    exit /b 1
)

echo ============================================================
echo CBSReg build process complete.
echo ============================================================
pause
