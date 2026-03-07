@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ================================================================
REM convert_to_onnx.bat
REM Converts a YOLO .pt model to ONNX using Ultralytics YOLO.
REM
REM Arguments (same interface):
REM   arg1 = input .pt model path
REM   arg2 = optional output .onnx path
REM   arg3 = optional optimization preset (1, 2, or 3)
REM Optional:
REM   --debug enables verbose debug output (can be passed anywhere).
REM
REM Exit codes:
REM   0 = Success
REM   1 = Input .pt not found / invalid
REM   2 = Ultralytics YOLO (yolo) not installed or not on PATH
REM   3 = Export failed or .onnx not created / not moved
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
set "OUTPUT_ARG="
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
set "LAST_ERRORLEVEL=0"
set "DEBUG_MODE=0"
set "LOG_ENABLED=0"
set "LOG_FILE="

set "RAW_ARG1="
set "RAW_ARG2="
set "RAW_ARG3="
set "NONDEBUG_COUNT=0"
for %%A in (%*) do (
    if /I "%%~A"=="--debug" (
        set "DEBUG_MODE=1"
    ) else (
        set /a NONDEBUG_COUNT+=1
        if !NONDEBUG_COUNT! EQU 1 set "RAW_ARG1=%%~A"
        if !NONDEBUG_COUNT! EQU 2 set "RAW_ARG2=%%~A"
        if !NONDEBUG_COUNT! EQU 3 set "RAW_ARG3=%%~A"
    )
)
if /I "%CONVERT_ONNX_DEBUG%"=="1" set "DEBUG_MODE=1"

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

call :init_logging
call :debug "Debug mode enabled."
call :debug "RAW_ARG1=%RAW_ARG1%"
call :debug "RAW_ARG2=%RAW_ARG2%"
call :debug "RAW_ARG3=%RAW_ARG3%"

