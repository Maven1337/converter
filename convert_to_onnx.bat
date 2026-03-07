@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ================================================================
REM convert_to_onnx.bat
REM Converts a YOLO .pt model to ONNX using Ultralytics YOLO.
REM
REM Arguments:
REM   arg1 = input .pt model path (default: best.pt in script directory)
REM   arg2 = optional output .onnx path
REM   arg3 = optional optimization preset (1, 2, or 3)
REM
REM Exit codes:
REM   0 = Success
REM   1 = Input .pt file not found / invalid
REM   2 = Ultralytics YOLO (yolo) not installed or not on PATH
REM   3 = Export failed or .onnx not created
REM   4 = Python not installed or not on PATH
REM   5 = User canceled or other unrecoverable error
REM ================================================================

set "EXIT_CODE=0"
set "EXIT_REASON=Success"
set "EXPORT_ERROR=0"
set "GPU_NAME="
set "CPU_NAME="
set "RAM_GB="
set "SUGGESTED_PRESET=3"
set "SUGGESTED_PRESET_NAME=3 - Balanced (recommended)"

call :line
call :title "YOLO .PT TO ONNX CONVERTER"
call :line

REM -------------------- Switch to script directory --------------------
pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    call :fail 5 "Could not switch to script directory"
    goto :final
)

REM -------------------- Argument handling --------------------
set "INPUT_PT=%~1"
if "%INPUT_PT%"=="" set "INPUT_PT=best.pt"

for %%I in ("%INPUT_PT%") do (
    set "INPUT_ABS=%%~fI"
    set "INPUT_NAME=%%~nxI"
    set "INPUT_BASE=%%~nI"
    set "INPUT_EXT=%%~xI"
    set "INPUT_DIR=%%~dpI"
)

set "OUTPUT_ARG=%~2"
if "%OUTPUT_ARG%"=="" (
    set "OUTPUT_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
) else (
    for %%O in ("%OUTPUT_ARG%") do (
        set "OUTPUT_ONNX=%%~fO"
        set "OUTPUT_EXT=%%~xO"
    )
    if /I not "%OUTPUT_EXT%"==".onnx" set "OUTPUT_ONNX=%OUTPUT_ONNX%.onnx"
)

for %%P in ("%OUTPUT_ONNX%") do (
    set "OUTPUT_DIR=%%~dpP"
    set "OUTPUT_NAME=%%~nxP"
)

REM -------------------- Hardware detection and preset choice --------------------
call :detect_hardware

set "PRESET=%~3"
if not "%PRESET%"=="" (
    call :apply_preset "%PRESET%"
    if errorlevel 1 (
        echo [WARN] Invalid preset argument "%PRESET%". Falling back to interactive selection.
        set "PRESET="
    )
)

if "%PRESET%"=="" goto :preset_prompt
goto :after_preset

:preset_prompt
call :line
echo [INFO] Select optimization preset ^(Balanced is recommended^):
if defined GPU_NAME echo [INFO] Detected GPU: !GPU_NAME!
if defined CPU_NAME echo [INFO] Detected CPU: !CPU_NAME!
if defined RAM_GB echo [INFO] Detected RAM: !RAM_GB! GB
if not defined RAM_GB echo [INFO] Detected RAM: Unknown
if not defined SUGGESTED_PRESET set "SUGGESTED_PRESET=3"
call :apply_preset "%SUGGESTED_PRESET%" >nul 2>&1
if errorlevel 1 (
    set "SUGGESTED_PRESET=3"
    call :apply_preset "3" >nul 2>&1
)
set "SUGGESTED_PRESET_NAME=!PRESET_NAME!"
echo [INFO] Suggested preset based on your system: !SUGGESTED_PRESET_NAME!.
echo        [1] Best performance - faster, potentially lower detection quality
echo        [2] Best detection   - slower, potentially better detection quality
echo        [3] Balanced         - recommended for most users
set /p PRESET="[INPUT] Enter 1, 2, or 3 [default !SUGGESTED_PRESET!]: "
if "%PRESET%"=="" set "PRESET=!SUGGESTED_PRESET!"
call :apply_preset "%PRESET%"
if errorlevel 1 (
    echo [WARN] Invalid preset. Please enter 1, 2, or 3.
    goto :preset_prompt
)

:after_preset

REM -------------------- Dependency checks --------------------
call :line
echo [STEP] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is required for Ultralytics YOLO.
    echo         Download Python from the official Python website.
    echo         During installation, enable "Add python.exe to PATH".
    call :fail 4 "Python not installed or not on PATH"
    goto :final
)
echo [OK] Python is available.

