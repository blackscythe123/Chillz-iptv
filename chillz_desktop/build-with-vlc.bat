@echo off
echo Building Flutter app with bundled libVLC...

echo.
echo Step 1: Building Flutter Windows app...
flutter build windows --release

if %ERRORLEVEL% neq 0 (
    echo Build failed!
    pause
    exit /b 1
)

echo.
echo Step 2: Bundling libVLC files...
if exist "libvlc_bundle\libvlc.dll" (
    echo Found local libvlc_bundle — using it as source
    powershell -ExecutionPolicy Bypass -File "scripts\bundle_libvlc.ps1" -Source "%CD%\libvlc_bundle" -Configuration Release
) else (
    echo No local libvlc_bundle found — falling back to system VLC install (C:\Program Files\VideoLAN\VLC)
    powershell -ExecutionPolicy Bypass -File "scripts\bundle_libvlc.ps1" -Source "C:\Program Files\VideoLAN\VLC" -Configuration Release
)

if %ERRORLEVEL% neq 0 (
    echo LibVLC bundling failed! Make sure a libVLC source is available (local libvlc_bundle or VLC installed).
    pause
    exit /b 1
)

echo.
echo ✅ Build complete! The app is ready to run with bundled libVLC.
echo Location: build\windows\x64\runner\Release\Chillz_desktop.exe
echo.
pause