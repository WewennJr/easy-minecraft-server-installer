@echo off
setlocal EnableExtensions

if /i "%~1"=="--mc-installer-child" goto :run

cmd /c ""%~f0" --mc-installer-child"
set "RC=%errorlevel%"
if not "%RC%"=="0" pause
exit /b %RC%

:run
title Easy Minecraft Server Installer

rem Easy Minecraft Server Installer
rem Creates a ready-to-run Minecraft server (vanilla, Fabric, Forge, NeoForge)
rem by downloading the correct files from official sources and preparing the folder.

set "APP_NAME=Easy Minecraft Server Installer"
set "APP_VERSION=1.3"

set "VERSIONS=26.3 26.2 26.1.2 26.1.1 26.1 1.21.11 1.21.10 1.21.9 1.21.8 1.21.7 1.21.6 1.21.5 1.21.4 1.21.3 1.21.2 1.21.1 1.21 1.20.6 1.20.5 1.20.4 1.20.3 1.20.2 1.20.1 1.20 1.19.4 1.19.3 1.19.2 1.19.1 1.19 1.18.2 1.18.1 1.18 1.17.1 1.17 1.16.5 1.16.4 1.16.3 1.16.2 1.16.1 1.16 1.8.9"

set "MANIFEST_URL=https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
set "FORGE_PROMOS_URL=https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
set "FABRIC_LOADER_URL=https://meta.fabricmc.net/v2/versions/loader"
set "FABRIC_INSTALLER_URL=https://meta.fabricmc.net/v2/versions/installer"
set "NEOFORGE_MAVEN=https://maven.neoforged.net/releases/net/neoforged"
set "ADOPTIUM_ASSETS_URL=https://api.adoptium.net/v3/assets/latest"

set "NAME="
set "VERSION="
set "LOADER="
set "RAM_GB="
set "JAR_NAME="
set "JAR_URL="
set "JAR_SHA1="
set "JAR_SIZE=0"
set "LOADER_DETAIL="
set "JAVA_REQUIRED="
set "MC_META="
set "SERVER_DIR="
set "JAVA_MODE=system"
set "JAVA_BIN=java"
set "JAVA_DETAIL="
set "SYS_JAVA_MAJOR="
set "JDK_FEATURE="
set "LOCAL_JAVA_HOME="
set "PS_OUT="
set "PS_EXPR="

where curl.exe >nul 2>&1
if errorlevel 1 call :die "curl.exe is required but was not found."
where powershell.exe >nul 2>&1
if errorlevel 1 call :die "powershell.exe is required but was not found."

set "TMP_DIR=%TEMP%\mc-installer-%RANDOM%-%RANDOM%"
mkdir "%TMP_DIR%" >nul 2>&1
if errorlevel 1 call :die "Could not create a temporary directory."

goto :main

:main
call :print_banner
call :ask_name
call :ask_version
call :ask_loader
call :ask_memory
call :resolve_jar
call :assess_java
call :print_summary
call :confirm
if errorlevel 1 call :cancel

mkdir "%SERVER_DIR%" >nul 2>&1
if errorlevel 1 call :die "Could not create the server folder."
cd /d "%SERVER_DIR%"
if errorlevel 1 call :die "Could not enter the server folder."

if "%JAVA_MODE%"=="local" call :download_local_jdk

call :section "Downloading server"
echo File: %JAR_NAME%
curl.exe -fL --retry 3 --progress-bar -o "%JAR_NAME%" "%JAR_URL%"
if errorlevel 1 call :die "Download failed."
if not exist "%JAR_NAME%" call :die "The downloaded file is empty."
for %%A in ("%JAR_NAME%") do set "JAR_SIZE=%%~zA"
if %JAR_SIZE% LEQ 0 call :die "The downloaded file is empty."

if not defined JAR_SHA1 goto :main_after_sha1
set "FILE=%CD%\%JAR_NAME%"
set "PS_EXPR=(Get-FileHash -Algorithm SHA1 -LiteralPath $env:FILE).Hash.ToLower()"
call :ps_run
if not defined PS_OUT (
  call :warn "Could not compute SHA-1; skipping verification."
  goto :main_after_sha1
)
if /i not "%PS_OUT%"=="%JAR_SHA1%" (
  del /f /q "%JAR_NAME%" >nul 2>&1
  call :die "Invalid SHA-1 checksum for the downloaded file."
)
call :ok "SHA-1 checksum verified."