echo [STEP] Checking Ultralytics YOLO CLI ^(yolo^) ...
where yolo >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Ultralytics YOLO is not installed or not on PATH.
    echo         Install or update it with:
    echo           pip install -U ultralytics
    echo         Then close and reopen your terminal.
    call :fail 2 "Ultralytics YOLO not installed or not on PATH"
    goto :final
)
yolo version >nul 2>&1
if errorlevel 1 (
    yolo --help >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] The yolo command was found but did not run correctly.
        echo         Try reinstalling/updating:
        echo           pip install -U ultralytics
        call :fail 2 "Ultralytics YOLO command check failed"
        goto :final
    )
)
echo [OK] YOLO CLI is available.

echo [STEP] Checking input model file...
if not exist "%INPUT_ABS%" (
    echo [ERROR] Input file not found: "%INPUT_ABS%"
    echo         Typical fixes:
    echo           - Check the filename.
    echo           - Ensure it is in this script directory.
    echo           - Pass a full path as argument 1.
    call :fail 1 "Input .pt file not found"
    goto :final
)

if /I not "%INPUT_EXT%"==".pt" (
    echo [ERROR] Input file must be a .pt model: "%INPUT_ABS%"
    call :fail 1 "Input file extension is not .pt"
    goto :final
)
echo [OK] Input model found.

if exist "%OUTPUT_ONNX%" (
    call :line
    echo [WARN] Output already exists:
    echo        "%OUTPUT_ONNX%"
    call :confirm_overwrite
    if errorlevel 1 goto :final
)

if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Could not create output directory:
        echo         "%OUTPUT_DIR%"
        call :fail 5 "Failed to create output directory"
        goto :final
    )
)

REM -------------------- Export --------------------
call :line
echo [PLAN] Input file : "%INPUT_ABS%"
echo [PLAN] Output file: "%OUTPUT_ONNX%"
echo [PLAN] Preset     : %PRESET_NAME%
echo [PLAN] Why        : %PRESET_DESC%
echo [PLAN] Recommended: Balanced preset is recommended for most users.

echo.
echo [RUN ] yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
set "EXPORT_ERROR=%ERRORLEVEL%"
if not "%EXPORT_ERROR%"=="0" (
    echo [ERROR] Export failed. Keeping original .pt file.
    echo         Common causes: corrupt model or version incompatibility.
    echo         Try running the command manually:
    echo           yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
    echo         You can also update Ultralytics:
    echo           pip install -U ultralytics
    call :fail 3 "Export failed with code %EXPORT_ERROR%"
    goto :final
)

set "GENERATED_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
if not exist "%GENERATED_ONNX%" (
    echo [ERROR] Export command returned success, but ONNX file was not created:
    echo         "%GENERATED_ONNX%"
    call :fail 3 "Expected .onnx output not found"
    goto :final
)

if /I not "%GENERATED_ONNX%"=="%OUTPUT_ONNX%" (
    move /Y "%GENERATED_ONNX%" "%OUTPUT_ONNX%" >nul
    if errorlevel 1 (
        echo [ERROR] Export succeeded, but failed to move output to:
        echo         "%OUTPUT_ONNX%"
        echo         Generated file remains at:
        echo         "%GENERATED_ONNX%"
        call :fail 3 "Failed to move .onnx to requested output path"
        goto :final
    )
)

if not exist "%OUTPUT_ONNX%" (
    echo [ERROR] Output file not found after export:
    echo         "%OUTPUT_ONNX%"
    call :fail 3 "Output .onnx file not found"
    goto :final
)

echo [OK] Export completed successfully.

REM -------------------- Optional source deletion --------------------
call :line
:delete_prompt
set "DELETE_CHOICE="
set /p DELETE_CHOICE="[INPUT] Do you want to delete the original .pt file? [Y/n]: "
if "%DELETE_CHOICE%"=="" set "DELETE_CHOICE=Y"
if /I "%DELETE_CHOICE%"=="Y" (
    del /F /Q "%INPUT_ABS%" >nul 2>&1
    if errorlevel 1 (
        echo [WARN] Could not delete "%INPUT_ABS%". File has been kept.
    ) else (
        echo [OK] Original .pt file deleted.
    )
) else if /I "%DELETE_CHOICE%"=="N" (
    echo [OK] Original .pt file kept.
) else (
    echo [WARN] Invalid choice. Please enter Y or N.
    goto :delete_prompt
)

set "EXIT_CODE=0"
set "EXIT_REASON=Success"
goto :final

