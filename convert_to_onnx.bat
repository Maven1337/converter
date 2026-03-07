@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ================================================================
REM convert_to_onnx.bat
REM Converts a YOLO .pt model to ONNX using Ultralytics YOLO.
REM
REM Arguments:
REM   arg1 = input .pt model path
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
set "DID_PUSHD=0"
set "INPUT_PT="
set "INPUT_ABS="
set "INPUT_NAME="
set "INPUT_BASE="
set "INPUT_EXT="
set "INPUT_DIR="
set "OUTPUT_ONNX="
set "OUTPUT_DIR="
set "OUTPUT_NAME="
set "OUTPUT_EXT="
set "GENERATED_ONNX="
set "PRESET="
set "IMGSZ=960"
set "PRESET_NAME=3 - Balanced (recommended)"
set "PRESET_DESC=Balanced speed and detection quality for most users"
set "GPU_NAME="
set "CPU_NAME="
set "RAM_GB="
set "HARDWARE_DETECTED=0"
set "SUGGESTED_PRESET=3"
set "SUGGESTED_PRESET_NAME=3 - Balanced (recommended)"

call :line
call :title "YOLO .PT TO ONNX CONVERTER"
call :line

REM -------------------- Switch to script directory --------------------
pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not switch to script directory: "%~dp0"
    call :fail 5 "Could not switch to script directory"
    goto :final
)
set "DID_PUSHD=1"

REM -------------------- Argument handling and file selection --------------------
if not "%~1"=="" (
    set "INPUT_PT=%~1"
) else (
    call :select_input_model
    if errorlevel 1 goto :final
)

for %%I in ("%INPUT_PT%") do (
    set "INPUT_ABS=%%~fI"
    set "INPUT_NAME=%%~nxI"
    set "INPUT_BASE=%%~nI"
    set "INPUT_EXT=%%~xI"
    set "INPUT_DIR=%%~dpI"
)

if "%INPUT_ABS%"=="" (
    echo [ERROR] No input model path could be resolved.
    call :fail 1 "Input .pt file not found / invalid"
    goto :final
)

if /I not "%INPUT_EXT%"==".pt" (
    echo [ERROR] Input file must be a .pt model: "%INPUT_ABS%"
    call :fail 1 "Input file extension is not .pt"
    goto :final
)

if not exist "%INPUT_ABS%" (
    echo [ERROR] Input file not found: "%INPUT_ABS%"
    echo         Place a .pt file next to this script or pass a full path as arg1.
    call :fail 1 "Input .pt file not found"
    goto :final
)

echo [OK] Input model found: "%INPUT_ABS%"

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

if "%OUTPUT_DIR%"=="" (
    echo [ERROR] Could not resolve output directory from: "%OUTPUT_ONNX%"
    call :fail 5 "Invalid output path"
    goto :final
)

REM -------------------- Hardware detection (PowerShell in background) --------------------
call :detect_hardware
if errorlevel 1 (
    echo [WARN] Hardware detection unavailable. Continuing without hardware-based suggestion.
)

REM -------------------- Preset selection --------------------
set "PRESET=%~3"
if not "%PRESET%"=="" (
    call :apply_preset "%PRESET%"
    if errorlevel 1 (
        echo [WARN] Invalid preset argument "%PRESET%". Falling back to interactive selection.
        set "PRESET="
    )
)

if "%PRESET%"=="" (
    call :prompt_preset
    if errorlevel 1 goto :final
)

REM -------------------- Dependency checks --------------------
call :line
echo [STEP] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is required for Ultralytics YOLO.
    echo         Download Python and enable "Add python.exe to PATH" during install.
    call :fail 4 "Python not installed or not on PATH"
    goto :final
)
echo [OK] Python is available.

echo [STEP] Checking Ultralytics YOLO CLI ^(yolo^) ...
where yolo >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Ultralytics YOLO is not installed or not on PATH.
    echo         Install with: pip install -U ultralytics
    call :fail 2 "Ultralytics YOLO not installed or not on PATH"
    goto :final
)

yolo version >nul 2>&1
if errorlevel 1 (
    yolo --help >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] yolo command exists but is not working correctly.
        call :fail 2 "Ultralytics YOLO command check failed"
        goto :final
    )
)
echo [OK] YOLO CLI is available.

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
call :line
echo [RUN ] Exporting with Ultralytics YOLO...
echo [RUN ] yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%

yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
set "EXPORT_ERROR=%ERRORLEVEL%"
if not "%EXPORT_ERROR%"=="0" (
    echo [ERROR] Export command failed with code %EXPORT_ERROR%.
    call :fail 3 "Export failed"
    goto :final
)

set "GENERATED_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
if not exist "%GENERATED_ONNX%" (
    echo [ERROR] Export command completed, but expected ONNX file was not created:
    echo         "%GENERATED_ONNX%"
    call :fail 3 "Export finished but .onnx not created"
    goto :final
)

if /I not "%GENERATED_ONNX%"=="%OUTPUT_ONNX%" (
    move /Y "%GENERATED_ONNX%" "%OUTPUT_ONNX%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Export succeeded, but failed to move output file to:
        echo         "%OUTPUT_ONNX%"
        echo         Generated file remains at: "%GENERATED_ONNX%"
        call :fail 3 "Failed to move exported .onnx"
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
:delete_prompt
call :line
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
:select_input_model
set "PT_COUNT=0"
for /f "delims=" %%F in ('dir /b /a:-d "*.pt" 2^>nul') do (
    set /a PT_COUNT+=1
    set "PT_FILE_!PT_COUNT!=%%F"
)

if "%PT_COUNT%"=="0" (
    echo [ERROR] No .pt files were found in "%~dp0".
    echo         Place a .pt file next to this script or pass a full path as arg1.
    call :fail 1 "Input .pt file not found"
    exit /b 1
)

if "%PT_COUNT%"=="1" (
    set "INPUT_PT=!PT_FILE_1!"
    echo [INFO] Using detected model: !PT_FILE_1!
    exit /b 0
)

call :line
echo [INFO] Multiple .pt models detected in "%~dp0":
for /l %%N in (1,1,%PT_COUNT%) do echo        [%%N] !PT_FILE_%%N!
set "MODEL_INDEX="
set /p MODEL_INDEX="[INPUT] Select the model to convert by number, or press Enter to cancel: "
if "%MODEL_INDEX%"=="" (
    echo [INFO] Operation canceled by user.
    call :fail 5 "User canceled model selection"
    exit /b 1
)

set /a MODEL_INDEX_NUM=%MODEL_INDEX%+0 >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Invalid selection: "%MODEL_INDEX%".
    call :fail 5 "Invalid model selection"
    exit /b 1
)

if %MODEL_INDEX_NUM% LSS 1 (
    echo [ERROR] Invalid selection: "%MODEL_INDEX%".
    call :fail 5 "Invalid model selection"
    exit /b 1
)
if %MODEL_INDEX_NUM% GTR %PT_COUNT% (
    echo [ERROR] Invalid selection: "%MODEL_INDEX%".
    call :fail 5 "Invalid model selection"
    exit /b 1
)

call set "INPUT_PT=%%PT_FILE_%MODEL_INDEX_NUM%%%"
if "%INPUT_PT%"=="" (
    echo [ERROR] Could not resolve selected model.
    call :fail 5 "Invalid model selection"
    exit /b 1
)

echo [INFO] Using selected model: %INPUT_PT%
exit /b 0

:detect_hardware
set "GPU_NAME="
set "CPU_NAME="
set "RAM_GB="
set "HARDWARE_DETECTED=0"
set "SUGGESTED_PRESET=3"

where powershell >nul 2>&1
if errorlevel 1 exit /b 1

for /f "usebackq tokens=1* delims==" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $gpu=(Get-CimInstance Win32_VideoController | Select-Object -First 1 -ExpandProperty Name); $cpu=(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name); $ram=([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)); if($gpu){Write-Output ('GPU=' + $gpu)}; if($cpu){Write-Output ('CPU=' + $cpu)}; if($ram){Write-Output ('RAM=' + $ram)}" 2^>nul`) do (
    if /I "%%A"=="GPU" set "GPU_NAME=%%B"
    if /I "%%A"=="CPU" set "CPU_NAME=%%B"
    if /I "%%A"=="RAM" set "RAM_GB=%%B"
)