:main_after_sha1
if "%LOADER%"=="forge" goto :main_install_forge
if "%LOADER%"=="neoforge" goto :main_install_forge
call :write_run_bat
if not exist "run.bat" call :die "Could not create run.bat."
> eula.txt echo eula=true
if not exist "eula.txt" call :die "Could not create eula.txt."
goto :main_done

:main_install_forge
call :section "Installing server (%LOADER%)"
"%JAVA_BIN%" -jar "%JAR_NAME%" --installServer
if errorlevel 1 call :die "Server installation failed."
call :apply_forge_memory
> eula.txt echo eula=true
if not exist "eula.txt" call :die "Could not create eula.txt."
call :wrap_forge_run_script

:main_done
echo.
echo Server ready in "%SERVER_DIR%"
echo   Start: cd /d "%SERVER_DIR%" ^&^& run.bat
goto :cleanup_ok

:print_banner
echo.
echo %APP_NAME% v%APP_VERSION%
echo Create a Minecraft server in a few steps.
goto :eof

:section
echo.
echo === %~1 ===
goto :eof

:ok
echo %~1
goto :eof

:warn
>&2 echo Warning: %~1
goto :eof

:die
>&2 echo Error: %~1
goto :cleanup_fail

:cancel
echo Cancelled.
goto :cleanup_ok

