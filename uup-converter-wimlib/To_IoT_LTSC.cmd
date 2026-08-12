@setlocal DisableDelayedExpansion
@echo off

:: Clave de producto genérica OEM inyectada vía DISM para activación digital
set "OEMKey=CGK42-GYN6Y-VD22B-BX98W-J8JXD"

set "_Null=1>nul 2>nul"
set DisableWimRebuilds=0
set UseDism=1
set AutoStart=0
set DeleteSource=1
set Preserve=0
set wim2esd=0
set wim2swm=0
set SkipISO=0
set "_wrb="
if %DisableWimRebuilds% equ 1 set "_wrb=rem."

set _uupc=0
set _Debug=0
set _type=
set qerel=
set _elev=
set _args=
set _args=%*
if not defined _args goto :NoProgArgs
if "%~1"=="" set "_args="&goto :NoProgArgs
for %%# in (%*) do call :parseArgs "%%#"
if defined _exTP1 if defined _exTP2 set "_exTime=%_exTP1%,%_exTP2%"
goto :NoProgArgs

:parseArgs
if "%~1"=="-elevated" (set _elev=1&exit /b)
if "%~1"=="-qedit" (set qerel=1&exit /b)
echo %~1|findstr /i "autoswm autowim autoesd manuswm manuwim manuesd extdism" >nul && (set "_type=%~1"&exit /b)
echo %~1|findstr \/ >nul && (set "_exTP1=%~1"&exit /b)
echo %~1|findstr :  >nul && (set "_exTP2=%~1"&exit /b)
echo %~1|findstr _  >nul && (set "_exLabel=%~1"&exit /b)
exit /b

:NoProgArgs
:: @color 07
set "xOS=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="arm64" set "xOS=arm64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if "%PROCESSOR_ARCHITEW6432%"=="" set "xOS=x86"
if /i "%PROCESSOR_ARCHITEW6432%"=="amd64" set "xOS=amd64"
if /i "%PROCESSOR_ARCHITEW6432%"=="arm64" set "xOS=arm64"
set "xDS=bin\bin64;bin"
if /i not %xOS%==amd64 set "xDS=bin"
set "SysPath=%SystemRoot%\System32"
set "Path=%xDS%;%SysPath%;%SystemRoot%;%SysPath%\Wbem;%SysPath%\WindowsPowerShell\v1.0\"
if exist "%SystemRoot%\Sysnative\reg.exe" (
set "SysPath=%SystemRoot%\Sysnative"
set "Path=%xDS%;%SystemRoot%\Sysnative;%SystemRoot%;%SystemRoot%\Sysnative\Wbem;%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\;%Path%"
)
set "_err=echo: &echo ==== ERROR ===="
set "_psc=powershell -nop -c"
set winbuild=1
for /f "tokens=6 delims=[]. " %%# in ('ver') do set winbuild=%%#
set _cwmi=0
for %%# in (wmic.exe) do @if not "%%~$PATH:#"=="" (
cmd /c "wmic path Win32_ComputerSystem get CreationClassName /value" 2>nul | find /i "ComputerSystem" 1>nul && set _cwmi=1
)
set _pwsh=1
for %%# in (powershell.exe) do @if "%%~$PATH:#"=="" set _pwsh=0
cmd /c "%_psc% "$ExecutionContext.SessionState.LanguageMode"" | find /i "FullLanguage" 1>nul || (set _pwsh=0)
call :pr_color
if %_cwmi% equ 0 if %_pwsh% equ 0 goto :E_PWS

set _uac=-elevated
%_Null% reg.exe query HKU\S-1-5-19 && (
  goto :Passed
  ) || (
  if defined _elev goto :E_Admin
)

set _PSarg="""%~f0""" %_uac%
if defined _args set _PSarg="""%~f0""" %_args:"="""% %_uac%
set _PSarg=%_PSarg:'=''%

(%_Null% cscript //NoLogo "%~f0?.wsf" //job:ELAV /File:"%~f0" %* %_uac%) && (
  exit /b
  ) || (
  call setlocal EnableDelayedExpansion
  %_Null% %_psc% "start cmd.exe -Arg '/c \"!_PSarg!\"' -verb runas" && (
    exit /b
    ) || (
    goto :E_Admin
  )
)

:Passed
if defined _type goto :skipQE
if %winbuild% LSS 10586 (
reg.exe query HKCU\Console /v QuickEdit 2>nul | find /i "0x0" >nul && set qerel=1
)
if defined qerel goto :skipQE
if %_pwsh% EQU 0 goto :skipQE
set _PSarg="""%~f0""" -qedit
if defined _args set _PSarg="""%~f0""" %_args:"="""% -qedit
set _PSarg=%_PSarg:'=''%
set "d1=$t=[AppDomain]::CurrentDomain.DefineDynamicAssembly(4, 1).DefineDynamicModule(2, $False).DefineType(0);"
set "d2=$t.DefinePInvokeMethod('GetStdHandle', 'kernel32.dll', 22, 1, [IntPtr], @([Int32]), 1, 3).SetImplementationFlags(128);"
set "d3=$t.DefinePInvokeMethod('SetConsoleMode', 'kernel32.dll', 22, 1, [Boolean], @([IntPtr], [Int32]), 1, 3).SetImplementationFlags(128);"
set "d4=$k=$t.CreateType(); $b=$k::SetConsoleMode($k::GetStdHandle(-10), 0x0080);"
setlocal EnableDelayedExpansion
%_psc% "!d1! !d2! !d3! !d4! & cmd.exe '/c' '!_PSarg!'" &exit /b
exit /b

:skipQE
set "logerr=%~dp0ErrorLog_V_%random%.txt"
set "_batf=%~f0"
set "_work=%~dp0"
set "_work=%_work:~0,-1%"
set _vdrv=%~d0
setlocal EnableDelayedExpansion
pushd "!_work!"
if exist "convert-UUP.cmd" (
for /f "tokens=2 delims==" %%# in ('findstr /i /b /c:"set _Debug" "convert-UUP.cmd"') do if not defined _udbg set _udbg=%%#
for /f "tokens=2 delims==" %%# in ('findstr /i /b /c:"@set uivr" "convert-UUP.cmd"') do if not defined _uver set _uver=%%#
)
if defined _udbg set _Debug=%_udbg%
if defined _uver set uivr=%_uver%