if defined GPU_NAME set "HARDWARE_DETECTED=1"
if defined CPU_NAME set "HARDWARE_DETECTED=1"
if defined RAM_GB set "HARDWARE_DETECTED=1"
if "%HARDWARE_DETECTED%"=="0" exit /b 1

set "IS_HIGH_GPU=0"
set "IS_LOW_GPU=0"

if defined GPU_NAME (
    echo !GPU_NAME! | find /I "RTX" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_NAME! | find /I "RX 6" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_NAME! | find /I "RX 7" >nul && set "IS_HIGH_GPU=1"
    echo !GPU_NAME! | find /I "ARC A" >nul && set "IS_HIGH_GPU=1"

    echo !GPU_NAME! | find /I "Intel(R) UHD" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "UHD" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "HD Graphics" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Iris" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Vega 3" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Vega 5" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Vega 6" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Vega 7" >nul && set "IS_LOW_GPU=1"
    echo !GPU_NAME! | find /I "Vega 8" >nul && set "IS_LOW_GPU=1"
)

if defined RAM_GB (
    set /a RAM_NUM=RAM_GB+0 >nul 2>&1
    if not errorlevel 1 (
        if !RAM_NUM! LSS 8 set "SUGGESTED_PRESET=1"
    )
)

if "%SUGGESTED_PRESET%"=="3" if "%IS_LOW_GPU%"=="1" set "SUGGESTED_PRESET=1"

if "%SUGGESTED_PRESET%"=="3" (
    if "%IS_HIGH_GPU%"=="1" (
        if defined RAM_GB (
            if !RAM_GB! GEQ 16 set "SUGGESTED_PRESET=2"
        )
    )
)

call :apply_preset "%SUGGESTED_PRESET%" >nul 2>&1
if errorlevel 1 (
    set "SUGGESTED_PRESET=3"
    call :apply_preset "3" >nul 2>&1
)
set "SUGGESTED_PRESET_NAME=%PRESET_NAME%"
exit /b 0

:prompt_preset
:preset_prompt
call :line
echo [INFO] Select optimization preset ^(Balanced is recommended^):
if "%HARDWARE_DETECTED%"=="1" (
    if defined GPU_NAME echo [INFO] Detected GPU: !GPU_NAME!
    if defined CPU_NAME echo [INFO] Detected CPU: !CPU_NAME!
    if defined RAM_GB (
        echo [INFO] Detected RAM: !RAM_GB! GB
    ) else (
        echo [INFO] Detected RAM: Unknown
    )
    echo [INFO] Suggested preset based on your system: !SUGGESTED_PRESET_NAME!
) else (
    echo [INFO] Hardware detection unavailable. Using default suggestion: 3 - Balanced (recommended)
    set "SUGGESTED_PRESET=3"
)

echo        [1] Best performance - faster, potentially lower detection quality
echo        [2] Best detection   - slower, potentially better detection quality
echo        [3] Balanced         - recommended for most users
echo        [C] Cancel
set "PRESET_INPUT="
set /p PRESET_INPUT="[INPUT] Enter 1, 2, or 3 [default !SUGGESTED_PRESET!]: "

if "%PRESET_INPUT%"=="" set "PRESET=!SUGGESTED_PRESET!"
if /I "%PRESET_INPUT%"=="C" (
    echo [INFO] Operation canceled by user.
    call :fail 5 "User canceled preset selection"
    exit /b 1
)
if not "%PRESET_INPUT%"=="" set "PRESET=%PRESET_INPUT%"

call :apply_preset "%PRESET%"
if errorlevel 1 (
    echo [WARN] Invalid preset. Please enter 1, 2, or 3, or C to cancel.
    goto :preset_prompt
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

REM -------------------- Final summary and exit --------------------
:final
call :line
echo SUMMARY
echo   Input file          : "%INPUT_ABS%"
echo   Output file         : "%OUTPUT_ONNX%"
echo   Optimization preset : %PRESET_NAME% ^(imgsz=%IMGSZ%^)
echo   Exit status         : %EXIT_REASON%
echo   Exit code           : %EXIT_CODE%
call :line

if "%DID_PUSHD%"=="1" popd >nul 2>&1
endlocal & exit /b %EXIT_CODE%