REM -------------------- Argument handling and file selection --------------------
if not "%RAW_ARG1%"=="" (
    set "INPUT_PT=%RAW_ARG1%"
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

set "OUTPUT_ARG=%RAW_ARG2%"
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

REM -------------------- Dependency checks --------------------
call :line
echo [STEP] Checking Python...
call :debug "RUN: where python"
where python >nul 2>&1
call :debug_errorlevel "where python"
if errorlevel 1 (
    echo [ERROR] Python is required for Ultralytics YOLO.
    echo         Download Python and enable "Add python.exe to PATH" during install.
    call :fail 4 "Python not installed or not on PATH"
    goto :final
)
call :debug "RUN: python --version"
python --version >nul 2>&1
call :debug_errorlevel "python --version"
if errorlevel 1 (
    echo [ERROR] Python command exists but is not working correctly.
    call :fail 4 "Python not installed or not on PATH"
    goto :final
)
echo [OK] Python is available.

echo [STEP] Checking Ultralytics YOLO CLI ^(yolo^) ...
call :debug "RUN: where yolo"
where yolo >nul 2>&1
call :debug_errorlevel "where yolo"
if errorlevel 1 (
    echo [ERROR] Ultralytics YOLO is not installed or not on PATH.
    echo         Install with: pip install -U ultralytics
    call :fail 2 "Ultralytics YOLO not installed or not on PATH"
    goto :final
)
call :debug "RUN: yolo version"
yolo version >nul 2>&1
call :debug_errorlevel "yolo version"
if errorlevel 1 (
    call :debug "RUN: yolo --help"
    yolo --help >nul 2>&1
    call :debug_errorlevel "yolo --help"
    if errorlevel 1 (
        echo [ERROR] yolo command exists but is not working correctly.
        call :fail 2 "Ultralytics YOLO command check failed"
        goto :final
    )
)
echo [OK] YOLO CLI is available.

REM -------------------- Hardware detection (PowerShell in background) --------------------
call :detect_hardware
if errorlevel 1 (
    echo [WARN] Hardware detection unavailable. Continuing without hardware-based suggestion.
)

REM -------------------- Preset selection --------------------
set "PRESET=%RAW_ARG3%"
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

if exist "%OUTPUT_ONNX%" (
    call :line
    echo [WARN] Output already exists:
    echo        "%OUTPUT_ONNX%"
    call :confirm_overwrite
    if errorlevel 1 goto :final
)
if not exist "%OUTPUT_DIR%" (
    call :debug "RUN: mkdir \"%OUTPUT_DIR%\""
    mkdir "%OUTPUT_DIR%" >nul 2>&1
    call :debug_errorlevel "mkdir output directory"
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
call :debug "RUN: yolo export model=\"%INPUT_ABS%\" format=onnx imgsz=%IMGSZ%"
yolo export model="%INPUT_ABS%" format=onnx imgsz=%IMGSZ%
set "EXPORT_ERROR=%ERRORLEVEL%"
call :debug "ERRORLEVEL after export=%EXPORT_ERROR%"
if not "%EXPORT_ERROR%"=="0" (
    echo [ERROR] Export command failed with code %EXPORT_ERROR%.
    call :fail 3 "Export failed"
    goto :final
)

set "GENERATED_ONNX=%INPUT_DIR%%INPUT_BASE%.onnx"
if not exist "%GENERATED_ONNX%" (
    echo [ERROR] Export command completed, but expected ONNX file was not created:
    echo         "%GENERATED_ONNX%"
    call :fail 3 "Export completed but ONNX file missing"
    goto :final
)

if /I "%GENERATED_ONNX%"=="%OUTPUT_ONNX%" (
    if exist "%OUTPUT_ONNX%" (
        echo [OK] Conversion complete.
        call :fail 0 "Success"
        goto :delete_source_prompt
    ) else (
        echo [ERROR] Export reported success, but output is not present at expected path.
        call :fail 3 "ONNX output missing after export"
        goto :final
    )
)

if exist "%OUTPUT_ONNX%" (
    echo [WARN] Target ONNX exists unexpectedly before move: "%OUTPUT_ONNX%"
)
call :debug "RUN: move /Y \"%GENERATED_ONNX%\" \"%OUTPUT_ONNX%\""
move /Y "%GENERATED_ONNX%" "%OUTPUT_ONNX%" >nul 2>&1
call :debug_errorlevel "move generated onnx"
if errorlevel 1 (
    echo [ERROR] Could not move generated ONNX file to requested output path.
    echo         Source: "%GENERATED_ONNX%"
    echo         Target: "%OUTPUT_ONNX%"
    call :fail 3 "ONNX generated but could not be moved"
    goto :final
)
if not exist "%OUTPUT_ONNX%" (
    echo [ERROR] Move command returned success, but output file is missing:
    echo         "%OUTPUT_ONNX%"
    call :fail 3 "Output ONNX missing after move"
    goto :final
)

echo [OK] Conversion complete.
call :fail 0 "Success"

:delete_source_prompt
set "DELETE_CHOICE="
set /p DELETE_CHOICE="[INPUT] Delete source .pt model after successful conversion? [y/N]: "
if "%DELETE_CHOICE%"=="" set "DELETE_CHOICE=N"
if /I "%DELETE_CHOICE%"=="Y" (
    call :debug "RUN: del /F /Q \"%INPUT_ABS%\""
    del /F /Q "%INPUT_ABS%" >nul 2>&1
    call :debug_errorlevel "delete source pt"
    if errorlevel 1 (
        echo [WARN] Could not delete source model: "%INPUT_ABS%"
    ) else (
        if exist "%INPUT_ABS%" (
            echo [WARN] Source model still exists after delete attempt: "%INPUT_ABS%"
        ) else (
            echo [INFO] Source model deleted.
        )
    )
    goto :final
)
if /I "%DELETE_CHOICE%"=="N" goto :final
echo [WARN] Invalid choice. Keeping source model.
goto :final

:select_input_model
set "PT_COUNT=0"
for /f "delims=" %%F in ('dir /b /a:-d "%~dp0*.pt" 2^>nul') do (
    set /a PT_COUNT+=1
    set "PT_FILE_!PT_COUNT!=%%F"
)
if "%PT_COUNT%"=="0" (
    echo [ERROR] No .pt files were found next to this script:
    echo         "%~dp0"
    echo         Place a .pt model next to this script or pass a full path as arg1.
    call :fail 1 "No input .pt found"
    exit /b 1
)
if "%PT_COUNT%"=="1" (
    set "INPUT_PT=%~dp0!PT_FILE_1!"
    echo [INFO] Using detected model: "!PT_FILE_1!"
    exit /b 0
)

set "MODEL_TRIES=0"
:select_model_prompt
set /a MODEL_TRIES+=1
call :line
echo [INFO] Multiple .pt files found next to this script:
for /L %%N in (1,1,%PT_COUNT%) do echo        [%%N] !PT_FILE_%%N!
set "MODEL_CHOICE="
set /p MODEL_CHOICE="[INPUT] Select the model to convert by number, or press Enter to cancel: "
if "%MODEL_CHOICE%"=="" (
    echo [INFO] Operation canceled by user.
    call :fail 5 "User canceled model selection"
    exit /b 1
)
echo(%MODEL_CHOICE%| findstr /R "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [WARN] Invalid selection. Enter a number between 1 and %PT_COUNT%.
    if %MODEL_TRIES% GEQ 3 (
        call :fail 5 "User entered invalid model selection repeatedly"
        exit /b 1
    )
    goto :select_model_prompt
)
set /a MODEL_INDEX=%MODEL_CHOICE% >nul 2>&1
if errorlevel 1 (
    echo [WARN] Invalid selection. Enter a valid number.
    if %MODEL_TRIES% GEQ 3 (
        call :fail 5 "User entered invalid model selection repeatedly"
        exit /b 1
    )
    goto :select_model_prompt
)
if %MODEL_INDEX% LSS 1 (
    echo [WARN] Invalid selection. Enter a number between 1 and %PT_COUNT%.
    if %MODEL_TRIES% GEQ 3 (
        call :fail 5 "User entered invalid model selection repeatedly"
        exit /b 1
    )
    goto :select_model_prompt
)
if %MODEL_INDEX% GTR %PT_COUNT% (
    echo [WARN] Invalid selection. Enter a number between 1 and %PT_COUNT%.
    if %MODEL_TRIES% GEQ 3 (
        call :fail 5 "User entered invalid model selection repeatedly"
        exit /b 1
    )
    goto :select_model_prompt
)
call set "INPUT_PT=%%~dp0%%PT_FILE_%MODEL_INDEX%%%"
if "%INPUT_PT%"=="" (
    echo [ERROR] Failed to resolve selected model.
    call :fail 5 "Invalid model selection"
    exit /b 1
)
echo [INFO] Using selected model: "!PT_FILE_%MODEL_INDEX%!"
exit /b 0

:detect_hardware
set "GPU_NAME="
set "CPU_NAME="
set "RAM_GB="
set "HARDWARE_DETECTED=0"
set "SUGGESTED_PRESET=3"
set "SUGGESTED_PRESET_NAME=3 - Balanced (recommended)"

call :debug "RUN: where powershell"
where powershell >nul 2>&1
call :debug_errorlevel "where powershell"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%G in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; (Get-CimInstance Win32_VideoController ^| Select-Object -First 1 -ExpandProperty Name)" 2^>nul`) do if not defined GPU_NAME set "GPU_NAME=%%G"
for /f "usebackq delims=" %%C in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; (Get-CimInstance Win32_Processor ^| Select-Object -First 1 -ExpandProperty Name)" 2^>nul`) do if not defined CPU_NAME set "CPU_NAME=%%C"
for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; ([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB))" 2^>nul`) do if not defined RAM_GB set "RAM_GB=%%R"

if defined GPU_NAME set "HARDWARE_DETECTED=1"
if defined CPU_NAME set "HARDWARE_DETECTED=1"
if defined RAM_GB set "HARDWARE_DETECTED=1"
if "%HARDWARE_DETECTED%"=="0" exit /b 1

set "IS_HIGH_GPU=0"
set "IS_LOW_GPU=0"
set "RAM_NUM="
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
    if errorlevel 1 set "RAM_NUM="
)
if defined RAM_NUM if !RAM_NUM! LSS 8 set "SUGGESTED_PRESET=1"
if "%SUGGESTED_PRESET%"=="3" if "%IS_LOW_GPU%"=="1" set "SUGGESTED_PRESET=1"
if "%SUGGESTED_PRESET%"=="3" if "%IS_HIGH_GPU%"=="1" if defined RAM_NUM if !RAM_NUM! GEQ 16 set "SUGGESTED_PRESET=2"

call :apply_preset "%SUGGESTED_PRESET%" >nul 2>&1
if errorlevel 1 (
    set "SUGGESTED_PRESET=3"
    call :apply_preset "3" >nul 2>&1
)
set "SUGGESTED_PRESET_NAME=%PRESET_NAME%"
call :debug "Detected GPU=!GPU_NAME!"
call :debug "Detected CPU=!CPU_NAME!"
call :debug "Detected RAM_GB=!RAM_GB!"
call :debug "Suggested preset=!SUGGESTED_PRESET!"
exit /b 0

:prompt_preset
set "PRESET_TRIES=0"
:preset_prompt
set /a PRESET_TRIES+=1
call :line
echo [INFO] Select optimization preset ^(Balanced is recommended^):
if "%HARDWARE_DETECTED%"=="1" (
    if defined GPU_NAME echo [INFO] Detected GPU: !GPU_NAME!
    if defined CPU_NAME echo [INFO] Detected CPU: !CPU_NAME!
    if defined RAM_GB (echo [INFO] Detected RAM: !RAM_GB! GB) else echo [INFO] Detected RAM: Unknown
    echo [INFO] Suggested preset based on your system: !SUGGESTED_PRESET_NAME!
) else (
    echo [INFO] Hardware detection unavailable. Using default suggestion: 3 - Balanced (recommended)
    set "SUGGESTED_PRESET=3"
)
echo        [1] Best performance - faster, potentially lower detection quality
echo        [2] Best detection   - slower, potentially better detection quality
echo        [3] Balanced         - recommended for most users
set "PRESET_INPUT="
set /p PRESET_INPUT="[INPUT] Enter 1, 2, or 3 [default !SUGGESTED_PRESET!]: "
if "%PRESET_INPUT%"=="" (
    set "PRESET=!SUGGESTED_PRESET!"
) else (
    set "PRESET=%PRESET_INPUT%"
)
call :apply_preset "%PRESET%"
if errorlevel 1 (
    echo [WARN] Invalid preset. Please enter 1, 2, or 3.
    if %PRESET_TRIES% GEQ 3 (
        call :fail 5 "User entered invalid preset repeatedly"
        exit /b 1
    )
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
set "OVERWRITE_TRIES=0"
:overwrite_prompt
set /a OVERWRITE_TRIES+=1
set "OVERWRITE_CHOICE="
set /p OVERWRITE_CHOICE="[INPUT] Overwrite existing output file? [y/N]: "
if "%OVERWRITE_CHOICE%"=="" set "OVERWRITE_CHOICE=N"
if /I "%OVERWRITE_CHOICE%"=="Y" (
    call :debug "RUN: del /F /Q \"%OUTPUT_ONNX%\""
    del /F /Q "%OUTPUT_ONNX%" >nul 2>&1
    call :debug_errorlevel "delete existing output"
    if errorlevel 1 (
        echo [ERROR] Could not remove existing output file.
        call :fail 5 "Cannot overwrite existing output file"
        exit /b 1
    )
    if exist "%OUTPUT_ONNX%" (
        echo [ERROR] Existing output file still present after delete attempt.
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
if %OVERWRITE_TRIES% GEQ 3 (
    call :fail 5 "User entered invalid overwrite choice repeatedly"
    exit /b 1
)
goto :overwrite_prompt

:init_logging
set "LOG_DIR=%~dp0logs"
set "LOG_FILE=%LOG_DIR%\convert_to_onnx.log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" (
    echo [WARN] Logging disabled: could not create log directory "%LOG_DIR%".
    set "LOG_ENABLED=0"
    exit /b 0
)
>>"%LOG_FILE%" echo.
if errorlevel 1 (
    echo [WARN] Logging disabled: could not write log file "%LOG_FILE%".
    set "LOG_ENABLED=0"
    exit /b 0
)
set "LOG_ENABLED=1"
exit /b 0

:log
if not "%LOG_ENABLED%"=="1" exit /b 0
set "LOG_TEXT=%~1"
>>"%LOG_FILE%" echo [%date% %time%] %LOG_TEXT%
if errorlevel 1 echo [WARN] Failed to append to log file.
exit /b 0

:debug
if not "%DEBUG_MODE%"=="1" exit /b 0
echo [INFO] [DEBUG] %~1
call :log "DEBUG: %~1"
exit /b 0

:debug_errorlevel
if not "%DEBUG_MODE%"=="1" exit /b 0
echo [INFO] [DEBUG] ERRORLEVEL after %~1 = %ERRORLEVEL%
call :log "DEBUG: ERRORLEVEL after %~1 = %ERRORLEVEL%"
exit /b 0

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
set "LAST_ERRORLEVEL=%ERRORLEVEL%"
call :line
echo SUMMARY
echo   Input file          : "%INPUT_ABS%"
echo   Output file         : "%OUTPUT_ONNX%"
echo   Optimization preset : %PRESET_NAME% ^(imgsz=%IMGSZ%^)
if "%HARDWARE_DETECTED%"=="1" (
    echo   Hardware GPU       : %GPU_NAME%
    echo   Hardware CPU       : %CPU_NAME%
    echo   Hardware RAM ^(GB^)  : %RAM_GB%
)
echo   Exit status         : %EXIT_REASON%
echo   Exit code           : %EXIT_CODE%
echo   Final ERRORLEVEL    : %LAST_ERRORLEVEL%
call :line
call :log "Input=%INPUT_ABS%"
call :log "Output=%OUTPUT_ONNX%"
call :log "Preset=%PRESET_NAME% imgsz=%IMGSZ%"
call :log "GPU=%GPU_NAME% CPU=%CPU_NAME% RAM_GB=%RAM_GB%"
call :log "ExitCode=%EXIT_CODE% ExitReason=%EXIT_REASON% FinalErrorlevel=%LAST_ERRORLEVEL%"
if "%DID_PUSHD%"=="1" popd >nul 2>&1
endlocal & exit /b %EXIT_CODE%
