@echo off
REM === SELF-LAUNCH: Opens CMD window + runs interactive ===
if defined AUTOMATED_MODE goto :main
if /I "%~1"=="--interactive" (
    set "AUTOMATED_MODE=1"
    shift
    goto :main
)
if "%~1"=="" (
    start cmd /k "cd /d ""%~dp0"" && set AUTOMATED_MODE=1 && ""%~f0"" --interactive"
    exit /b
)
:main
setlocal EnableExtensions DisableDelayedExpansion

REM ================================================================
REM convert_to_onnx.bat
REM Converts a YOLO .pt model to ONNX using Ultralytics YOLO.
REM
REM Arguments (unchanged interface):
REM   arg1 = input .pt model path
REM   arg2 = optional output .onnx path
REM   arg3 = optional optimization preset (1, 2, or 3)
REM Optional flags:
REM   --dry-run  : validate and print planned actions, execute nothing mutating
REM   --yes      : auto-accept overwrite/delete prompts
REM   --verbose  : print extra diagnostics and write logs
REM   --debug    : alias of --verbose
REM
REM Exit codes:
REM   0 = Success
REM   1 = Input .pt not found / invalid
REM   2 = Ultralytics YOLO (yolo) not installed or not on PATH
REM   3 = Export failed or .onnx not created / not moved
REM   4 = Python not installed or not on PATH
REM   5 = User canceled or other unrecoverable error
REM      subtype 5.1 = user canceled
REM      subtype 5.2 = internal/unrecoverable runtime error
REM ================================================================

set "STATE_EXIT_CODE=0"
set "STATE_EXIT_REASON=Success"
set "STATE_EXIT_SUBCODE=0"
set "STATE_DID_PUSHD=0"
set "STATE_LAST_ERRORLEVEL=0"
set "STATE_DRY_RUN=0"
set "STATE_ASSUME_YES=0"
set "STATE_VERBOSE=0"
set "STATE_LOG_ENABLED=0"
set "STATE_LOG_FILE="
set "STATE_TEMP_FILE="
set "STATE_PYTHON_CMD="
set "STATE_PYTHON_WHERE="
set "STATE_YOLO_WHERE="
set "STATE_HW_DETECTED=0"
set "STATE_HW_GPU="
set "STATE_HW_CPU="
set "STATE_HW_RAM_GB="
set "STATE_SUGGESTED_PRESET=3"
set "STATE_UNC_WARNING=0"
set "STATE_READONLY_WARNING=0"
set "STATE_INTERACTIVE=0"

set "ARG_INPUT="
set "ARG_OUTPUT="
set "ARG_PRESET="
set "RESOLVED_INPUT="
set "RESOLVED_INPUT_DIR="
set "RESOLVED_INPUT_BASE="
set "RESOLVED_INPUT_NAME="
set "RESOLVED_OUTPUT="
set "RESOLVED_OUTPUT_DIR="
set "RESOLVED_OUTPUT_NAME="
set "RESOLVED_GENERATED_ONNX="
set "CURRENT_PRESET=3"
set "CURRENT_PRESET_NAME=3 - Balanced (recommended)"
set "CURRENT_PRESET_DESC=Balanced speed and detection quality for most users"
set "CURRENT_IMGSZ=960"
set "STATE_EXPORT_RC=0"
set "STATE_MOVE_RC=0"
set "STATE_DELETE_RC=0"
set "STATE_FAILING_COMMAND="

set "STATE_POSITIONAL_COUNT=0"

call :line
call :title "YOLO .PT TO ONNX CONVERTER"
call :line

goto :parse_args

:parse_args
if "%~1"=="" goto :validate
set "STATE_TOKEN=%~1"
if /I "%STATE_TOKEN%"=="--dry-run" (
    set "STATE_DRY_RUN=1"
    shift
    goto :parse_args
)
if /I "%STATE_TOKEN%"=="--yes" (
    set "STATE_ASSUME_YES=1"
    shift
    goto :parse_args
)
if /I "%STATE_TOKEN%"=="--verbose" (
    set "STATE_VERBOSE=1"
    shift
    goto :parse_args
)
if /I "%STATE_TOKEN%"=="--debug" (
    set "STATE_VERBOSE=1"
    shift
    goto :parse_args
)
if /I "%STATE_TOKEN%"=="--interactive" (
    set "STATE_INTERACTIVE=1"
    shift
    goto :parse_args
)
if "%STATE_TOKEN:~0,2%"=="--" (
    echo [ERROR] Unknown flag: "%STATE_TOKEN%"
    call :fail 5 "Unknown flag provided" 2
    goto :final
)
set /a STATE_POSITIONAL_COUNT+=1
if "%STATE_POSITIONAL_COUNT%"=="1" set "ARG_INPUT=%~1"
if "%STATE_POSITIONAL_COUNT%"=="2" set "ARG_OUTPUT=%~1"
if "%STATE_POSITIONAL_COUNT%"=="3" set "ARG_PRESET=%~1"
shift
goto :parse_args

