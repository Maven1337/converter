# PT to ONNX Converter (Easy Guide)

This folder has one main tool:

- `convert_to_onnx.bat`

It converts a YOLO `.pt` model into an `.onnx` model.

## What You Need

- Windows
- Python 3 installed
- Ultralytics installed (`yolo` command works)

If you are not sure, run this once in Command Prompt:

```bat
py -3 -m pip install -U ultralytics onnx onnxruntime
```

## Easiest Way (Double-Click)

1. Put your `.pt` file in this folder.
2. Double-click `convert_to_onnx.bat`.
3. Follow the prompts to pick model, output name, and preset (or just press Enter for recommended).
4. Wait for completion.

At the end, you will see a final summary card with result and file path.

## Command Line (Optional)

```bat
convert_to_onnx.bat <input.pt> [output.onnx] [preset]
```

Examples:

```bat
convert_to_onnx.bat "C:\models\best.pt"
convert_to_onnx.bat "C:\models\best.pt" "C:\exports\best.onnx"
convert_to_onnx.bat "C:\models\best.pt" "C:\exports\best.onnx" 2
```

## Presets (Simple)

- `1` Faster speed, lower quality potential
- `2` Better quality, slower
- `3` Balanced (recommended for most users)

## Useful Flags

- `--dry-run` checks everything without converting
- `--yes` auto-accepts prompts
- `--verbose` extra details
- `--debug` same as verbose

Example:

```bat
convert_to_onnx.bat "C:\models\best.pt" --dry-run
```

## If Something Fails

### Error: `yolo command exists but is not working correctly`

Run:

```bat
py -3 -m pip install -U ultralytics onnx onnxruntime
yolo version
```

### Error: `Python is required for Ultralytics YOLO`

Install Python 3 and make sure it is added to PATH.

### Error: `.pt` file not found

- Put the `.pt` file in this folder, or
- pass the full path to the `.pt` file

## Logs

Each run creates a log file in:

`logs\convert_to_onnx_YYYY-MM-DD_HHMMSS.log`

The script also prints the log path while running.

## Exit Codes (For Advanced Users)

- `0` Success
- `1` Input file problem
- `2` YOLO/Ultralytics problem
- `3` Export failed
- `4` Python not found
- `5` Canceled or internal error