:ps_run
set "PS_OUT="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "Invoke-Expression $env:PS_EXPR"`) do (
  if not defined PS_OUT set "PS_OUT=%%A"
)
goto :eof

:ps_match
powershell -NoProfile -Command "if ([Environment]::GetEnvironmentVariable($env:PS_NAME) -match $env:PS_PATTERN) { exit 0 } else { exit 1 }"
exit /b %errorlevel%

:ps_in_list
powershell -NoProfile -Command "if (($env:PS_LIST -split ' ') -contains [Environment]::GetEnvironmentVariable($env:PS_NAME)) { exit 0 } else { exit 1 }"
exit /b %errorlevel%

:ps_yes
powershell -NoProfile -Command "if ($env:ANSWER -imatch '^(y|yes)$') { exit 0 } else { exit 1 }"
exit /b %errorlevel%

:show_versions
echo   26.x     26.1 - 26.3
echo   1.21.x   1.21 - 1.21.11
echo   1.20.x   1.20 - 1.20.6
echo   1.19.x   1.19 - 1.19.4
echo   1.18.x   1.18 - 1.18.2
echo   1.17.x   1.17 - 1.17.1
echo   1.16.x   1.16 - 1.16.5
echo   1.8.x    1.8.9
goto :eof

:ask_name
:ask_name_loop
set "NAME="
set /p "NAME=Server name (folder name): "
if not defined NAME (
  call :warn "Invalid name."
  goto :ask_name_loop
)
set "PS_NAME=NAME"
set "PS_PATTERN=^[A-Za-z0-9._-]+$"
call :ps_match
if errorlevel 1 (
  call :warn "Use only letters, digits, '.', '_' and '-'."
  goto :ask_name_loop
)
if "%NAME%"=="." (
  call :warn "Invalid name."
  goto :ask_name_loop
)
if "%NAME%"==".." (
  call :warn "Invalid name."
  goto :ask_name_loop
)
set "SERVER_DIR=%CD%\%NAME%"
if exist "%SERVER_DIR%" (
  call :warn "Folder '.\%NAME%' already exists."
  goto :ask_name_loop
)
goto :eof

:ask_version
call :section "Game version"
echo Available versions (snapshots excluded):
call :show_versions
:ask_version_loop
set "VERSION="
set /p "VERSION=Version [26.3]: "
if not defined VERSION set "VERSION=26.3"
set "PS_NAME=VERSION"
set "PS_PATTERN=^[0-9][0-9.]*$"
call :ps_match
if errorlevel 1 (
  call :warn "Invalid version format. Use digits and dots (e.g. 1.21.1)."
  goto :ask_version_loop
)
set "PS_LIST=%VERSIONS%"
call :ps_in_list
if errorlevel 1 (
  call :warn "'%VERSION%' is not a valid release from the list."
  goto :ask_version_loop
)
call :ok "Selected version: %VERSION%"
goto :eof

:ask_loader
call :section "Mod loader"
echo   1 vanilla   official server
echo   2 fabric    lightweight mods
echo   3 forge     classic mods
echo   4 neoforge  modern Forge fork
:ask_loader_loop
set "LOADER="
set "LOADER_INPUT="
set /p "LOADER_INPUT=Mod loader [vanilla]: "
if not defined LOADER_INPUT set "LOADER_INPUT=vanilla"
set "PS_NAME=LOADER_INPUT"
set "PS_PATTERN=^(1|2|3|4|vanilla|fabric|forge|neoforge)$"
call :ps_match
if errorlevel 1 (
  call :warn "Invalid choice (1-4 or vanilla/fabric/forge/neoforge)."
  goto :ask_loader_loop
)
if /i "%LOADER_INPUT%"=="1" set "LOADER=vanilla"
if /i "%LOADER_INPUT%"=="2" set "LOADER=fabric"
if /i "%LOADER_INPUT%"=="3" set "LOADER=forge"
if /i "%LOADER_INPUT%"=="4" set "LOADER=neoforge"
if /i "%LOADER_INPUT%"=="vanilla" set "LOADER=vanilla"
if /i "%LOADER_INPUT%"=="fabric" set "LOADER=fabric"
if /i "%LOADER_INPUT%"=="forge" set "LOADER=forge"
if /i "%LOADER_INPUT%"=="neoforge" set "LOADER=neoforge"
call :ok "Selected mod loader: %LOADER%"
goto :eof

:ask_memory
call :section "Memory"
:ask_memory_loop
set "MEM_INPUT="
set /p "MEM_INPUT=Maximum memory in GB [2]: "
if not defined MEM_INPUT set "MEM_INPUT=2"
set "PS_NAME=MEM_INPUT"
set "PS_PATTERN=^[1-9][0-9]*$"
call :ps_match
if errorlevel 1 (
  call :warn "Enter a whole number of gigabytes (1 or more)."
  goto :ask_memory_loop
)
set "RAM_GB=%MEM_INPUT%"
call :ok "Maximum memory: %RAM_GB% GB"
goto :eof

:resolve_jar
call :fetch_mc_meta
if "%LOADER%"=="vanilla" call :resolve_vanilla
if "%LOADER%"=="fabric" call :resolve_fabric
if "%LOADER%"=="forge" call :resolve_forge
if "%LOADER%"=="neoforge" call :resolve_neoforge
goto :eof

:fetch_mc_meta
set "MANIFEST=%TMP_DIR%\manifest.json"
curl.exe -fsSL --retry 3 -o "%MANIFEST%" "%MANIFEST_URL%"
if errorlevel 1 call :die "Could not download the Mojang manifest."
set "JSON_FILE=%MANIFEST%"
set "MC_VERSION=%VERSION%"
set "PS_EXPR=$d=Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json; $e=$d.versions | Where-Object { $_.id -eq $env:MC_VERSION -and $_.type -eq 'release' } | Select-Object -First 1; if ($e) { $e.url }"
call :ps_run
if not defined PS_OUT call :die "Version %VERSION% was not found in the Mojang manifest."
set "MC_META=%TMP_DIR%\mc-%VERSION%.json"
curl.exe -fsSL --retry 3 -o "%MC_META%" "%PS_OUT%"
if errorlevel 1 call :die "Could not download metadata for %VERSION%."
set "JSON_FILE=%MC_META%"
set "PS_EXPR=$d=Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json; $d.javaVersion.majorVersion"
call :ps_run
set "JAVA_REQUIRED=%PS_OUT%"
goto :eof

:resolve_vanilla
set "JSON_FILE=%MC_META%"
set "PS_EXPR=$d=Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json; $d.downloads.server.url"
call :ps_run
if not defined PS_OUT call :die "Vanilla server URL not found for %VERSION%."
set "JAR_URL=%PS_OUT%"
set "PS_EXPR=$d=Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json; $s=$d.downloads.server.sha1; if ($s -match '^[0-9a-fA-F]{40}$') { $s.ToLower() }"
call :ps_run
set "JAR_SHA1=%PS_OUT%"
set "JAR_NAME=server.jar"
set "LOADER_DETAIL=Vanilla"
goto :eof

:resolve_fabric
set "LOADER_JSON=%TMP_DIR%\fabric-loader.json"
curl.exe -fsSL --retry 3 -o "%LOADER_JSON%" "%FABRIC_LOADER_URL%/%VERSION%" 2>nul
if errorlevel 1 call :die "Fabric does not support Minecraft %VERSION%."
set "JSON_FILE=%LOADER_JSON%"
set "PS_EXPR=$d=@(Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json); if ($d.Count -eq 0) { exit 1 }; $s=$d | Where-Object { $_.loader.stable } | Select-Object -First 1; if ($s) { $s.loader.version } else { ($d | Select-Object -First 1).loader.version }"
call :ps_run
if not defined PS_OUT call :die "No Fabric loader is available for Minecraft %VERSION%."
set "FABRIC_LOADER=%PS_OUT%"
set "INSTALLER_JSON=%TMP_DIR%\fabric-installer.json"
curl.exe -fsSL --retry 3 -o "%INSTALLER_JSON%" "%FABRIC_INSTALLER_URL%"
if errorlevel 1 call :die "Could not fetch the Fabric installer."
set "JSON_FILE=%INSTALLER_JSON%"
set "PS_EXPR=$d=@(Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json); if ($d.Count -eq 0) { exit 1 }; $s=$d | Where-Object { $_.stable } | Select-Object -First 1; if ($s) { $s.version } else { ($d | Select-Object -First 1).version }"
call :ps_run
if not defined PS_OUT call :die "Fabric installer version not found."
set "FABRIC_INSTALLER=%PS_OUT%"
set "JAR_URL=%FABRIC_LOADER_URL%/%VERSION%/%FABRIC_LOADER%/%FABRIC_INSTALLER%/server/jar"
set "JAR_SHA1="
set "JAR_NAME=fabric-server-mc.%VERSION%-loader.%FABRIC_LOADER%-launcher.%FABRIC_INSTALLER%.jar"
set "LOADER_DETAIL=Fabric loader %FABRIC_LOADER% (installer %FABRIC_INSTALLER%)"
goto :eof

:resolve_forge
set "PROMOS=%TMP_DIR%\forge-promos.json"
curl.exe -fsSL --retry 3 -o "%PROMOS%" "%FORGE_PROMOS_URL%"
if errorlevel 1 call :die "Could not fetch Forge versions."
set "JSON_FILE=%PROMOS%"
set "MC_VERSION=%VERSION%"
set "PS_EXPR=$d=Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json; $k=$env:MC_VERSION + '-recommended'; $v=$d.promos.$k; if (-not $v) { $k=$env:MC_VERSION + '-latest'; $v=$d.promos.$k }; $v"
call :ps_run
if not defined PS_OUT call :die "Forge has no build for Minecraft %VERSION%."
set "FORGE_VERSION=%PS_OUT%"
set "JAR_URL=https://maven.minecraftforge.net/net/minecraftforge/forge/%VERSION%-%FORGE_VERSION%/forge-%VERSION%-%FORGE_VERSION%-installer.jar"
set "JAR_NAME=forge-%VERSION%-%FORGE_VERSION%-installer.jar"
call :fetch_sha1 "%JAR_URL%"
set "LOADER_DETAIL=Forge %FORGE_VERSION%"
goto :eof

:fetch_sha1
set "JAR_SHA1="
set "SHA1_FILE=%TMP_DIR%\sha1.txt"
curl.exe -fsSL --retry 3 -o "%SHA1_FILE%" "%~1.sha1" >nul 2>&1
if errorlevel 1 goto :eof
set "PS_EXPR=$h=((Get-Content -Raw -LiteralPath $env:SHA1_FILE) -split '\s+' | Where-Object { $_ } | Select-Object -First 1); if ($h -match '^[0-9a-fA-F]{40}$') { $h.ToLower() }"
call :ps_run
if defined PS_OUT set "JAR_SHA1=%PS_OUT%"
goto :eof

:resolve_neoforge
if "%VERSION%"=="1.20.1" (
  set "ARTIFACT=forge"
  set "XML_FILE=%TMP_DIR%\neoforge-forge.xml"
  set "NEOFORGE_URL=%NEOFORGE_MAVEN%/forge/maven-metadata.xml"
) else (
  set "ARTIFACT=neoforge"
  set "XML_FILE=%TMP_DIR%\neoforge.xml"
  set "NEOFORGE_URL=%NEOFORGE_MAVEN%/neoforge/maven-metadata.xml"
)
curl.exe -fsSL --retry 3 -o "%XML_FILE%" "%NEOFORGE_URL%"
if errorlevel 1 call :die "Could not fetch NeoForge versions."
set "MC_VERSION=%VERSION%"
set "PS_EXPR=[xml]$x=Get-Content -Raw -LiteralPath $env:XML_FILE; $mc=$env:MC_VERSION; if ($mc -eq '1.20.1') { $p='1.20.1-' } elseif ($mc.StartsWith('1.')) { $b=$mc.Substring(2); if (-not $b.Contains('.')) { $b=$b+'.0' }; $p=$b+'.' } else { if (($mc -split '\.').Count -eq 3) { $p=$mc+'.' } else { $p=$mc+'.0.' } }; $v=@($x.metadata.versioning.versions.version | Where-Object { $_.StartsWith($p) -and $_ -notmatch '-(beta|alpha)|snapshot' }); if ($v.Count -gt 0) { $v | Sort-Object { [int](($_ -split '\.')[-1]) } | Select-Object -Last 1 }"
call :ps_run
if not defined PS_OUT call :die "NeoForge has no stable build for Minecraft %VERSION% (1.20.1 minimum; some versions are not supported)."
set "NEOFORGE_VERSION=%PS_OUT%"
if "%ARTIFACT%"=="forge" (
  set "JAR_URL=%NEOFORGE_MAVEN%/forge/%NEOFORGE_VERSION%/forge-%NEOFORGE_VERSION%-installer.jar"
) else (
  set "JAR_URL=%NEOFORGE_MAVEN%/neoforge/%NEOFORGE_VERSION%/neoforge-%NEOFORGE_VERSION%-installer.jar"
)
set "JAR_NAME=%ARTIFACT%-%NEOFORGE_VERSION%-installer.jar"
call :fetch_sha1 "%JAR_URL%"
set "LOADER_DETAIL=NeoForge %NEOFORGE_VERSION%"
goto :eof

:detect_system_java
set "SYS_JAVA_MAJOR="
where java >nul 2>&1
if errorlevel 1 goto :eof
set "PS_EXPR=try { $q=[char]34; $v=(& java -version 2>&1 | Select-Object -First 1); $s=$v.Split($q); if ($s.Count -lt 2) { exit 1 }; $r=$s[1]; if ($r.StartsWith('1.')) { [int](($r.Substring(2) -split '\.')[0]) } else { [int](($r -split '\.')[0]) } } catch { exit 1 }"
call :ps_run
if defined PS_OUT set "SYS_JAVA_MAJOR=%PS_OUT%"
goto :eof

:next_jdk_feature
set "JDK_FEATURE="
for %%F in (8 11 17 21 25) do (
  if not defined JDK_FEATURE if %%F GEQ %JAVA_REQUIRED% set "JDK_FEATURE=%%F"
)
if not defined JDK_FEATURE exit /b 1
exit /b 0

:assess_java
call :section "Java"
if not defined JAVA_REQUIRED set "JAVA_REQUIRED=8"
set "JAVA_MODE=system"
set "JAVA_BIN=java"
set "JAVA_DETAIL="
set "JDK_FEATURE="
call :detect_system_java
if not defined SYS_JAVA_MAJOR goto :assess_no_java
if %SYS_JAVA_MAJOR% GEQ %JAVA_REQUIRED% goto :assess_ok
call :warn "Java %SYS_JAVA_MAJOR% detected, but Minecraft %VERSION% requires Java %JAVA_REQUIRED%+."
goto :assess_need_jdk

:assess_no_java
call :warn "Java was not found on this system."

:assess_need_jdk
call :next_jdk_feature
if errorlevel 1 call :die "No local JDK is available for Java %JAVA_REQUIRED%+. Install it manually."
set "ANSWER="
set /p "ANSWER=Download a local Temurin %JDK_FEATURE% JDK into the server folder? [y/N] "
call :ps_yes
if errorlevel 1 call :cancel
goto :assess_local

:assess_local
set "JAVA_MODE=local"
set "JAVA_DETAIL=Temurin %JDK_FEATURE% (local, to download)"
goto :eof

:assess_ok
set "JAVA_DETAIL=Java %SYS_JAVA_MAJOR% (system)"
call :ok "Java %SYS_JAVA_MAJOR% detected (required: %JAVA_REQUIRED%+)."
if %JAVA_REQUIRED% LEQ 8 if %SYS_JAVA_MAJOR% GTR 8 call :warn "Minecraft %VERSION% may require Java %JAVA_REQUIRED%; Java %SYS_JAVA_MAJOR% might not work."
goto :eof

:download_local_jdk
set "FEATURE=%JDK_FEATURE%"
set "ARCH_RAW=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH_RAW=%PROCESSOR_ARCHITEW6432%"
set "ARCH="
if /i "%ARCH_RAW%"=="AMD64" set "ARCH=x64"
if /i "%ARCH_RAW%"=="ARM64" set "ARCH=aarch64"
if not defined ARCH call :die "Unsupported architecture for JDK download: %ARCH_RAW%."
call :section "Downloading Java %FEATURE%"
set "API_URL=%ADOPTIUM_ASSETS_URL%/%FEATURE%/hotspot?architecture=%ARCH%&image_type=jdk&os=windows&vendor=eclipse"
set "JSON_FILE=%TMP_DIR%\adoptium-%FEATURE%.json"
curl.exe -fsSL --retry 3 -o "%JSON_FILE%" "%API_URL%"
if errorlevel 1 call :die "The Adoptium API is unreachable."
set "PS_EXPR=$d=@(Get-Content -Raw -LiteralPath $env:JSON_FILE | ConvertFrom-Json); $p=($d | Where-Object { $_.binary.package.name -like '*.zip' } | Select-Object -First 1).binary.package; if (-not $p) { exit 1 }; $t=$env:TMP_DIR; [IO.File]::WriteAllText((Join-Path $t 'jdk-link.txt'), [string]$p.link); [IO.File]::WriteAllText((Join-Path $t 'jdk-checksum.txt'), [string]$p.checksum); [IO.File]::WriteAllText((Join-Path $t 'jdk-name.txt'), [string]$p.name); [IO.File]::WriteAllText((Join-Path $t 'jdk-size.txt'), [string]$p.size)"
powershell -NoProfile -Command "Invoke-Expression $env:PS_EXPR"
if errorlevel 1 call :die "No Temurin %FEATURE% JDK is available for this platform."
set "JDK_LINK="
set "JDK_CHECKSUM="
set "JDK_FILENAME="
set "JDK_SIZE="
set /p "JDK_LINK=" < "%TMP_DIR%\jdk-link.txt"
set /p "JDK_CHECKSUM=" < "%TMP_DIR%\jdk-checksum.txt"
set /p "JDK_FILENAME=" < "%TMP_DIR%\jdk-name.txt"
set /p "JDK_SIZE=" < "%TMP_DIR%\jdk-size.txt"
if not defined JDK_CHECKSUM call :die "No Temurin %FEATURE% JDK is available for this platform."
if not defined JDK_SIZE set "JDK_SIZE=0"
set /a SIZE_MB=%JDK_SIZE%/1048576
set "ARCHIVE=%SERVER_DIR%\.jdk.zip"
echo Downloading "%JDK_FILENAME%" (%SIZE_MB% MB)...
curl.exe -fL --retry 3 --progress-bar -o "%ARCHIVE%" "%JDK_LINK%"
if errorlevel 1 call :die "JDK download failed."
set "FILE=%ARCHIVE%"
set "PS_EXPR=(Get-FileHash -Algorithm SHA256 -LiteralPath $env:FILE).Hash.ToLower()"
call :ps_run
if not defined PS_OUT call :die "Could not compute the JDK checksum."
if /i not "%PS_OUT%"=="%JDK_CHECKSUM%" (
  del /f /q "%ARCHIVE%" >nul 2>&1
  call :die "Invalid SHA-256 checksum for the downloaded JDK."
)
call :ok "SHA-256 checksum verified."
set "LOCAL_JAVA_HOME=%SERVER_DIR%\.jdk"
if exist "%LOCAL_JAVA_HOME%" rmdir /s /q "%LOCAL_JAVA_HOME%"
mkdir "%LOCAL_JAVA_HOME%"
if errorlevel 1 call :die "Could not create the local JDK folder."
set "DEST=%LOCAL_JAVA_HOME%"
set "PS_EXPR=$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:DEST -Force"
powershell -NoProfile -Command "Invoke-Expression $env:PS_EXPR"
if errorlevel 1 call :die "JDK extraction failed."
del /f /q "%ARCHIVE%" >nul 2>&1
set "FOUND_HOME="
for /d %%D in ("%LOCAL_JAVA_HOME%\*") do (
  if exist "%%~D\bin\java.exe" if not defined FOUND_HOME set "FOUND_HOME=%%~D"
)
if not defined FOUND_HOME call :die "The extracted JDK is invalid."
if exist "%LOCAL_JAVA_HOME%\home" rmdir /s /q "%LOCAL_JAVA_HOME%\home"
move /y "%FOUND_HOME%" "%LOCAL_JAVA_HOME%\home" >nul
set "JAVA_BIN=%LOCAL_JAVA_HOME%\home\bin\java.exe"
if not exist "%JAVA_BIN%" call :die "The extracted JDK is invalid."
set "JAVA_HOME=%LOCAL_JAVA_HOME%\home"
set "PATH=%JAVA_HOME%\bin;%PATH%"
call :ok "JDK %FEATURE% installed in .jdk"
goto :eof

:print_summary
call :section "Summary"
echo   Name        %NAME%
echo   Folder      "%SERVER_DIR%"
echo   Version     %VERSION%
echo   Mod loader  %LOADER%
echo   Detail      %LOADER_DETAIL%
echo   Jar file    "%JAR_NAME%"
echo   Max memory  %RAM_GB% GB
echo   Java        %JAVA_DETAIL%
echo   Source
echo     "%JAR_URL%"
goto :eof

:confirm
set "ANSWER="
set /p "ANSWER=Create this server? [y/N] "
call :ps_yes
if errorlevel 1 exit /b 1
exit /b 0

:write_run_bat
> run.bat echo @echo off
>> run.bat echo cd /d "%%~dp0"
if "%JAVA_MODE%"=="local" (
  >> run.bat echo set "JAVA_HOME=%%~dp0.jdk\home"
  >> run.bat echo set "PATH=%%JAVA_HOME%%\bin;%%PATH%%"
  >> run.bat echo "%%JAVA_HOME%%\bin\java.exe" -Xmx%RAM_GB%G -jar "%JAR_NAME%" nogui
) else (
  >> run.bat echo java -Xmx%RAM_GB%G -jar "%JAR_NAME%" nogui
)
goto :eof

:apply_forge_memory
if not exist "user_jvm_args.txt" (
  call :warn "user_jvm_args.txt not found; memory settings were not applied."
  goto :eof
)
set "ARGS_FILE=%CD%\user_jvm_args.txt"
set "PS_EXPR=$ErrorActionPreference='Stop'; $p=$env:ARGS_FILE; $l=@(Get-Content -LiteralPath $p | Where-Object { $_ -notmatch '^\s*-Xm[sx]' }); $l += ('-Xmx' + $env:RAM_GB + 'G'); [IO.File]::WriteAllLines($p, [string[]]$l)"
powershell -NoProfile -Command "Invoke-Expression $env:PS_EXPR"
if errorlevel 1 call :die "Could not update user_jvm_args.txt."
goto :eof

:wrap_forge_run_script
if not "%JAVA_MODE%"=="local" goto :eof
if not exist "run.bat" goto :eof
move /y "run.bat" "run-server.bat" >nul
if errorlevel 1 call :die "Could not rename the Forge launch script."
> run.bat echo @echo off
>> run.bat echo cd /d "%%~dp0"
>> run.bat echo set "JAVA_HOME=%%~dp0.jdk\home"
>> run.bat echo set "PATH=%%JAVA_HOME%%\bin;%%PATH%%"
>> run.bat echo call "%%~dp0run-server.bat" %%*
if not exist "run.bat" call :die "Could not create run.bat."
goto :eof

:cleanup_ok
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%" >nul 2>&1
endlocal
exit 0

:cleanup_fail
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%" >nul 2>&1
endlocal
exit 1