:validate
if /I "%DEBUG%"=="1" set "STATE_VERBOSE=1"

pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not switch to script directory: "%~dp0"
    call :fail 5 "Could not switch to script directory" 2
    goto :final
)
set "STATE_DID_PUSHD=1"

call :init_logging
call :log "args=%*"
call :debug "ARG_INPUT=%ARG_INPUT%"
call :debug "ARG_OUTPUT=%ARG_OUTPUT%"
call :debug "ARG_PRESET=%ARG_PRESET%"

if "%STATE_INTERACTIVE%"=="1" (
    call :line
    echo        YOLO PT^>ONNX CONVERTER v2.0 - INTERACTIVE
    call :line
)

if not "%ARG_INPUT%"=="" (
    set "RESOLVED_INPUT=%ARG_INPUT%"
) else (
    if "%STATE_INTERACTIVE%"=="1" echo 1. Scanning .pt files...
    call :select_input_model
    if errorlevel 1 goto :final
)

for %%I in ("%RESOLVED_INPUT%") do (
    set "RESOLVED_INPUT=%%~fI"
    set "RESOLVED_INPUT_DIR=%%~dpI"
    set "RESOLVED_INPUT_BASE=%%~nI"
    set "RESOLVED_INPUT_NAME=%%~nxI"
)

if "%RESOLVED_INPUT%"=="" (
    echo [ERROR] No input model path could be resolved.
    call :missing_pt_help
    call :fail 1 "Input .pt file not found / invalid" 0
    goto :final
)
if /I not "%RESOLVED_INPUT:~-3%"==".pt" (
    echo [ERROR] Input file must be a .pt model: "%RESOLVED_INPUT%"
    call :missing_pt_help
    call :fail 1 "Input file extension is not .pt" 0
    goto :final
)
if not exist "%RESOLVED_INPUT%" (
    echo [ERROR] Input file not found: "%RESOLVED_INPUT%"
    call :missing_pt_help
    call :fail 1 "Input .pt file not found" 0
    goto :final
)
echo [OK] Input model found: "%RESOLVED_INPUT%"

if "%ARG_OUTPUT%"=="" (
    if "%STATE_INTERACTIVE%"=="1" (
        call :prompt_output_name
        if errorlevel 1 goto :final
    ) else (
        set "RESOLVED_OUTPUT=%RESOLVED_INPUT_DIR%%RESOLVED_INPUT_BASE%.onnx"
    )
) else (
    for %%O in ("%ARG_OUTPUT%") do set "RESOLVED_OUTPUT=%%~fO"
    if /I not "%RESOLVED_OUTPUT:~-5%"==".onnx" set "RESOLVED_OUTPUT=%RESOLVED_OUTPUT%.onnx"
)
for %%O in ("%RESOLVED_OUTPUT%") do (
    set "RESOLVED_OUTPUT=%%~fO"
    set "RESOLVED_OUTPUT_DIR=%%~dpO"
    set "RESOLVED_OUTPUT_NAME=%%~nxO"
)

if "%RESOLVED_OUTPUT_DIR%"=="" (
    echo [ERROR] Could not resolve output directory from "%RESOLVED_OUTPUT%".
    call :fail 5 "Invalid output path" 2
    goto :final
)

echo %RESOLVED_OUTPUT_DIR%| findstr /B "\\\\" >nul 2>&1
if not errorlevel 1 (
    set "STATE_UNC_WARNING=1"
    echo [WARN] Output directory is UNC path. Network latency/permissions may affect export.
)

if not exist "%RESOLVED_OUTPUT_DIR%" (
    call :run_cmd "mkdir \"%RESOLVED_OUTPUT_DIR%\"" "mkdir output directory"
    if errorlevel 1 (
        echo [ERROR] Could not create output directory: "%RESOLVED_OUTPUT_DIR%"
        call :fail 5 "Failed to create output directory" 2
        goto :final
    )
)

call :preflight_writable "%RESOLVED_OUTPUT_DIR%"
if errorlevel 1 goto :final

goto :detect

:detect
call :line
echo [STEP] Detecting Python...
call :detect_python
if errorlevel 1 goto :final
echo [OK] Python is available: %STATE_PYTHON_CMD%

