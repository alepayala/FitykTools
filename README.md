# FitykTools: Robust Batch Processing for Fityk 🚀

A powerful, self-contained Lua script for automating spectral data analysis in [Fityk](https://fityk.ni/). It handles batch fitting across multiple datasets, extracts parameters, generates detailed reports, and exports data for external plotting.

## 🎥 [Watch the Demo Video](FitykTools.mp4)

See the script in action: **[FitykTools.mp4](FitykTools.mp4)** (Download to view)

---

## Key Features

*   **Batch Fitting**: Sequentially fits multiple datasets, intelligently copying parameters from the previous dataset (`n`) to the next (`n+1`) as initial guesses for stable convergence.
*   **Detailed Exports**: Saves `.xy` files containing:
    *   `x`
    *   `y` (Original Data)
    *   `F(x)` (Total Fit)
    *   **Individual Components**: Columns for every single peak function (e.g., `%Gaussian1(x)`, `%Lorentzian2(x)`).
*   **Robust & Flexible**: 
    *   Automatically handles missing parameters (e.g., fitting a dataset with no peaks doesn't crash the script).
    *   Supports different function types (Gaussian, Lorentzian, Sigmoid, etc.) with automatic handling of varying parameter names.
*   **Smart Header Auto-Detection**: Leave `headerStr` empty and the script inspects every fitted function (via Fityk's `get_info`) to build the report columns for you, **independently for each peak position**. If peak #1 is a Voigt in some datasets and a Lorentzian in others, both parameter sets accumulate correctly for that column, and any dataset missing a given parameter simply gets a `-` in that exact cell — columns never shift or misalign.
*   **Configurable Column Layout**: Choose whether the report groups columns by peak (`center1, height1, ..., center2, height2, ...`) or by parameter type (`center1, center2, ..., height1, height2, ...`) via `sortByType`.
*   **External Configuration**: Keep your code clean! Use a separate `fityk_config.lua` file in your data folder to control settings without modifying the main script.
*   **Advanced Reporting**: Generates Tab-Separated or CSV reports with parameter values and errors.
*   **User-Defined Functions**: Easily define and use custom fitting functions (e.g., `PVL`, `PearsonIV`) directly in your configuration file or the main script, expanding Fityk's built-in capabilities.

## Installation

1.  Download `FitykTools.lua` and place it in a convenient folder (e.g., `C:\Scripts\`).
2.  (Optional) Download `fityk_config.lua` and place it in the folder where your data files are located.

## Usage

### 1. Load Data
Open Fityk and load your series of data files (e.g., multiple `.dat` or `.xy` files).

### 2. Configure
You have two options:

**Option A (Recommended): External Config**
Copy `fityk_config.lua` to your data directory. Edit it to set your preferences:
```lua
return {
    mode = "full_process_and_save",
    lowerL = 1, upperL = 0, -- Set inverted to use full range
    -- ... other settings
}
```

**Option B: Edit the Script**
If no config file is found, the script uses default settings defined at the top of `FitykTools.lua`.

### 3. Run
In the Fityk console (bottom of the window), type:
```lua
exec 'C:\path\to\FitykTools.lua'
```

## Output Formats

**Report File (`results.txt` or `.csv`)**:
Contains a row for each dataset with columns for Chi-Square, DOF, and all defined parameters (Center, Height, FWHM, Area, etc.).

**XY Data Files**:
Saved as `Filename.xy`.
Format:
```text
x	y	F(x)	%Gaussian1(x)	%Lorentzian2(x) ...
10.0	25.1	24.9	12.0	12.9
...
```

## Plotting Tools

Included in the repository is a Python plotting tool, `plot_fityk_table.py`, which visualizes the generated parameter tables as a grid of subplots (one for each parameter and peak pair).

**Usage:**
```bash
python plot_fityk_table.py results.txt
```
*It automatically detects the delimiter, extracts the x-axis, and generates `results_matrix.png`.*

*   Set `auto_plot = true` in your config to launch it automatically right after the report is saved. It runs in its own console window, which now closes itself as soon as the plot is generated.
*   Each subplot automatically rescales its y-axis to the data's own min/max (with a small margin) whenever the error bars are larger than the spread of the values themselves — so a few noisy points don't stretch the axis and hide the real trend.

## License
MIT License. See [LICENSE](LICENSE) for details.

## Author
**Alejandro Pedro Ayala**
Federal University of Ceará