if %_Debug% equ 0 (
  set "_Nul1=1>nul"
  set "_Nul2=2>nul"
  set "_Nul6=2^>nul"
  set "_Nul3=1>nul 2>nul"
  set "_Pause=pause >nul"
  set "_Contn=echo Press any key to continue..."
  set "_Exit=echo Press any key to exit."
  set "_Supp="
  set "_Nul7=1>nul 2>nul"
  goto :Begin
)
  set "_Nul1="
  set "_Nul2="
  set "_Nul6="
  set "_Nul3="
  set "_Pause=rem."
  set "_Contn=rem."
  set "_Exit=rem."
  set "_Supp=1>nul"
  set "_Nul7="
@echo on
@prompt $G

:Begin
set "_dLog=%SystemRoot%\Logs\DISM"
call :checkadk
set _fils=(7z.dll,7z.exe,cdimage.exe,imagex.exe,libwim-15.dll,offlinereg.exe,offreg.dll,wimlib-imagex.exe,veData.cmd)
for %%# in %_fils% do (
if not exist ".\bin\%%#" (set _bin=%%#&goto :E_Bin)
)
set "_mount=%_vdrv%\MountUUP"
set "_ntf=NTFS"
if /i not "%_vdrv%"=="%SystemDrive%" if %_cwmi% equ 1 for /f "tokens=2 delims==" %%# in ('"wmic volume where DriveLetter='%_vdrv%' get FileSystem /value"') do set "_ntf=%%#"
if /i not "%_vdrv%"=="%SystemDrive%" if %_cwmi% equ 0 for /f %%# in ('%_psc% "(([WMISEARCHER]'Select * from Win32_Volume where DriveLetter=\"%_vdrv%\"').Get()).FileSystem"') do set "_ntf=%%#"
if /i not "%_ntf%"=="NTFS" (
set "_mount=%SystemDrive%\MountUUP"
)

set ERRTEMP=
set _exDism=0
set _all=0
set _dir=0
set _dvd=0
set _iso=0
set "_ln2=____________________________________________________________"
set "_ln1=________________________________________________"
if not defined _type @color 07

if defined _args (
if /i "%_type%"=="autoswm" set _uupc=1&set AutoStart=1&set Preserve=0&set _Debug=1&set wim2esd=0&set wim2swm=1
if /i "%_type%"=="autowim" set _uupc=1&set AutoStart=1&set Preserve=0&set _Debug=1&set wim2esd=0&set wim2swm=0
if /i "%_type%"=="autoesd" set _uupc=1&set AutoStart=1&set Preserve=0&set _Debug=1&set wim2esd=1&set wim2swm=0
if /i "%_type%"=="manuswm" set wim2esd=0&set wim2swm=1
if /i "%_type%"=="manuwim" set wim2esd=0&set wim2swm=0
if /i "%_type%"=="manuesd" set wim2esd=1&set wim2swm=0
if /i "%_type%"=="extdism" set AutoStart=1&set Preserve=0&set _Debug=1&set _exDism=1&set _exEdtn=%2
)

set _shortINF=
if %_exDism% equ 0 goto :checkdir

:extdism
:: call :dk_color1 %Blue% "=== Creating Virtual Editions . . ." 4
set UseDism=1
set ISOdir=ISOUUP
set WimFile=install.wim
imagex /info ISOFOLDER\sources\%WimFile% >bin\infoall.txt 2>&1
for /f "tokens=3 delims=: " %%# in ('findstr /i /b /c:"Image Count" bin\infoall.txt') do set images=%%#
for /l %%# in (1,1,%images%) do imagex /info ISOFOLDER\sources\%WimFile% %%# >bin\info%%#.txt 2>&1
for /f "tokens=3 delims=<>" %%# in ('find /i "<BUILD>" bin\info1.txt') do set _build=%%#
set EditionHome=0
set EditionProf=0
set EditionProN=0
set EditionLTSC=0
set Edition%_exEdtn%=1
set _shortINF=1
call :sharedINF
goto :dCheck

:checkdir
title Virtual Editions %uivr%
dir /b /ad . %_Nul3% || goto :checkiso
for /f "tokens=* delims=" %%# in ('dir /b /ad .') do (
if exist "%%~#\sources\install.wim" set _dir=1&set "ISOdir=%%~#"
)
if %_dir% neq 1 for /f "tokens=* delims=" %%# in ('dir /b /ad .') do (
if exist "%%~#\sources\install.esd" set _dir=1&set "ISOdir=%%~#"
)
if %_dir% neq 1 goto :checkiso
goto :dCheck

:checkiso
if exist "*.iso" for /f "tokens=* delims=" %%# in ('dir /b /a:-d *.iso') do (
set /a _iso+=1
set "ISOfile=%%~#"
)
if %_iso% equ 1 (
set Preserve=0
goto :dISO
)


:dISO
:: @color 1F
@cls
call :dk_color1 %Blue% "=== Extracting ISO file . . ." 4 5
echo "!ISOfile!"
set ISOdir=ISOUUP
if exist %ISOdir%\ rmdir /s /q %ISOdir%\
7z.exe x "!ISOfile!" -o%ISOdir% * -r %_Null%

:dCheck
if defined _Supp (
if defined _args echo "!_args!"
echo "!_work!"
)
if %_Debug% neq 0 (
if %AutoStart% equ 0 set AutoStart=1
)
if not defined ISOdir (
(echo.&echo ISOdir source directory is not specified, or valid)>>"!logerr!"
exit /b
)
if exist bin\temp\ rmdir /s /q bin\temp\
:: @color 1F
set _configured=0
for %%# in (
UseDism
AutoStart
DeleteSource
Preserve
SkipISO
wim2esd
wim2swm
) do (
if !%%#! neq 0 set _configured=1
)
if defined SortEditions set _configured=1
if %_exDism% equ 1 goto :PROCESS_ISO
if %_uupc% equ 1 (call :dk_color1 %Blue% "=== Creating Virtual Editions . . ." 4) else (call :dk_color1 %Blue% "=== Checking distribution Info . . ." 4)
if %_dvd% equ 1 set Preserve=1
goto :dInfo

