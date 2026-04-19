@echo off
title Bayer POS - Kurulum
color 0A

echo.
echo ============================================================
echo        BAYER POS - KURULUM SCRIPTI
echo ============================================================
echo.

REM Ana dizine gec
cd /d "%~dp0.."
echo Calisma dizini: %CD%
echo.

REM ==============================================================
REM 1. GEREKSINIMLERI KONTROL ET
REM ==============================================================

echo [1/3] Gereksinimler kontrol ediliyor...
echo.

REM Node.js kontrolu
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: Node.js bulunamadi!
    echo.
    echo Node.js kurmaniz gerekiyor:
    echo https://nodejs.org/
    echo.
    echo LTS versiyonunu indirin ve kurun.
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
    echo rustup-init.exe dosyasini indirip calistirin.
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('cargo --version') do set CARGO_VERSION=%%i
echo [OK] Rust/Cargo: %CARGO_VERSION%
echo.

REM ==============================================================
REM 2. LOCAL-POS DIZININE GEC VE DEPENDENCIES KUR
REM ==============================================================

echo [2/3] Dependencies kuruluyor...
echo Bu islem 5-10 dakika surebilir, lutfen bekleyin...
echo.

cd local-pos
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: local-pos dizini bulunamadi!
    pause
    exit /b 1
)

REM Dependencies kur
echo Node modulleri kuruluyor...
call npm install
if %ERRORLEVEL% NEQ 0 (
    echo [X] HATA: npm install basarisiz!
    pause
    exit /b 1
)
echo [OK] Dependencies kuruldu
echo.

REM ==============================================================
REM 3. KURULUM TAMAMLANDI
REM ==============================================================

echo [3/3] Kurulum tamamlandi!
echo.
echo ============================================================
echo   KURULUM BASARIYLA TAMAMLANDI!
echo ============================================================
echo.
echo Uygulamayi baslatmak icin:
echo   1. Ana dizindeki BASLAT.bat dosyasina cift tiklayin
echo   2. VEYA: local-pos klasorunde "npm run tauri:dev" komutunu calistirin
echo.
echo Veritabani dosyasi: pos.db (otomatik olusturulur)
echo.
pause