if not "%STATE_PYTHON_WHERE%"=="" (
    call :debug "PATH lookup: %STATE_PYTHON_WHERE%"
    call :path_len_warn "%STATE_PYTHON_WHERE%" "python"
)

call :line
echo [STEP] Checking Ultralytics YOLO CLI ^(yolo^) ...
where yolo >nul 2>&1
set "STATE_TMP_RC=%ERRORLEVEL%"
call :debug "where yolo rc=%STATE_TMP_RC%"
if not "%STATE_TMP_RC%"=="0" (
    echo [ERROR] Ultralytics YOLO is not installed or not on PATH.
    echo         Install with: pip install -U ultralytics
    call :fail 2 "Ultralytics YOLO not installed or not on PATH" 0
    goto :final
)
for /f "delims=" %%W in ('where yolo 2^>nul') do if not defined STATE_YOLO_WHERE set "STATE_YOLO_WHERE=%%W"
if not "%STATE_YOLO_WHERE%"=="" call :path_len_warn "%STATE_YOLO_WHERE%" "yolo"

yolo version >nul 2>&1
set "STATE_TMP_RC=%ERRORLEVEL%"
if not "%STATE_TMP_RC%"=="0" (
    echo [ERROR] yolo command exists but is not working correctly.
    echo         Try: pip install -U ultralytics
    call :fail 2 "Ultralytics YOLO command check failed" 0
    goto :final
)
echo [OK] YOLO CLI is available.

call :detect_hardware
if errorlevel 1 (
    echo [WARN] Hardware detection unavailable. Using preset suggestion: 3 - Balanced (recommended)
    set "STATE_SUGGESTED_PRESET=3"
)

if "%ARG_PRESET%"=="" (
    if "%STATE_INTERACTIVE%"=="1" echo 3. Preset: [Enter=Auto hardware detect]
    call :prompt_preset
    if errorlevel 1 goto :final
) else (
    set "CURRENT_PRESET=%ARG_PRESET%"
    call :apply_preset "%CURRENT_PRESET%"
    if errorlevel 1 (
        echo [ERROR] Invalid preset argument "%ARG_PRESET%". Use 1, 2, or 3.
        call :fail 5 "Invalid preset argument" 2
        goto :final
    )
)

if "%ARG_OUTPUT%"=="" (
    if "%STATE_INTERACTIVE%"=="0" (
        if "%CURRENT_PRESET%"=="1" set "RESOLVED_OUTPUT=%RESOLVED_INPUT_DIR%%RESOLVED_INPUT_BASE%_best_performance.onnx"
        if "%CURRENT_PRESET%"=="2" set "RESOLVED_OUTPUT=%RESOLVED_INPUT_DIR%%RESOLVED_INPUT_BASE%_best_detection.onnx"
        if "%CURRENT_PRESET%"=="3" set "RESOLVED_OUTPUT=%RESOLVED_INPUT_DIR%%RESOLVED_INPUT_BASE%_best_balanced.onnx"
        for %%O in ("%RESOLVED_OUTPUT%") do (
            set "RESOLVED_OUTPUT=%%~fO"
            set "RESOLVED_OUTPUT_DIR=%%~dpO"
            set "RESOLVED_OUTPUT_NAME=%%~nxO"
        )
    )
)

if exist "%RESOLVED_OUTPUT%" (
    if "%STATE_ASSUME_YES%"=="1" (
        echo [INFO] --yes enabled; removing existing output.
        if "%STATE_DRY_RUN%"=="1" (
            echo [RUN ] DRY-RUN del /F /Q "%RESOLVED_OUTPUT%"
        ) else (
            del /F /Q "%RESOLVED_OUTPUT%" >nul 2>&1
            set "STATE_TMP_RC=%ERRORLEVEL%"
            if not "%STATE_TMP_RC%"=="0" (
                echo [ERROR] Could not remove existing output file: "%RESOLVED_OUTPUT%"
                call :fail 5 "Cannot overwrite existing output file" 2
                goto :final
            )
        )
    ) else (
        call :prompt_yes_no_cancel "Overwrite existing output file?" "N" "OVERWRITE_CHOICE"
        if errorlevel 1 goto :final
        if /I "%OVERWRITE_CHOICE%"=="C" (
            call :fail 5 "User canceled because output already exists" 1
            goto :final
        )
        if /I "%OVERWRITE_CHOICE%"=="Y" (
            if "%STATE_DRY_RUN%"=="1" (
                echo [RUN ] DRY-RUN del /F /Q "%RESOLVED_OUTPUT%"
            ) else (
                del /F /Q "%RESOLVED_OUTPUT%" >nul 2>&1
                set "STATE_TMP_RC=%ERRORLEVEL%"
                if not "%STATE_TMP_RC%"=="0" (
                    echo [ERROR] Could not remove existing output file: "%RESOLVED_OUTPUT%"
                    call :fail 5 "Cannot overwrite existing output file" 2
                    goto :final
                )
            )
        ) else (
            call :fail 5 "User canceled overwrite" 1
            goto :final
        )
    )
)