:PROCESS_ISO
if %_exDism% equ 1 goto :skipcopy

if exist ISOFOLDER\ rmdir /s /q ISOFOLDER\
move /y "%ISOdir%" ISOFOLDER %_Nul1%
attrib -A -I -R "ISOFOLDER\*" /S /D %_Nul3%
if not exist "ISOFOLDER\sources\%WimFile%" (
%_err%
echo Failed to create ISOFOLDER\sources\%WimFile%
echo.
(echo.&echo Failed to create ISOFOLDER\sources\%WimFile%)>>"!logerr!"
goto :E_None
)

:skipcopy
if %EditionLTSC% equ 0 goto :E_None
set /a index=%images%

:doDism
if %_exDism% equ 0 del /f /q "%_dLog%\DismVirtualEditions.log" %_Nul3%
if not exist "%_dLog%\" mkdir "%_dLog%" %_Nul3%
if %_build% geq 19041 if %winbuild% lss 17133 if not exist "%SysPath%\ext-ms-win-security-slc-l1-1-0.dll" (
copy /y %SysPath%\slc.dll %SysPath%\ext-ms-win-security-slc-l1-1-0.dll %_Nul1%
if /i not %xOS%==x86 copy /y %SystemRoot%\SysWOW64\slc.dll %SystemRoot%\SysWOW64\ext-ms-win-security-slc-l1-1-0.dll %_Nul1%
)
call :doMount %IndexLTSC%
call :doData IoTEnterpriseS
call :doUnmount %IndexLTSC%
if defined _term exit /b
if %_exDism% equ 1 exit /b
if %_build% geq 19041 if %winbuild% lss 17133 if exist "%SysPath%\ext-ms-win-security-slc-l1-1-0.dll" (
del /f /q %SysPath%\ext-ms-win-security-slc-l1-1-0.dll %_Nul3%
if /i not %xOS%==x86 del /f /q %SystemRoot%\SysWOW64\ext-ms-win-security-slc-l1-1-0.dll %_Nul3%
)
if %modded% equ 1 (goto :ISOCREATE) else (goto :E_None)

:doData
if defined _term exit /b
if /i %1==IoTEnterpriseS (
if %_build% lss 19041 exit /b
if not exist "%_mount%\Windows\System32\spp\tokens\skus\IoTEnterpriseS\IoTEnterpriseS-OEM*.xrm-ms" exit /b
)
set "EditionID=IoTEnterpriseS"
set "desc=IoT Enterprise LTSC"
set "winver=%wtxLTSC%"
set "channel=OEM"
call :dk_color1 %Gray% "=== Creating Edition: %desc%" 4
call :doWIM
exit /b



:doWIM
set "_chn=/Channel:%channel%"
if /i "%channel%"=="OEM" if %_build% neq 18362 set "_chn="
call :wds_add
%_dism1% /Image:"%_mount%" /LogPath:"%_dLog%\DismVirtualEditions.log" /Set-Edition:%EditionID% %_chn%
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 (
call :dk_color1 %Red% "Could not set %EditionID% edition." 4
(echo.&echo Could not set %EditionID% edition.)>>"!logerr!"
exit /b
)
if /i %EditionID%==ServerRdsh (
%_Nul3% reg.exe load HKLM\SYS "%_mount%\Windows\System32\config\SYSTEM"
%_Nul3% reg.exe add "HKLM\SYS\Setup\FirstBoot\PreOobe" /f /v 00 /t REG_SZ /d "cmd.exe /c powershell -ep unrestricted -nop -c \"Set-CimInstance -Query 'Select * from Win32_UserAccount WHERE SID LIKE ''S-1-5-21-%%-500''' -Property @{Disabled=0}\" &exit /b 0 "
%_Nul3% reg.exe unload HKLM\SYS
)
if /i %EditionID%==IoTEnterpriseS (
%_dism1% /Image:"%_mount%" /LogPath:"%_dLog%\DismVirtualEditions.log" /Set-ProductKey:%OEMKey%
)
call :wds_rem
%_dism1% /Commit-Image /MountDir:"%_mount%" /Append %_Supp%
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 (
call :dk_color1 %Red% "Could not save the edition image." 4
(echo.&echo Could not save the edition image.)>>"!logerr!"
exit /b
)
set /a index+=1
if %_exDism% equ 0 (
set "_Nul7="
echo.
)
%_Nul7% wimlib-imagex.exe info ISOFOLDER\sources\%WimFile% %index% "%winver% %desc%" "%winver% %desc%" --image-property FLAGS=%EditionID% --image-property DISPLAYNAME="%winver% %desc%" --image-property DISPLAYDESCRIPTION="%winver% %desc%"
set modded=1
exit /b

:doMount
if defined _term exit /b
if %_exDism% equ 1 exit /b
call :dk_color1 %Blue% "=== Mounting Source Index: %1" %_preMount%
set _preMount=4
if exist "%_mount%\" rmdir /s /q "%_mount%\"
if not exist "%_mount%\" mkdir "%_mount%"
%_dism1% /Mount-Wim /Wimfile:ISOFOLDER\sources\%WimFile% /Index:%1 /MountDir:"%_mount%" %_Supp%
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 (
call :discard
set "MESSAGE=Could not mount the image"&goto :E_MSG
)
exit /b

:doUnmount
if defined _term exit /b
if %_exDism% equ 1 exit /b
call :dk_color1 %Blue% "=== Unmounting Source Index: %1" 4
%_dism1% /Unmount-Wim /MountDir:"%_mount%" /Discard %_Supp%
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 (
call :discard
set "MESSAGE=Could not unmount the image"&goto :E_MSG
)
rmdir /s /q "%_mount%\"
exit /b

:discard
%_dism1% /Image:"%_mount%" /Get-Packages %_Null%
%_dism1% /Unmount-Wim /MountDir:"%_mount%" /Discard %_Supp%
%_dism1% /Cleanup-Mountpoints %_Nul3%
%_dism1% /Cleanup-Wim %_Nul3%
if exist "%_mount%\" rmdir /s /q "%_mount%\"
set _term=1
exit /b

