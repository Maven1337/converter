@echo off
setlocal EnableDelayedExpansion

:: ================================================================
:: convert_to_onnx.bat
::
:: Converts a YOLO .pt model to ONNX using Ultralytics:
::   yolo export model="..." format=onnx imgsz=...
::
:: Optimization presets (imgsz only):
::   1 = Best performance (smaller size, faster, may reduce detection quality)
::   2 = Best detection   (larger size, slower, may improve detection quality)
::   3 = Balanced (recommended default)
::
:: Requirements:
::   - Windows
::   - Python installed and on PATH
::   - Ultralytics YOLO installed: pip install -U ultralytics
::
:: The script checks for missing requirements, prints what is wrong,
:: explains how to fix it step by step, and exits with explicit codes:
::   0 = Success
::   1 = Input .pt file not found
::   2 = Ultralytics YOLO (yolo) not installed or not on PATH
::   3 = Export failed or .onnx not created
::   4 = Python not installed or not on PATH
::   5 = User canceled or other unrecoverable error
:: ================================================================

set "EXIT_CODE=0"
set "EXIT_REASON=Success"

pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    set "EXIT_CODE=5"
    set "EXIT_REASON=Could not switch to script directory"
    goto :final
)

set "INPUT_PT=%~1"
if "%INPUT_PT%"=="" set "INPUT_PT=best.pt"

for %%I in ("%INPUT_PT%") do (
    set "INPUT_ABS=%%~fI"
    set "INPUT_NAME=%%~nxI"
    set "INPUT_BASE=%%~nI"
    set "INPUT_DIR=%%~dpI"
)

set "OUTPUT_ARG=%~2"
if "%OUTPUT_ARG%"=="" (
    set "OUTPUT_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
) else (
    for %%O in ("%OUTPUT_ARG%") do set "OUTPUT_ONNX=%%~fO"
)
for %%P in ("%OUTPUT_ONNX%") do (
    set "OUTPUT_DIR=%%~dpP"
    set "OUTPUT_NAME=%%~nxP"
)

set "PRESET=%~3"
if "%PRESET%"=="" goto :preset_prompt
call :apply_preset "%PRESET%"
if errorlevel 1 goto :preset_prompt
goto :after_preset

:preset_prompt
echo.
echo Select optimization preset (Balanced is recommended):
echo   [1] Best performance - faster inference, potentially lower detection quality
echo   [2] Best detection   - slower inference, potentially better detection quality
echo   [3] Balanced ^(recommended^) - good speed/quality tradeoff
set /p PRESET="Enter 1, 2, or 3 [default 3]: "
if "%PRESET%"=="" set "PRESET=3"
call :apply_preset "%PRESET%"
if errorlevel 1 (
    echo [!] Invalid preset selection. Please enter 1, 2, or 3.
    goto :preset_prompt
)

:after_preset
echo.
echo [*] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [!] Python is required for Ultralytics YOLO.
    echo     Download Python from the official Python website.
    echo     During installation, enable "Add python.exe to PATH".
    set "EXIT_CODE=4"
    set "EXIT_REASON=Python not installed or not on PATH"
    goto :final
)

echo [*] Checking Ultralytics YOLO CLI ^(yolo^) ...
yolo version >nul 2>&1
if errorlevel 1 (
    yolo --help >nul 2>&1
    if errorlevel 1 (
        echo [!] Ultralytics YOLO is not installed or not on PATH.
        echo     Install or update it with:
        echo       pip install -U ultralytics
        echo     Then close and reopen your terminal.
        set "EXIT_CODE=2"
        set "EXIT_REASON=Ultralytics YOLO not installed or not on PATH"
        goto :final
    )
)

echo [*] Checking input model file...
if not exist "%INPUT_ABS%" (
    echo [!] Input file not found: "%INPUT_ABS%"
    echo     Typical fixes:
    echo       - Check the filename spelling.
    echo       - Put the file in this script directory.
    echo       - Pass a full path as argument 1.
    set "EXIT_CODE=1"
    set "EXIT_REASON=Input .pt file not found"
    goto :final
)

