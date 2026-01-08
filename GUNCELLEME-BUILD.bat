@echo off
chcp 65001 >nul
echo ========================================
echo  BAYER POS - GÜNCELLEME BUILD
echo ========================================
echo.

cd local-pos

echo [1/3] Versiyon kontrol ediliyor...
echo.

echo [2/3] Build başlatılıyor...
echo Bu işlem birkaç dakika sürebilir...
echo.
call npm run tauri:build

echo.
echo ========================================
echo  ✅ BUILD TAMAMLANDI!
echo ========================================
echo.
echo 📦 Installer konumu:
echo    local-pos\src-tauri\target\release\bundle\msi\
echo.
echo 💡 Bu .msi dosyasını müşteriye gönder.
echo    Database otomatik korunur!
echo.
pause