:wds_add
if %_build% geq 29550 if %winbuild% lss 20348 if /i not %xOS%==x86 (
if /i %arch%==%xOS% copy /y %SysPath%\wdscore.dll "%_mount%\Windows\System32\downlevel\" %_Nul1%
if /i %arch%==x64 if /i %xOS%==amd64 copy /y %SysPath%\wdscore.dll "%_mount%\Windows\System32\downlevel\" %_Nul1%
if exist "%SystemRoot%\SysWOW64\wdscore.dll" if exist "%_mount%\Windows\SysWOW64\downlevel\*.dll" copy /y %SystemRoot%\SysWOW64\wdscore.dll "%_mount%\Windows\SysWOW64\downlevel\" %_Nul1%
)
exit /b

:wds_rem
if exist "%_mount%\Windows\System32\downlevel\wdscore.dll" del /f /q "%_mount%\Windows\System32\downlevel\wdscore.dll" %_Nul3%
if exist "%_mount%\Windows\SysWOW64\downlevel\wdscore.dll" del /f /q "%_mount%\Windows\SysWOW64\downlevel\wdscore.dll" %_Nul3%
exit /b

:ISOCREATE
for /f "tokens=3 delims=: " %%# in ('imagex /info ISOFOLDER\sources\%WimFile% ^|findstr /i /b /c:"Image Count"') do set finalimages=%%#
if %finalimages% gtr 1 if not exist "ei.cfg" if not exist "UUPs\ei.cfg" if exist ISOFOLDER\sources\ei.cfg del /f /q ISOFOLDER\sources\ei.cfg

call :dk_color1 %Blue% "=== Deleting Source Edition{s} . . ." 4 5
call :dDelete EnterpriseS
call :dPREPARE

call :dk_color1 %Blue% "=== Rebuilding %WimFile% . . ." 4 5
%_wrb% wimlib-imagex.exe optimize ISOFOLDER\sources\%WimFile% %_Supp%

call :SET_DYNAMIC_DVDISO
call :dk_color1 %Blue% "=== Creating ISO . . ." 4
if defined _exTime set isotime=%_exTime%
if /i not %arch%==arm64 (
cdimage.exe -bootdata:2#p0,e,b"ISOFOLDER\boot\etfsboot.com"#pEF,e,b"ISOFOLDER\efi\Microsoft\boot\efisys.bin" -o -m -u2 -udfver102 -t%isotime% -l%DVDLABEL% ISOFOLDER %DVDISO%.iso
) else (
cdimage.exe -bootdata:1#pEF,e,b"ISOFOLDER\efi\Microsoft\boot\efisys.bin" -o -m -u2 -udfver102 -t%isotime% -l%DVDLABEL% ISOFOLDER %DVDISO%.iso
)
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 goto :E_ISO
set qmsg=Finished.
goto :QUIT

:dDelete
for /f "tokens=3 delims=: " %%# in ('imagex /info ISOFOLDER\sources\%WimFile% ^|findstr /i /b /c:"Image Count"') do set dimages=%%#
for /l %%# in (1,1,%dimages%) do imagex /info ISOFOLDER\sources\%WimFile% %%# >bin\info%%#.txt 2>&1
for /L %%# in (1,1,%dimages%) do (
find /i "<EDITIONID>%1</EDITIONID>" bin\info%%#.txt %_Nul3% && (
  echo %1
  rem %_dism1% /Delete-Image /ImageFile:ISOFOLDER\sources\%WimFile% /Index:%%#
  wimlib-imagex.exe delete ISOFOLDER\sources\%WimFile% %%# --soft %_Nul3%
  )
)
del /f /q bin\info*.txt %_Nul3%
exit /b



:dInfo
if exist "%ISOdir%\sources\install.wim" (set WimFile=install.wim) else (set WimFile=install.esd)
wimlib-imagex.exe info "%ISOdir%\sources\%WimFile%" 1 %_Nul3%
set ERRTEMP=%ERRORLEVEL%
if %ERRTEMP% neq 0 (
%_err%
echo Could not execute wimlib-imagex.exe
echo Use simple work path without special characters
echo.
(echo.&echo Could not execute wimlib-imagex.exe)>>"!logerr!"
goto :QUIT
)
imagex /info "%ISOdir%\sources\%WimFile%">bin\infoall.txt 2>&1
for /f "tokens=3 delims=: " %%# in ('findstr /i /b /c:"Image Count" bin\infoall.txt') do set images=%%#
for /l %%# in (1,1,%images%) do imagex /info "%ISOdir%\sources\%WimFile%" %%# >bin\info%%#.txt 2>&1
for /f "tokens=3 delims=<>" %%# in ('find /i "<BUILD>" bin\info1.txt') do set _build=%%#
for /f "tokens=3 delims=<>" %%# in ('find /i "<DEFAULT>" bin\info1.txt') do set "langid=%%#"
for /f "tokens=3 delims=<>" %%# in ('find /i "<ARCH>" bin\info1.txt') do (if %%# equ 0 (set "arch=x86") else if %%# equ 9 (set "arch=x64") else (set "arch=arm64"))
set EditionLTSC=0
find /i "<EDITIONID>EnterpriseS</EDITIONID>" bin\infoall.txt %_Nul1% && (set EditionLTSC=1)
if %EditionLTSC% equ 0 (
if %_iso% equ 1 rmdir /s /q "%ISOdir%\"
set "MESSAGE=No LTSC source edition detected (EnterpriseS)"&goto :E_MSG
)