echo.
echo [*] Conversion plan:
echo     Input file : "%INPUT_ABS%"
echo     Output file: "%OUTPUT_ONNX%"
echo     Preset     : %PRESET_NAME%
echo     Why        : %PRESET_DESC%
echo     Recommended: Balanced preset is recommended for most users.
echo.
echo [*] Running export command:
echo     yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
echo.

yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
if errorlevel 1 (
    echo [!] Export failed. Keeping original .pt file.
    echo     Common causes: corrupted model or version incompatibility.
    echo     Try running this command manually:
    echo       yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
    echo     You can also update Ultralytics:
    echo       pip install -U ultralytics
    set "EXIT_CODE=3"
    set "EXIT_REASON=Export command failed"
    goto :final
)

set "GENERATED_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
if not exist "%GENERATED_ONNX%" (
    echo [!] Export finished but expected ONNX output was not created:
    echo     "%GENERATED_ONNX%"
    echo     Keeping original .pt file.
    set "EXIT_CODE=3"
    set "EXIT_REASON=Expected .onnx output not found"
    goto :final
)

if /I not "%GENERATED_ONNX%"=="%OUTPUT_ONNX%" (
    if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" >nul 2>&1
    move /Y "%GENERATED_ONNX%" "%OUTPUT_ONNX%" >nul
    if errorlevel 1 (
        echo [!] Export succeeded, but failed to place output at:
        echo     "%OUTPUT_ONNX%"
        echo     Generated file remains at:
        echo     "%GENERATED_ONNX%"
        set "EXIT_CODE=3"
        set "EXIT_REASON=Failed to move .onnx to requested output path"
        goto :final
    )
)

echo.
:delete_prompt
set "DELETE_CHOICE="
set /p DELETE_CHOICE="Do you want to delete the original .pt file? [Y/n]: "
if "%DELETE_CHOICE%"=="" set "DELETE_CHOICE=Y"
if /I "%DELETE_CHOICE%"=="Y" (
    del /F /Q "%INPUT_ABS%" >nul 2>&1
    if errorlevel 1 (
        echo [!] Could not delete "%INPUT_ABS%". File has been kept.
    ) else (
        echo [+] Original .pt file deleted.
    )
) else if /I "%DELETE_CHOICE%"=="N" (
    echo [+] Original .pt file kept.
) else (
    echo [!] Invalid choice. Please enter Y or N.
    goto :delete_prompt
)

set "EXIT_CODE=0"
set "EXIT_REASON=Success"

:final
echo.
echo ==================== SUMMARY ====================
echo Input file          : "%INPUT_ABS%"
echo Output file         : "%OUTPUT_ONNX%"
echo Optimization preset : %PRESET_NAME% ^(imgsz=%IMGSZ%^) 
echo Exit status         : %EXIT_REASON%
echo Exit code           : %EXIT_CODE%
echo =================================================

popd >nul 2>&1
endlocal & exit /b %EXIT_CODE%

:apply_preset
set "PRESET=%~1"
if "%PRESET%"=="1" (
    set "IMGSZ=640"
    set "PRESET_NAME=1 - Best performance"
    set "PRESET_DESC=Smaller image size for faster runtime, with potential quality tradeoff"
    exit /b 0
)
if "%PRESET%"=="2" (
    set "IMGSZ=1280"
    set "PRESET_NAME=2 - Best detection"
    set "PRESET_DESC=Larger image size for potentially better detection, with slower runtime"
    exit /b 0
)
if "%PRESET%"=="3" (
    set "IMGSZ=960"
    set "PRESET_NAME=3 - Balanced (recommended)"
    set "PRESET_DESC=Balanced speed and detection quality for most users"
    exit /b 0
)
exit /b 1
