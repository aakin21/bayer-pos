@echo off
cls
echo.
echo  ========================================
echo      BAYER POS KAPATILIYOR...
echo  ========================================
echo.

taskkill /F /IM node.exe /T >nul 2>&1
taskkill /F /IM bayer-pos.exe /T >nul 2>&1
taskkill /F /IM BayerPOS.exe /T >nul 2>&1
taskkill /F /IM cargo.exe /T >nul 2>&1

echo  Tum process'ler kapatildi.
timeout /t 2 >nul
exit