:sharedINF
for /L %%# in (1,1,%images%) do (
if %EditionLTSC% equ 1 (find /i "<EDITIONID>EnterpriseS</EDITIONID>" bin\info%%#.txt %_Nul3% && (set IndexLTSC=%%#))
)
set "wtxLTSC=Windows 10"
if %EditionLTSC% equ 1 (
find /i "<NAME>" bin\info%IndexLTSC%.txt %_Nul2% | find /i "Windows 11" %_Nul1% && (set "wtxLTSC=Windows 11")
find /i "<NAME>" bin\info%IndexLTSC%.txt %_Nul2% | find /i "Windows 12" %_Nul1% && (set "wtxLTSC=Windows 12")
)
for /l %%# in (1,1,%images%) do del /f /q bin\info%%#.txt %_Nul3%
if defined _shortINF goto :eof
if %_build% lss 19041 (
if %_iso% equ 1 rmdir /s /q "%ISOdir%\"
set "MESSAGE=ISO build %_build% is not supported for IoTEnterpriseS"&goto :E_MSG
)
if %EditionLTSC% equ 1 if %_build% geq 19041 set /a _sum+=1
if %EditionLTSC% equ 1 if %_build% geq 25193 set /a _sum+=1
wimlib-imagex.exe extract "%ISOdir%\sources\boot.wim" 2 sources\setuphost.exe --dest-dir=.\bin\temp --no-acls --no-attributes %_Null%
7z.exe l .\bin\temp\setuphost.exe >.\bin\temp\version.txt 2>&1
for /f "tokens=4-7 delims=.() " %%i in ('"findstr /i /b "FileVersion" .\bin\temp\version.txt" %_Nul6%') do (set uupver=%%i.%%j&set uupmaj=%%i&set uupmin=%%j&set branch=%%k&set uupdate=%%l)
set revver=%uupver%&set revmaj=%uupmaj%&set revmin=%uupmin%
set "tok=6,7"&set "toe=5,6,7"
if /i %arch%==x86 (set _ss=x86) else if /i %arch%==x64 (set _ss=amd64) else (set _ss=arm64)
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\WinSxS\Manifests\%_ss%_microsoft-windows-coreos-revision*.manifest --dest-dir=.\bin\temp --no-acls --no-attributes %_Nul3%
if exist "bin\temp\*_microsoft-windows-coreos-revision*.manifest" for /f "tokens=%tok% delims=_." %%A in ('dir /b /a:-d /od .\bin\temp\*_microsoft-windows-coreos-revision*.manifest') do set revver=%%A.%%B&set revmaj=%%A&set revmin=%%B
if %_build% geq 15063 (
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\System32\config\SOFTWARE --dest-dir=.\bin\temp --no-acls --no-attributes %_Null%
set "isokey=Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed"
for /f %%i in ('"offlinereg.exe .\bin\temp\SOFTWARE "!isokey!" enumkeys %_Nul6% ^| findstr /i /r "Client\.OS Server\.OS""') do if not errorlevel 1 (
  for /f "tokens=3 delims==:" %%A in ('"offlinereg.exe .\bin\temp\SOFTWARE "!isokey!\%%i" getvalue Branch %_Nul6%"') do set "revbranch=%%~A"
  for /f "tokens=5,6 delims==:." %%A in ('"offlinereg.exe .\bin\temp\SOFTWARE "!isokey!\%%i" getvalue Version %_Nul6%"') do if %%A gtr !revmaj! (
    set "revver=%%~A.%%B
    set revmaj=%%~A
    set "revmin=%%B
    )
  )
)
set chkmin=%revmin%
call :setuphostprep
for /f "tokens=4-7 delims=.() " %%i in ('"findstr /i /b "FileVersion" .\bin\version.txt" %_Nul6%') do (set uupver=%%i.%%j&set uupmaj=%%i&set uupmin=%%j&set branch=%%k&set uupdate=%%l)
del /f /q .\bin\version.txt %_Nul3%
set "isotime=!uupdate:~2,2!/!uupdate:~4,2!/20!uupdate:~0,2!,!uupdate:~7,2!:!uupdate:~9,2!:10"
if defined revbranch set branch=%revbranch%
if %revmaj%==18363 (
if /i "%branch:~0,4%"=="19h1" set branch=19h2%branch:~4%
if %uupver:~0,5%==18362 set uupver=18363%uupver:~5%
)
if %revmaj%==19042 (
if /i "%branch:~0,2%"=="vb" set branch=20h2%branch:~2%
if %uupver:~0,5%==19041 set uupver=19042%uupver:~5%
)
if %revmaj%==19043 (
if /i "%branch:~0,2%"=="vb" set branch=21h1%branch:~2%
if %uupver:~0,5%==19041 set uupver=19043%uupver:~5%
)
if %revmaj%==19044 (
if /i "%branch:~0,2%"=="vb" set branch=21h2%branch:~2%
if %uupver:~0,5%==19041 set uupver=19044%uupver:~5%
)
if %revmaj%==19045 (
if /i "%branch:~0,2%"=="vb" set branch=22h2%branch:~2%
if %uupver:~0,5%==19041 set uupver=19045%uupver:~5%
)
if %revmaj% geq %_build% if %_build% geq 21382 (
if %uupver:~0,5%==%_build% set uupver=%revmaj%%uupver:~5%
)
if %revmaj%==22631 (
if /i "%branch:~0,2%"=="ni" (echo %branch% | find /i "beta" %_Nul1% || set branch=23h2_ni%branch:~2%)
if %uupver:~0,5%==22621 set uupver=22631%uupver:~5%
)
if %revmaj%==22635 (
if %uupver:~0,5%==22621 set uupver=22635%uupver:~5%
)
if %revmaj%==26200 (
if /i "%branch:~0,2%"=="ge" (echo %branch% | findstr /i /r "beta prerelease" %_Nul1% || set branch=25h2_ge%branch:~2%)
if %uupver:~0,5%==26100 set uupver=26200%uupver:~5%
)
if %uupmin% lss %revmin% (
set uupver=%revver%
set uupmin=%revmin%
if not exist "%SystemRoot%\temp\" mkdir "%SystemRoot%\temp" %_Nul3%
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\Servicing\Packages\Package_for_RollupFix*.mum --dest-dir=.\bin\temp --no-acls --no-attributes %_Nul3%
for /f %%# in ('dir /b /a:-d /od bin\temp\Package_for_RollupFix*.mum') do copy /y "bin\temp\%%#" %SystemRoot%\temp\update.mum %_Nul1%
call :datemum uupdate isotime
)
if %uupmin% gtr %revmin% (
if not exist "%SystemRoot%\temp\" mkdir "%SystemRoot%\temp" %_Nul3%
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\servicing\Packages\Package_for_RollupFix*.mum --dest-dir=%SystemRoot%\temp --no-acls --no-attributes %_Nul3%
if not exist "%SystemRoot%\temp\Package_for_RollupFix*.mum" set branch=WinBuild
)
set _legacy=
set _useold=0
if /i "%branch%"=="WinBuild" set _useold=1
if /i "%branch%"=="GitEnlistment" set _useold=1
if /i "%uupdate%"=="winpbld" set _useold=1
if %_useold% equ 1 (
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\System32\config\SOFTWARE --dest-dir=.\bin\temp --no-acls --no-attributes %_Null%
for /f "tokens=3 delims==:" %%# in ('"offlinereg.exe .\bin\temp\SOFTWARE "Microsoft\Windows NT\CurrentVersion" getvalue BuildLabEx" %_Nul6%') do if not errorlevel 1 (for /f "tokens=1-5 delims=." %%i in ('echo %%~#') do set _legacy=%%i.%%j.%%m.%%l&set branch=%%l)
)
if defined _legacy (set _label=%_legacy%) else (set _label=%uupver%.%uupdate%.%branch%)
rmdir /s /q bin\temp\
set _label=%_label%_CLIENT
for %%# in (A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z) do (
set _label=!_label:%%#=%%#!
set branch=!branch:%%#=%%#!
set langid=!langid:%%#=%%#!
)
if /i %arch%==x86 set archl=X86
if /i %arch%==x64 set archl=X64
if /i %arch%==arm64 set archl=A64
set _ddv=DV5
if %_build% geq 22621 set _ddv=DV9
set "DVDLABEL=CCSA_%archl%FRE_%langid%_%_ddv%"
if defined _exLabel set _label=%_exLabel%
set "DVDISO=%_label%MULTI_%archl%FRE_%langid%"
set "_edtn=MULTI"
call :SET_DYNAMIC_DVDISO
if exist "%DVDISO%.ISO" set "DVDISO=%DVDISO%_%random%"
goto :PROCESS_ISO

