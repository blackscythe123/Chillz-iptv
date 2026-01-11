@echo off
echo Running Flutter app in debug mode with libVLC bundling...

echo.
echo Step 1: Running Flutter in debug mode...
start /b flutter run -d windows

echo Waiting for build to complete...
timeout /t 30 /nobreak > nul

echo.
echo Step 2: Bundling libVLC files for debug build...
if exist "libvlc_bundle\libvlc.dll" (
    echo Found local libvlc_bundle — using it as source
    powershell -ExecutionPolicy Bypass -File "scripts\bundle_libvlc.ps1" -Source "%CD%\libvlc_bundle" -Configuration Debug
) else (
    echo No local libvlc_bundle found — falling back to system VLC install (C:\Program Files\VideoLAN\VLC)
    powershell -ExecutionPolicy Bypass -File "scripts\bundle_libvlc.ps1" -Source "C:\Program Files\VideoLAN\VLC" -Configuration Debug
)

echo.
echo ✅ libVLC files bundled! The app should now work properly.
echo If the app is still running, hot reload it to apply changes.
echo.
pause