goto :export

:export
if "%STATE_INTERACTIVE%"=="1" echo [STEP] Starting conversion...
call :line
echo [PLAN] Input file : "%RESOLVED_INPUT%"
echo [PLAN] Output file: "%RESOLVED_OUTPUT%"
echo [PLAN] Preset     : %CURRENT_PRESET_NAME%
echo [PLAN] Why        : %CURRENT_PRESET_DESC%
if "%STATE_HW_DETECTED%"=="1" (
    if not "%STATE_HW_GPU%"=="" echo [INFO] GPU: %STATE_HW_GPU%
    if not "%STATE_HW_CPU%"=="" echo [INFO] CPU: %STATE_HW_CPU%
    if not "%STATE_HW_RAM_GB%"=="" echo [INFO] RAM: %STATE_HW_RAM_GB% GB
)
if "%STATE_DRY_RUN%"=="1" (
    echo [INFO] DRY-RUN mode is ON. No export/delete/move operations will execute.
)
call :line

set "RESOLVED_GENERATED_ONNX=%RESOLVED_INPUT_DIR%%RESOLVED_INPUT_BASE%.onnx"
if "%STATE_DRY_RUN%"=="1" (
    echo [RUN ] DRY-RUN yolo export model="%RESOLVED_INPUT%" format=onnx imgsz=%CURRENT_IMGSZ%
    if /I not "%RESOLVED_GENERATED_ONNX%"=="%RESOLVED_OUTPUT%" (
        echo [RUN ] DRY-RUN move /Y "%RESOLVED_GENERATED_ONNX%" "%RESOLVED_OUTPUT%"
    )
    echo [OK] DRY-RUN complete. Validation passed.
    call :fail 0 "Dry-run success" 0
    goto :cleanup
)

echo [RUN ] Exporting with Ultralytics YOLO...
echo [RUN ] yolo export model="%RESOLVED_INPUT%" format=onnx imgsz=%CURRENT_IMGSZ%
yolo export model="%RESOLVED_INPUT%" format=onnx imgsz=%CURRENT_IMGSZ%
set "STATE_EXPORT_RC=%ERRORLEVEL%"
if not "%STATE_EXPORT_RC%"=="0" (
    if exist "%RESOLVED_GENERATED_ONNX%" del /F /Q "%RESOLVED_GENERATED_ONNX%" >nul 2>&1
    echo [ERROR] Export command failed with code %STATE_EXPORT_RC%.
    echo         Manual retry:
    echo         yolo export model="%RESOLVED_INPUT%" format=onnx imgsz=%CURRENT_IMGSZ%
    call :fail 3 "Export failed" 0
    goto :cleanup
)

if not exist "%RESOLVED_GENERATED_ONNX%" (
    echo [ERROR] Export completed, but ONNX was not created: "%RESOLVED_GENERATED_ONNX%"
    call :fail 3 "Export completed but ONNX file missing" 0
    goto :cleanup
)

if /I not "%RESOLVED_GENERATED_ONNX%"=="%RESOLVED_OUTPUT%" (
    move /Y "%RESOLVED_GENERATED_ONNX%" "%RESOLVED_OUTPUT%" >nul 2>&1
    set "STATE_MOVE_RC=%ERRORLEVEL%"
    if not "%STATE_MOVE_RC%"=="0" (
        echo [ERROR] Could not move generated ONNX file to requested output path.
        echo         File remains at "%RESOLVED_GENERATED_ONNX%"
        call :fail 3 "ONNX generated but could not be moved" 0
        goto :cleanup
    )
)

if not exist "%RESOLVED_OUTPUT%" (
    echo [ERROR] Output ONNX missing after export/move: "%RESOLVED_OUTPUT%"
    call :fail 3 "Output ONNX missing after move" 0
    goto :cleanup
)

echo [OK] Conversion complete.

if "%STATE_ASSUME_YES%"=="1" (
    set "DELETE_CHOICE=Y"
) else (
    call :prompt_yes_no_cancel "Delete source .pt model after successful conversion?" "N" "DELETE_CHOICE"
    if errorlevel 1 goto :cleanup
)