:dPREPARE
for /f "tokens=3 delims=: " %%# in ('imagex /info ISOFOLDER\sources\%WimFile% ^|findstr /i /b /c:"Image Count"') do set finalimages=%%#
if %finalimages% gtr 1 exit /b
set _VL=1
set DVDLABEL=IOTES_%archl%FRE_%langid%_DV5
set DVDISO=%_label%IOTENTERPRISES_OEMRET_%archl%FRE_%langid%
set "_edtn=IoTEnterpriseS"
call :SET_DYNAMIC_DVDISO
if exist "!_UUP!\ei.cfg" (copy /y "!_UUP!\ei.cfg" ISOFOLDER\sources\ei.cfg %_Nul3%) else if exist "ei.cfg" (copy /y "ei.cfg" ISOFOLDER\sources\ei.cfg %_Nul3%)
exit /b

:datemum
set "mumfile=%SystemRoot%\temp\update.mum"
set "chkfile=!mumfile:\=\\!"
if %_cwmi% equ 1 for /f "tokens=2 delims==" %%# in ('wmic datafile where "name='!chkfile!'" get LastModified /value') do set "mumdate=%%#"
if %_cwmi% equ 0 for /f %%# in ('%_psc% "([WMI]'CIM_DataFile.Name=''!chkfile!''').LastModified"') do set "mumdate=%%#"
del /f /q %SystemRoot%\temp\*.mum
set "%1=!mumdate:~2,2!!mumdate:~4,2!!mumdate:~6,2!-!mumdate:~8,4!"
set "%2=!mumdate:~4,2!/!mumdate:~6,2!/!mumdate:~0,4!,!mumdate:~8,2!:!mumdate:~10,2!:!mumdate:~12,2!"
exit /b

