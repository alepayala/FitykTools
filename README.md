# Fityk Batch Processing Script 🚀

A robust, self-contained Lua script for automating spectral data analysis in [Fityk](https://fityk.ni/). It handles batch fitting, parameter extraction, reporting, and data management.

## Features

- **Batch Fitting**: Sequentially fits multiple datasets. intelligently using parameters from the previous dataset as initial guesses.
- **Advanced Reporting**: Generates clean, tabulated reports of peak parameters (center, height, HWHM, Area, etc.) and their errors.
- **Flexible Output**: Supports both **Tab-Separated** (for text editors) and **CSV** (for Excel/Pandas) formats.
- **External Configuration**: Supports a separate `fityk_config.lua` file for easy setting management without modifying the code.
- **Data Manipulation**: Built-in tools for normalization and baseline subtraction.
- **Robustness**: Automatically handles missing parameters (e.g., if a dataset has a different peak type) without crashing.

## Installation

1. Download `FitykTools.lua` and place it in a known folder (e.g., `C:\Scripts\FitykTools.lua`).
2. (Optional) Download `fityk_config.lua` and place it in the folder where your data is located.

## Usage

### 1. Load Data
Open Fityk and load your series of data files.

### 2. Configure (Two Options)

#### Option A: External Configuration (Recommended)
Copy the `fityk_config.lua` file to the same folder as your data. Edit this file to change settings for that specific analysis.

```lua
return {
    mode = "full_process_and_save",
    report_output_file = "results.csv",
    output_delimiter = "CSV",
    -- ... other settings
}
```

#### Option B: Edit the Script
If `fityk_config.lua` is not found, the script uses the defaults defined inside `FitykTools.lua`. You can edit the `UserConfig` section at the top of the script to change these defaults.

### 3. Run
In the Fityk command line console (usually at the bottom of the window), type:

```bash
exec 'C:\Scripts\FitykTools.lua'
```

(Replace the path with the actual location of the script).

## Workflow Modes

The `mode` variable controls what the script does:

| Mode | Description |
|------|-------------|
| `full_process` | Fits data, replots, and prints report to screen. |
| `full_process_and_save` | Fits, reports, and saves both the report file and `.xy` data files. |
| `fit_only` | Performs batch fitting and updating plots only. |
| `report_only` | Generates the parameter report for currently fitted data. |
| `save_table` | Generates and saves the parameter report only. |
| `subtract_baseline` | Subtracts the background function (e.g., `%bgN`) from the data. |
| `normalize_and_replot` | Normalizes Y-values to [0,1] range. |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Author

**Alejandro Pedro Ayala**  
Federal University of Ceará