if /I "%DELETE_CHOICE%"=="C" (
    call :fail 5 "User canceled at delete prompt" 1
    goto :cleanup
)
if /I "%DELETE_CHOICE%"=="Y" (
    del /F /Q "%RESOLVED_INPUT%" >nul 2>&1
    set "STATE_DELETE_RC=%ERRORLEVEL%"
    if not "%STATE_DELETE_RC%"=="0" (
        echo [WARN] Could not delete source model.
        echo        File remains at "%RESOLVED_INPUT%"
    ) else (
        if exist "%RESOLVED_INPUT%" (
            echo [WARN] Delete reported success but file remains at "%RESOLVED_INPUT%"
        ) else (
            echo [INFO] Source model deleted.
        )
    )
)

if "%STATE_EXIT_CODE%"=="0" call :fail 0 "Success" 0

goto :cleanup

:cleanup
if defined STATE_TEMP_FILE (
    if exist "%STATE_TEMP_FILE%" del /F /Q "%STATE_TEMP_FILE%" >nul 2>&1
)
goto :final

:final
set "STATE_LAST_ERRORLEVEL=%ERRORLEVEL%"
call :line
echo SUMMARY
echo   Input file          : "%RESOLVED_INPUT%"
echo   Output file         : "%RESOLVED_OUTPUT%"
echo   Optimization preset : %CURRENT_PRESET_NAME% ^(imgsz=%CURRENT_IMGSZ%^)
if "%STATE_HW_DETECTED%"=="1" (
    if not "%STATE_HW_GPU%"=="" echo   Hardware GPU       : %STATE_HW_GPU%
    if not "%STATE_HW_CPU%"=="" echo   Hardware CPU       : %STATE_HW_CPU%
    if not "%STATE_HW_RAM_GB%"=="" echo   Hardware RAM ^(GB^)  : %STATE_HW_RAM_GB%
)
if "%STATE_UNC_WARNING%"=="1" echo   Warning             : UNC path detected
if "%STATE_READONLY_WARNING%"=="1" echo   Warning             : Read-only/permission risk detected
echo   Exit status         : %STATE_EXIT_REASON%
if "%STATE_EXIT_CODE%"=="5" echo   Exit code detail     : 5.%STATE_EXIT_SUBCODE%
echo   Exit code           : %STATE_EXIT_CODE%
echo   Final ERRORLEVEL    : %STATE_LAST_ERRORLEVEL%
call :line

call :log "input=%RESOLVED_INPUT%"
call :log "output=%RESOLVED_OUTPUT%"
call :log "preset=%CURRENT_PRESET% imgsz=%CURRENT_IMGSZ% name=%CURRENT_PRESET_NAME%"
call :log "gpu=%STATE_HW_GPU% cpu=%STATE_HW_CPU% ram=%STATE_HW_RAM_GB%"
call :log "export_rc=%STATE_EXPORT_RC% move_rc=%STATE_MOVE_RC% delete_rc=%STATE_DELETE_RC%"
call :log "exit_code=%STATE_EXIT_CODE% exit_subcode=%STATE_EXIT_SUBCODE% exit_reason=%STATE_EXIT_REASON%"

if "%STATE_DID_PUSHD%"=="1" popd >nul 2>&1
endlocal & exit /b %STATE_EXIT_CODE%

:detect_python
set "STATE_PYTHON_CMD="
set "STATE_PYTHON_WHERE="

py -3 --version >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    set "STATE_PYTHON_CMD=py -3"
    for /f "delims=" %%W in ('where py 2^>nul') do if not defined STATE_PYTHON_WHERE set "STATE_PYTHON_WHERE=%%W"
    exit /b 0
)
python3 --version >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    set "STATE_PYTHON_CMD=python3"
    for /f "delims=" %%W in ('where python3 2^>nul') do if not defined STATE_PYTHON_WHERE set "STATE_PYTHON_WHERE=%%W"
    exit /b 0
)
python --version >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    set "STATE_PYTHON_CMD=python"
    for /f "delims=" %%W in ('where python 2^>nul') do if not defined STATE_PYTHON_WHERE set "STATE_PYTHON_WHERE=%%W"
    exit /b 0
)

echo [ERROR] Python is required for Ultralytics YOLO.
echo         Install Python and enable "Add python.exe to PATH" during setup.
call :fail 4 "Python not installed or not on PATH" 0
exit /b 1

:detect_hardware
set "STATE_HW_DETECTED=0"
set "STATE_HW_GPU="
set "STATE_HW_CPU="
set "STATE_HW_RAM_GB="