:setuphostprep
wimlib-imagex.exe extract "%ISOdir%\sources\boot.wim" 2 sources\setuphost.exe --dest-dir=%SystemRoot%\temp --no-acls --no-attributes %_Null%
wimlib-imagex.exe extract "%ISOdir%\sources\boot.wim" 2 sources\setupprep.exe --dest-dir=%SystemRoot%\temp --no-acls --no-attributes %_Null%
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\system32\UpdateAgent.dll --dest-dir=%SystemRoot%\temp --no-acls --no-attributes %_Null%
wimlib-imagex.exe extract "%ISOdir%\sources\%WimFile%" 1 Windows\system32\Facilitator.dll --dest-dir=%SystemRoot%\temp --no-acls --no-attributes %_Null%
set _svr1=0&set _svr2=0&set _svr3=0&set _svr4=0
set "_fvr1=%SystemRoot%\temp\UpdateAgent.dll"
set "_fvr2=%SystemRoot%\temp\setupprep.exe"
set "_fvr3=%SystemRoot%\temp\setuphost.exe"
set "_fvr4=%SystemRoot%\temp\Facilitator.dll"
set "cfvr1=!_fvr1:\=\\!"
set "cfvr2=!_fvr2:\=\\!"
set "cfvr3=!_fvr3:\=\\!"
set "cfvr4=!_fvr4:\=\\!"
if %_cwmi% equ 1 (
if exist "!_fvr1!" for /f "tokens=5 delims==." %%a in ('wmic datafile where "name='!cfvr1!'" get Version /value ^| find "="') do set /a "_svr1=%%a"
if exist "!_fvr2!" for /f "tokens=5 delims==." %%a in ('wmic datafile where "name='!cfvr2!'" get Version /value ^| find "="') do set /a "_svr2=%%a"
if exist "!_fvr3!" for /f "tokens=5 delims==." %%a in ('wmic datafile where "name='!cfvr3!'" get Version /value ^| find "="') do set /a "_svr3=%%a"
if exist "!_fvr4!" for /f "tokens=5 delims==." %%a in ('wmic datafile where "name='!cfvr4!'" get Version /value ^| find "="') do set /a "_svr4=%%a"
)
if %_cwmi% equ 0 (
if exist "!_fvr1!" for /f "tokens=4 delims=." %%a in ('%_psc% "([WMI]'CIM_DataFile.Name=''!cfvr1!''').Version"') do set /a "_svr1=%%a"
if exist "!_fvr2!" for /f "tokens=4 delims=." %%a in ('%_psc% "([WMI]'CIM_DataFile.Name=''!cfvr2!''').Version"') do set /a "_svr2=%%a"
if exist "!_fvr3!" for /f "tokens=4 delims=." %%a in ('%_psc% "([WMI]'CIM_DataFile.Name=''!cfvr3!''').Version"') do set /a "_svr3=%%a"
if exist "!_fvr4!" for /f "tokens=4 delims=." %%a in ('%_psc% "([WMI]'CIM_DataFile.Name=''!cfvr4!''').Version"') do set /a "_svr4=%%a"
)
set "_chk=!_fvr1!"
if %chkmin% equ %_svr1% set "_chk=!_fvr1!"&goto :prephostsetup
if %chkmin% equ %_svr2% set "_chk=!_fvr2!"&goto :prephostsetup
if %chkmin% equ %_svr3% set "_chk=!_fvr3!"&goto :prephostsetup
if %chkmin% equ %_svr4% set "_chk=!_fvr4!"&goto :prephostsetup
if %_svr2% gtr %_svr1% (
if %_svr2% gtr %_svr3% if %_svr2% gtr %_svr4% set "_chk=!_fvr2!"
if %_svr3% gtr %_svr2% if %_svr3% gtr %_svr4% set "_chk=!_fvr3!"
if %_svr4% gtr %_svr2% if %_svr4% gtr %_svr3% set "_chk=!_fvr4!"
)
if %_svr3% gtr %_svr1% (
if %_svr2% gtr %_svr3% if %_svr2% gtr %_svr4% set "_chk=!_fvr2!"
if %_svr3% gtr %_svr2% if %_svr3% gtr %_svr4% set "_chk=!_fvr3!"
if %_svr4% gtr %_svr2% if %_svr4% gtr %_svr3% set "_chk=!_fvr4!"
)
if %_svr4% gtr %_svr1% (
if %_svr2% gtr %_svr3% if %_svr2% gtr %_svr4% set "_chk=!_fvr2!"
if %_svr3% gtr %_svr2% if %_svr3% gtr %_svr4% set "_chk=!_fvr3!"
if %_svr4% gtr %_svr2% if %_svr4% gtr %_svr3% set "_chk=!_fvr4!"
)

:prephostsetup
7z.exe l "%_chk%" >.\bin\version.txt 2>&1
del /f /q "!_fvr1!" "!_fvr2!" "!_fvr3!" "!_fvr4!" %_Nul3%
exit /b

:checkadk
set _dism1=dism.exe /English
set _dism2=dism.exe /English /ScratchDir
set _ADK=0
set regKeyPathFound=1
set wowRegKeyPathFound=1
reg.exe query "HKLM\Software\Wow6432Node\Microsoft\Windows Kits\Installed Roots" /v KitsRoot10 %_Nul3% || set wowRegKeyPathFound=0
reg.exe query "HKLM\Software\Microsoft\Windows Kits\Installed Roots" /v KitsRoot10 %_Nul3% || set regKeyPathFound=0
if %wowRegKeyPathFound% equ 0 (
  if %regKeyPathFound% equ 0 (
    goto :eof
  ) else (
    set regKeyPath=HKLM\Software\Microsoft\Windows Kits\Installed Roots
  )
) else (
    set regKeyPath=HKLM\Software\Wow6432Node\Microsoft\Windows Kits\Installed Roots
)
for /f "skip=2 tokens=2*" %%i in ('reg.exe query "%regKeyPath%" /v KitsRoot10') do set "KitsRoot=%%j"
set "DandIRoot=%KitsRoot%Assessment and Deployment Kit\Deployment Tools"
if exist "%DandIRoot%\%xOS%\DISM\dism.exe" (
set _ADK=1
set "Path=%xDS%;%DandIRoot%\%xOS%\DISM;%SysPath%;%SystemRoot%;%SysPath%\Wbem;%SysPath%\WindowsPowerShell\v1.0\"
)
goto :eof

:pr_color
set _NCS=1
if %winbuild% LSS 10586 set _NCS=0
if %winbuild% GEQ 10586 reg.exe query HKCU\Console /v ForceV2 2>nul | find /i "0x0" %_Null% && (set _NCS=0)

if %_NCS% EQU 1 (
for /F %%a in ('echo prompt $E ^| cmd.exe') do set "_esc=%%a"
set     "Red="41;97m" "pad""
set    "Gray="100;97m" "pad""
set   "Green="42;97m" "pad""
set    "Blue="44;97m" "pad""
set  "_White="40;37m" "pad""
set  "_Green="40;92m" "pad""
set "_Yellow="40;93m" "pad""
) else (
set     "Red="Red" "white""
set    "Gray="DarkGray" "white""
set   "Green="DarkGreen" "white""
set    "Blue="Blue" "white""
set  "_White="Black" "Gray""
set  "_Green="Black" "Green""
set "_Yellow="Black" "Yellow""
)

set "_err=echo: &call :dk_color1 %Red% "==== ERROR ====" &echo:"
exit /b

