@echo off
title Bayer POS - Otomatik Build ve Kurulum
color 0A

echo.
echo ============================================================
echo        BAYER POS - OTOMATIK BUILD VE KURULUM
echo ============================================================
echo.

REM Ana dizine gec
cd /d "%~dp0"
echo Calisma dizini: %CD%
echo.

REM ==============================================================
REM 1. GEREKSINIMLERI KONTROL ET
REM ==============================================================

echo [1/4] Gereksinimler kontrol ediliyor...
echo.

REM Node.js kontrolu
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: Node.js bulunamadi!
    echo.
    echo Node.js kurmaniz gerekiyor:
    echo https://nodejs.org/
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('node -v') do set NODE_VERSION=%%i
echo [OK] Node.js: %NODE_VERSION%

REM npm kontrolu
where npm >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: npm bulunamadi!
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('npm -v') do set NPM_VERSION=%%i
echo [OK] npm: v%NPM_VERSION%

REM Rust kontrolu
where cargo >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: Rust/Cargo bulunamadi!
    echo.
    echo Rust kurmaniz gerekiyor:
    echo https://rustup.rs/
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('cargo --version') do set CARGO_VERSION=%%i
echo [OK] Rust/Cargo: %CARGO_VERSION%
echo.

REM ==============================================================
REM 2. LOCAL-POS DIZININE GEC
REM ==============================================================

echo [2/4] Proje dizinine geciliyor...
cd local-pos
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: local-pos dizini bulunamadi!
    pause
    exit /b 1
)
echo [OK] local-pos dizinine gecildi
echo.

REM ==============================================================
REM 3. BUILD YAP
REM ==============================================================

echo [3/4] Build yapiliyor...
echo Bu islem 5-10 dakika surebilir, lutfen bekleyin...
echo.

REM Dependencies kur
if not exist "node_modules\" (
    echo Node modulleri kuruluyor...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo [X] HATA: npm install basarisiz!
        pause
        exit /b 1
    )
    echo [OK] Dependencies kuruldu
    echo.
)

REM Build yap
call npm run tauri build
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: Build basarisiz!
    pause
    exit /b 1
)

echo.
echo [OK] Build basariyla tamamlandi!
echo.

REM ==============================================================
REM 4. INSTALLER'I OTOMATIK CALISTIR
REM ==============================================================

echo [4/4] Installer aciliyor...
echo.

set INSTALLER_DIR=src-tauri\target\release\bundle

REM MSI installer varsa onu kullan
if exist "%INSTALLER_DIR%\msi\*.msi" (
    echo [OK] MSI Installer bulundu, aciliyor...
    for %%f in ("%INSTALLER_DIR%\msi\*.msi") do (
        echo Installer: %%~nxf
        start "" "%%f"
        echo.
        echo ============================================================
        echo   INSTALLER ACILDI! Kurulum adimlarini takip edin.
        echo   Kurulum bitince uygulama otomatik baslatilacak.
        echo ============================================================
        goto :END
    )
)

REM NSIS/EXE installer varsa onu kullan
if exist "%INSTALLER_DIR%\nsis\*.exe" (
    echo [OK] EXE Installer bulundu, aciliyor...
    for %%f in ("%INSTALLER_DIR%\nsis\*.exe") do (
        echo Installer: %%~nxf
        start "" "%%f"
        echo.
        echo ============================================================
        echo   INSTALLER ACILDI! Kurulum adimlarini takip edin.
        echo   Kurulum bitince uygulama otomatik baslatilacak.
        echo ============================================================
        goto :END
    )
)

REM Installer bulunamadiysa
echo [X] HATA: Installer dosyasi bulunamadi!
echo.
echo Kontrol edilen dizin: %INSTALLER_DIR%
echo.
pause
exit /b 1

:END
echo.
echo Islem tamamlandi.
echo.
pause