where powershell >nul 2>&1
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%G in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Get-CimInstance Win32_VideoController ^| Select-Object -First 1 -Expand Name" 2^>nul`) do if not defined STATE_HW_GPU set "STATE_HW_GPU=%%G"
for /f "usebackq delims=" %%C in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Get-CimInstance Win32_Processor ^| Select-Object -First 1 -Expand Name" 2^>nul`) do if not defined STATE_HW_CPU set "STATE_HW_CPU=%%C"
for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" 2^>nul`) do if not defined STATE_HW_RAM_GB set "STATE_HW_RAM_GB=%%R"

if defined STATE_HW_GPU set "STATE_HW_DETECTED=1"
if defined STATE_HW_CPU set "STATE_HW_DETECTED=1"
if defined STATE_HW_RAM_GB set "STATE_HW_DETECTED=1"
if "%STATE_HW_DETECTED%"=="0" exit /b 1

set "STATE_SUGGESTED_PRESET=3"

echo %STATE_HW_GPU%| find /I "RTX" >nul && set "STATE_SUGGESTED_PRESET=2"
if "%STATE_SUGGESTED_PRESET%"=="3" echo %STATE_HW_GPU%| find /I "Intel" >nul && set "STATE_SUGGESTED_PRESET=1"
if "%STATE_SUGGESTED_PRESET%"=="3" echo %STATE_HW_GPU%| find /I "UHD" >nul && set "STATE_SUGGESTED_PRESET=1"
if not "%STATE_HW_RAM_GB%"=="" (
    set /a STATE_RAM_NUM=%STATE_HW_RAM_GB%+0 >nul 2>&1
    if not errorlevel 1 (
        if %STATE_RAM_NUM% LSS 8 set "STATE_SUGGESTED_PRESET=1"
        if %STATE_RAM_NUM% GEQ 16 if not "%STATE_SUGGESTED_PRESET%"=="1" echo %STATE_HW_GPU%| find /I "RTX" >nul && set "STATE_SUGGESTED_PRESET=2"
    )
)

exit /b 0

:prompt_preset
call :line
echo [INFO] Select optimization preset ^(Balanced is recommended^)
if "%STATE_HW_DETECTED%"=="1" (
    if not "%STATE_HW_GPU%"=="" echo [INFO] Detected GPU: %STATE_HW_GPU%
    if not "%STATE_HW_CPU%"=="" echo [INFO] Detected CPU: %STATE_HW_CPU%
    if not "%STATE_HW_RAM_GB%"=="" echo [INFO] Detected RAM: %STATE_HW_RAM_GB% GB
)
echo [INFO] Suggested preset: %STATE_SUGGESTED_PRESET%
echo        [1] Best performance - faster, lower compute

echo        [2] Best detection   - higher quality, slower
echo        [3] Balanced         - recommended
call :validate_input "Enter 1, 2, or 3 [default %STATE_SUGGESTED_PRESET%]: " "%STATE_SUGGESTED_PRESET%" "1 2 3" "3" "CURRENT_PRESET"
if errorlevel 1 exit /b 1
call :apply_preset "%CURRENT_PRESET%"
if errorlevel 1 (
    call :fail 5 "Invalid preset selection" 2
    exit /b 1
)
exit /b 0

:apply_preset
if "%~1"=="1" (
    set "CURRENT_PRESET=1"
    set "CURRENT_IMGSZ=640"
    set "CURRENT_PRESET_NAME=1 - Best performance"
    set "CURRENT_PRESET_DESC=Smaller image size for faster runtime"
    exit /b 0
)
if "%~1"=="2" (
    set "CURRENT_PRESET=2"
    set "CURRENT_IMGSZ=1280"
    set "CURRENT_PRESET_NAME=2 - Best detection"
    set "CURRENT_PRESET_DESC=Larger image size for better potential accuracy"
    exit /b 0
)
if "%~1"=="3" (
    set "CURRENT_PRESET=3"
    set "CURRENT_IMGSZ=960"
    set "CURRENT_PRESET_NAME=3 - Balanced (recommended)"
    set "CURRENT_PRESET_DESC=Balanced speed and detection quality for most users"
    exit /b 0
)
exit /b 1

:select_input_model
setlocal EnableDelayedExpansion
set "STATE_PT_COUNT=0"
for /f "delims=" %%F in ('dir /b /a:-d "%~dp0*.pt" 2^>nul') do (
    set /a STATE_PT_COUNT+=1
    set "STATE_PT_FILE_!STATE_PT_COUNT!=%%F"
)

if "!STATE_PT_COUNT!"=="0" (
    endlocal
    echo [ERROR] No .pt files found next to this script.
    call :missing_pt_help
    call :fail 1 "No input .pt found" 0
    exit /b 1
)
if "!STATE_PT_COUNT!"=="1" (
    for %%Q in ("%~dp0!STATE_PT_FILE_1!") do endlocal & set "RESOLVED_INPUT=%%~fQ" & echo [INFO] Using: %%~nxQ & exit /b 0
)