:dk_color1
if /i "%_Exit%"=="rem." (
echo %~3
exit /b
)
if not "%4"=="" if "%4"=="4" echo:
if %_NCS% EQU 1 (
echo %_esc%[%~1%~3%_esc%[0m
) else if %_pwsh% EQU 1 (
%_psc% write-host -back '%1' -fore '%2' '%3'
) else (
echo %~3
)
if not "%5"=="" echo:
exit /b

:dk_color2
if /i "%_Exit%"=="rem." (
echo %~3 %~6
exit /b
)
if not "%7"=="" if "%7"=="7" echo:
if %_NCS% EQU 1 (
echo %_esc%[%~1%~3%_esc%[%~4%~6%_esc%[0m
) else if %_pwsh% EQU 1 (
%_psc% write-host -back '%1' -fore '%2' '%3' -NoNewline; write-host -back '%4' -fore '%5' '%6'
) else (
echo %~3 %~6
)
if not "%8"=="" echo:
exit /b

:checkQE
if not defined qerel reg.exe query HKCU\Console /v QuickEdit 2>nul | find /i "0x0" >nul || (
call :dk_color1 %Red% "### WARNING ###"
echo.
echo Console "Quick Edit Mode" is active.
echo Do not left-click with the mouse cursor inside the console window,
echo or else the operation execution will hang until a key is pressed.
echo.
set _preMount=4
)
exit /b

:E_Admin
%_err%
echo This script require administrator privileges.
echo To do so, right click on this script and select 'Run as administrator'
goto :E_Exit

:E_PWS
%_err%
echo Windows PowerShell is not detected or not working correctly.
echo It is required for this script to work.
goto :E_Exit

:E_Exit
if %_Debug% neq 0 exit /b
echo.
echo Press any key to exit.
pause >nul
exit /b

:E_Bin
%_err%
echo Required file %_bin% is missing.
echo.
goto :QUIT

:E_MSG
:: @color 47
if %_build% geq 19041 if %winbuild% lss 17133 if exist "%SysPath%\ext-ms-win-security-slc-l1-1-0.dll" (
del /f /q %SysPath%\ext-ms-win-security-slc-l1-1-0.dll %_Nul3%
if /i not %xOS%==x86 del /f /q %SystemRoot%\SysWOW64\ext-ms-win-security-slc-l1-1-0.dll %_Nul3%
)
if exist "ISOFOLDER\sources\*.exe" ren ISOFOLDER %DVDISO% %_Nul3%
%_err%
echo %MESSAGE%
echo.
(echo.&echo %MESSAGE%)>>"!logerr!"
goto :QUIT

:E_None
:: @color 0F
if %_exDism% equ 1 exit /b
if %UseDism% neq 1 if exist ISOFOLDER\sources\temp.wim del /f /q ISOFOLDER\sources\temp.wim
call :dPREPARE
ren ISOFOLDER %DVDISO%
if %modded% equ 0 (
echo.
echo All chosen editions already exists in the source
)
call :dk_color1 %Gray% "No operation performed." 4 5
goto :QUIT

:E_ISO
:: @color 17
ren ISOFOLDER %DVDISO%
call :dk_color1 %Red% "Errors were reported during ISO creation." 4 5
(echo.&echo Errors were reported during ISO creation.)>>"!logerr!"
goto :QUIT

:QUIT
if exist ISOFOLDER\ rmdir /s /q ISOFOLDER\
if exist bin\temp\ rmdir /s /q bin\temp\
if exist bin\infoall.txt del /f /q bin\infoall.txt
popd
if %_Debug% neq 0 exit /b
if defined qmsg call :dk_color1 %Green% "%qmsg%" 4
call :dk_color1 %_Yellow% "Press 0 or q to exit."
choice /c 0Q /n
if errorlevel 1 (exit /b) else (rem.)

:SET_DYNAMIC_DVDISO
set "_winver=Win10"
set "_chk_b=!_build!"
if "!_chk_b!"=="" set "_chk_b=%_build%"
if "!_chk_b!"=="" if defined uupver for /f "tokens=1 delims=." %%a in ("!uupver!") do set "_chk_b=%%a"
if "!_chk_b!"=="" if defined isover for /f "tokens=1 delims=." %%a in ("!isover!") do set "_chk_b=%%a"

if not "!_chk_b!"=="" (
    if !_chk_b! geq 22000 set "_winver=Win11"
)

set "_winh2="
if "!_chk_b!"=="26200" set "_winh2=25H2"
if "!_chk_b!"=="26100" set "_winh2=24H2"
if "!_chk_b!"=="22631" set "_winh2=23H2"
if "!_chk_b!"=="22621" set "_winh2=22H2"
if "!_chk_b!"=="22000" set "_winh2=21H2"
if "!_chk_b!"=="19045" set "_winh2=22H2"
if "!_chk_b!"=="19044" set "_winh2=21H2"
if "!_chk_b!"=="19043" set "_winh2=21H1"
if "!_chk_b!"=="19042" set "_winh2=20H2"
if "!_chk_b!"=="19041" set "_winh2=2004"
if "!_chk_b!"=="17763" set "_winh2=1809"
if "!_chk_b!"=="14393" set "_winh2=1607"
if not defined _winh2 set "_winh2=!_chk_b!"

set "_uupv=!uupver!"
if "!_uupv!"=="" set "_uupv=!isover!"
set "_winrev="
if not "!_uupv!"=="" for /f "tokens=2 delims=." %%a in ("!_uupv!") do set "_winrev=%%a"
if "!_winrev!"=="" set "_winrev=!_chk_b!"

set "_winedt=!_edtn!"
if "!_winedt!"=="" set "_winedt=!editionid!"
if "!_winedt!"=="" set "_winedt=IoTEnterpriseS"

set "_winlang=!langid!"
if "!_winlang!"=="" set "_winlang=!_mui!"
if "!_winlang!"=="" set "_winlang=es-mx"
for %%# in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do set "_winlang=!_winlang:%%#=%%#!"

set "DVDISO=!_winver!_!_winh2!_!_winedt!_!_winrev!_!_winlang!"
exit /b

----- Begin wsf script --->
<package>
   <job id="ELAV">
      <script language="VBScript">
         Set strArg=WScript.Arguments.Named
         Set strRdlproc = CreateObject("WScript.Shell").Exec("rundll32 kernel32,Sleep")
         With GetObject("winmgmts:\\.\root\CIMV2:Win32_Process.Handle='" & strRdlproc.ProcessId & "'")
            With GetObject("winmgmts:\\.\root\CIMV2:Win32_Process.Handle='" & .ParentProcessId & "'")
               If InStr (.CommandLine, WScript.ScriptName) <> 0 Then
                  strLine = Mid(.CommandLine, InStr(.CommandLine , "/File:") + Len(strArg("File")) + 8)
               End If
            End With
            .Terminate
         End With
         CreateObject("Shell.Application").ShellExecute "cmd.exe", "/c " & chr(34) & chr(34) & strArg("File") & chr(34) & strLine & chr(34), "", "runas", 1
      </script>
   </job>
</package>