REM -------------------- Helpers --------------------
:detect_hardware
set "GPU_NAME="
set "CPU_NAME="
set "RAM_BYTES="
set "RAM_GB="
set "SUGGESTED_PRESET=3"

for /f "usebackq skip=1 tokens=* delims=" %%G in (`wmic path win32_videocontroller get name 2^>nul`) do (
    if not defined GPU_NAME (
        set "TMP=%%G"
        if not "!TMP!"=="" set "GPU_NAME=!TMP!"
    )
)

for /f "usebackq skip=1 tokens=* delims=" %%C in (`wmic cpu get name 2^>nul`) do (
    if not defined CPU_NAME (
        set "TMP=%%C"
        if not "!TMP!"=="" set "CPU_NAME=!TMP!"
    )
)

for /f "usebackq skip=1 tokens=* delims=" %%R in (`wmic ComputerSystem get TotalPhysicalMemory 2^>nul`) do (
    if not defined RAM_BYTES (
        set "TMP=%%R"
        if not "!TMP!"=="" set "RAM_BYTES=!TMP!"
    )
)

if defined RAM_BYTES (
    set /a RAM_GB=!RAM_BYTES!/1073741824 2>nul
)

set "GPU_LC=!GPU_NAME!"
if defined GPU_LC (
    set "GPU_LC=!GPU_LC:RTX=rtx!"
    set "GPU_LC=!GPU_LC:RX 6=rx 6!"
    set "GPU_LC=!GPU_LC:RX 7=rx 7!"
    set "GPU_LC=!GPU_LC:ARC A=arc a!"
    set "GPU_LC=!GPU_LC:UHD=uhd!"
    set "GPU_LC=!GPU_LC:IRIS=iris!"
    set "GPU_LC=!GPU_LC:HD Graphics=hd graphics!"
    set "GPU_LC=!GPU_LC:VEGA=vega!"
)

set "IS_HIGH_GPU=0"
set "IS_LOW_GPU=0"

if defined GPU_LC (
    echo !GPU_LC! | find /I "rtx" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_LC! | find /I "rx 6" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_LC! | find /I "rx 7" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_LC! | find /I "arc a" >nul && set "IS_HIGH_GPU=1"

    echo !GPU_LC! | find /I "intel" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "uhd" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "iris" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "hd graphics" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "vega 3" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "vega 5" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "vega 6" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "vega 7" >nul && set "IS_LOW_GPU=1"
    echo !GPU_LC! | find /I "vega 8" >nul && set "IS_LOW_GPU=1"
)

if defined RAM_GB (
    if !RAM_GB! LSS 8 set "SUGGESTED_PRESET=1"
)

if "%SUGGESTED_PRESET%"=="3" (
    if "%IS_LOW_GPU%"=="1" set "SUGGESTED_PRESET=1"
)

if "%SUGGESTED_PRESET%"=="3" (
    if "%IS_HIGH_GPU%"=="1" (
        if defined RAM_GB (
            if !RAM_GB! GEQ 16 set "SUGGESTED_PRESET=2"
        )
    )
)

exit /b 0

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

:confirm_overwrite
:overwrite_prompt
set "OVERWRITE_CHOICE="
set /p OVERWRITE_CHOICE="[INPUT] Overwrite existing output file? [y/N]: "
if "%OVERWRITE_CHOICE%"=="" set "OVERWRITE_CHOICE=N"
if /I "%OVERWRITE_CHOICE%"=="Y" (
    del /F /Q "%OUTPUT_ONNX%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Could not remove existing output file.
        call :fail 5 "Cannot overwrite existing output file"
        exit /b 1
    )
    exit /b 0
)
if /I "%OVERWRITE_CHOICE%"=="N" (
    echo [INFO] Operation canceled by user.
    call :fail 5 "User canceled because output already exists"
    exit /b 1
)
echo [WARN] Invalid choice. Enter Y or N.
goto :overwrite_prompt

:fail
set "EXIT_CODE=%~1"
set "EXIT_REASON=%~2"
exit /b 0

:line
echo ================================================================
exit /b 0

:title
echo %~1
exit /b 0

:final
call :line
echo SUMMARY
echo   Input file          : "%INPUT_ABS%"
echo   Output file         : "%OUTPUT_ONNX%"
echo   Optimization preset : %PRESET_NAME% ^(imgsz=%IMGSZ%^)
echo   Exit status         : %EXIT_REASON%
echo   Exit code           : %EXIT_CODE%
call :line

popd >nul 2>&1
endlocal & exit /b %EXIT_CODE%