call :line
echo [INFO] Multiple .pt files found:
for /L %%N in (1,1,!STATE_PT_COUNT!) do echo        [%%N] !STATE_PT_FILE_%%N!
echo        [C] Cancel

set "STATE_SELECT_TRY=0"
:select_loop
set /a STATE_SELECT_TRY+=1
set "STATE_CHOICE="
if "%STATE_INTERACTIVE%"=="1" (
    set /p STATE_CHOICE=[INPUT] Select model ^(1-!STATE_PT_COUNT!^) [Enter=1, C=Cancel]: 
    if "!STATE_CHOICE!"=="" set "STATE_CHOICE=1"
) else (
    set /p STATE_CHOICE=[INPUT] Select model number [1-!STATE_PT_COUNT!] or C: 
    if "!STATE_CHOICE!"=="" set "STATE_CHOICE=C"
)
if /I "!STATE_CHOICE!"=="C" (
    endlocal
    call :fail 5 "User canceled model selection" 1
    exit /b 1
)
echo(!STATE_CHOICE!| findstr /R "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 (
    echo [WARN] Invalid selection.
    if !STATE_SELECT_TRY! GEQ 3 (
        endlocal
        call :fail 5 "Invalid model selection attempts exceeded" 2
        exit /b 1
    )
    goto :select_loop
)
set /a STATE_NUM=!STATE_CHOICE! >nul 2>&1
if !STATE_NUM! LSS 1 goto :select_bad
if !STATE_NUM! GTR !STATE_PT_COUNT! goto :select_bad
call set "STATE_PICK=%%STATE_PT_FILE_!STATE_NUM!%%"
for %%Q in ("%~dp0!STATE_PICK!") do endlocal & set "RESOLVED_INPUT=%%~fQ" & echo [INFO] Using: %%~nxQ & exit /b 0

:select_bad
echo [WARN] Selection out of range.
if !STATE_SELECT_TRY! GEQ 3 (
    endlocal
    call :fail 5 "Invalid model selection attempts exceeded" 2
    exit /b 1
)
goto :select_loop

:prompt_output_name
if not "%STATE_INTERACTIVE%"=="1" exit /b 0
echo 2. Output filename: [Enter=%RESOLVED_INPUT_BASE%.onnx]
set "STATE_OUTPUT_NAME="
set /p STATE_OUTPUT_NAME=[INPUT] Output filename: 
if "%STATE_OUTPUT_NAME%"=="" set "STATE_OUTPUT_NAME=%RESOLVED_INPUT_BASE%.onnx"
for %%O in ("%STATE_OUTPUT_NAME%") do set "STATE_OUTPUT_CLEAN=%%~nxO"
if "%STATE_OUTPUT_CLEAN%"=="" set "STATE_OUTPUT_CLEAN=%RESOLVED_INPUT_BASE%.onnx"
if /I not "%STATE_OUTPUT_CLEAN:~-5%"==".onnx" set "STATE_OUTPUT_CLEAN=%STATE_OUTPUT_CLEAN%.onnx"
set "RESOLVED_OUTPUT=%RESOLVED_INPUT_DIR%%STATE_OUTPUT_CLEAN%"
exit /b 0

:prompt_yes_no_cancel
setlocal
set "STATE_PROMPT_TEXT=%~1"
set "STATE_PROMPT_DEFAULT=%~2"
set "STATE_PROMPT_OUTVAR=%~3"
set "STATE_DEFAULT_SWITCH=/D N"
if /I "%STATE_PROMPT_DEFAULT%"=="Y" set "STATE_DEFAULT_SWITCH=/D Y"
if /I "%STATE_PROMPT_DEFAULT%"=="C" set "STATE_DEFAULT_SWITCH=/D C"
choice /C YNC /N /M "%STATE_PROMPT_TEXT% [Y/N/C]: " %STATE_DEFAULT_SWITCH%
set "STATE_CHOICE_RC=%ERRORLEVEL%"
if "%STATE_CHOICE_RC%"=="1" (endlocal & set "%STATE_PROMPT_OUTVAR%=Y" & exit /b 0)
if "%STATE_CHOICE_RC%"=="2" (endlocal & set "%STATE_PROMPT_OUTVAR%=N" & exit /b 0)
if "%STATE_CHOICE_RC%"=="3" (
    endlocal
    call :fail 5 "User canceled" 1
    exit /b 1
)
endlocal
call :fail 5 "Prompt input failed" 2
exit /b 1

