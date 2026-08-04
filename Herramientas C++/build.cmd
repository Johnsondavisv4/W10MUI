@echo off
title Building Native C++ Binaries for W10UI
echo ============================================================
echo Compiling PSFDeltaExtractor.exe and CBSReg.exe (x64)
echo ============================================================
echo.

set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if exist "%VCVARS%" (
    call "%VCVARS%" >nul
) else (
    echo Error: Could not find vcvars64.bat. Please ensure Visual Studio Build Tools is installed.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo Compiling CBSReg.exe...
cl.exe /nologo /O2 /EHsc CBSReg.cpp /link /out:..\W10UI\bin\CBSReg.exe Advapi32.lib Shell32.lib User32.lib
if %errorlevel% equ 0 (
    echo [SUCCESS] CBSReg.exe compiled to W10UI\bin\
) else (
    echo [FAIL] CBSReg.exe compilation failed
)

echo.
echo Compiling PSFDeltaExtractor.exe...
cl.exe /nologo /O2 /EHsc PSFDeltaExtractor.cpp /link /out:..\W10UI\bin\PSFDeltaExtractor.exe Advapi32.lib User32.lib
if %errorlevel% equ 0 (
    echo [SUCCESS] PSFDeltaExtractor.exe compiled to W10UI\bin\
) else (
    echo [FAIL] PSFDeltaExtractor.exe compilation failed
)

del *.obj 2>nul
echo.
echo ============================================================
echo Build process complete.
echo ============================================================
exit /b 0