:preflight_writable
set "STATE_TEMP_FILE=%~1convert_write_test_%RANDOM%_%RANDOM%.tmp"
call :debug "Preflight write test at %STATE_TEMP_FILE%"
(echo test)>"%STATE_TEMP_FILE%" 2>nul
if errorlevel 1 (
    echo [ERROR] Output directory is not writable: "%~1"
    echo         Check permissions, free disk space, and folder attributes.
    set "STATE_READONLY_WARNING=1"
    call :fail 5 "Output directory is not writable (disk full or permission denied)" 2
    exit /b 1
)
del /F /Q "%STATE_TEMP_FILE%" >nul 2>&1
if errorlevel 1 (
    echo [WARN] Temporary preflight file could not be deleted: "%STATE_TEMP_FILE%"
    echo        File remains at "%STATE_TEMP_FILE%"
)
exit /b 0

:validate_input
setlocal EnableDelayedExpansion
set "STATE_PROMPT=%~1"
set "STATE_DEFAULT=%~2"
set "STATE_ALLOWED=%~3"
set "STATE_MAX=%~4"
set "STATE_OUTVAR=%~5"
set "STATE_TRIES=0"
:validate_input_loop
set /a STATE_TRIES+=1
set "STATE_VAL="
set /p STATE_VAL=!STATE_PROMPT!
if "!STATE_VAL!"=="" set "STATE_VAL=!STATE_DEFAULT!"
if /I "!STATE_VAL!"=="C" (
    endlocal
    call :fail 5 "User canceled" 1
    exit /b 1
)
set "STATE_OK=0"
for %%A in (!STATE_ALLOWED!) do (
    if /I "%%A"=="!STATE_VAL!" set "STATE_OK=1"
)
if "!STATE_OK!"=="1" (
    endlocal & set "%~5=%STATE_VAL%" & exit /b 0
)
echo [WARN] Invalid input: "!STATE_VAL!"
if !STATE_TRIES! GEQ !STATE_MAX! (
    endlocal
    call :fail 5 "Invalid input attempts exceeded" 2
    exit /b 1
)
goto :validate_input_loop

:run_cmd
call :debug "RUN: %~1"
cmd /d /c "%~1" >nul 2>&1
set "STATE_TMP_RC=%ERRORLEVEL%"
if not "%STATE_TMP_RC%"=="0" (
    call :debug "%~2 failed rc=%STATE_TMP_RC%"
    exit /b 1
)
exit /b 0

:path_len_warn
set "STATE_PATH_CHECK=%~1"
set "STATE_LABEL=%~2"
call set "STATE_PATH_LEN=%%STATE_PATH_CHECK%%"
if not "%STATE_PATH_LEN:~240,1%"=="" (
    echo [WARN] %STATE_LABEL% resolved path appears very long. PATH truncation may occur on some systems.
)
exit /b 0

:init_logging
if "%STATE_VERBOSE%"=="0" exit /b 0
set "STATE_LOG_DIR=%~dp0logs"
if not exist "%STATE_LOG_DIR%" mkdir "%STATE_LOG_DIR%" >nul 2>&1
if not exist "%STATE_LOG_DIR%" exit /b 0

set "STATE_LOG_DATE="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd" 2^>nul`) do if not defined STATE_LOG_DATE set "STATE_LOG_DATE=%%D"
if "%STATE_LOG_DATE%"=="" set "STATE_LOG_DATE=%date:/=-%"
set "STATE_LOG_FILE=%STATE_LOG_DIR%\convert_to_onnx_%STATE_LOG_DATE%.log"
>>"%STATE_LOG_FILE%" echo [%date% %time%] session start
if errorlevel 1 exit /b 0
set "STATE_LOG_ENABLED=1"
exit /b 0

:log
if "%STATE_LOG_ENABLED%"=="0" exit /b 0
>>"%STATE_LOG_FILE%" echo [%date% %time%] %~1
exit /b 0

:debug
if "%STATE_VERBOSE%"=="0" exit /b 0
echo [INFO] [DEBUG] %~1
call :log "DEBUG %~1"
exit /b 0

:missing_pt_help
echo         Fixes:
echo         1^) Place a .pt file next to this script.
echo         2^) Pass full path as arg1.
echo         3^) Verify the file extension is exactly .pt.
exit /b 0

:fail
set "STATE_EXIT_CODE=%~1"
set "STATE_EXIT_REASON=%~2"
if "%~3"=="" (
    if "%STATE_EXIT_CODE%"=="5" set "STATE_EXIT_SUBCODE=2"
) else (
    set "STATE_EXIT_SUBCODE=%~3"
)
exit /b 0

:line
echo ================================================================
exit /b 0

:title
echo %~1
exit /b 0
