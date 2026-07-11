# FitykTools: Robust Batch Processing for Fityk 🚀

A self-contained Lua script for automating spectral data analysis in [Fityk](https://fityk.nieto.pl/). It batch-fits an entire series of spectra, propagating the model from one dataset to the next, and produces a consolidated parameter report with uncertainties and fit-quality metrics — plus optional data export, session saving, and automatic plotting.

## 🎥 [Watch the Demo Video](FitykTools.mp4)

See the script in action: **[FitykTools.mp4](FitykTools.mp4)** (Download to view)

---

## Files

| File | Role |
|---|---|
| `FitykTools.lua` | The batch-processing script. Also the authoritative reference of all configuration keys and their defaults. |
| `fityk_config.lua` | The file you actually edit day to day: a per-data-folder configuration that overrides the defaults. Fully optional and partial — any key you delete falls back to the built-in default. |
| `plot_fityk_table.py` | Python tool that turns the parameter report into a grid of plots (one subplot per parameter/peak pair). |

## Quick Start

1. Place `FitykTools.lua` (and `plot_fityk_table.py`) in a convenient folder, e.g. `C:\Scripts\`.
2. Copy `fityk_config.lua` into the folder with your data files and adjust it.
3. Open Fityk, load your series of spectra, and build the model on the **first** dataset (guess/add the peak functions and the background).
4. In the Fityk console, run:
   ```
   exec 'C:\Scripts\FitykTools.lua'
   ```
   The script finds `fityk_config.lua` automatically (it searches the working directory, the data folder, and the script folder), fits every dataset, and writes the report.

### Typical workflow: several regions, same files

Edit `x_min`/`x_max`, keep `append_range_to_report_name = true`, and re-run. Every region produces its own report, plot, and session file named `..._<min>-<max>...` — no run ever overwrites the results of a previous region.

## Modes

Set `mode` in the config to choose the workflow:

| Mode | What it does |
|---|---|
| `full_process` | Fit all datasets → Plot → Report |
| `full_process_and_save` | Same, plus saves each spectrum with its fit components as columns (`.xy` files) |
| `fit_only` | Fit and plot, no report |
| `report_only` | Report the current parameters (no fitting) |
| `save_table` | Same as `report_only`, forcing save to file |
| `normalize` | Rescale Y of every dataset to [0, 1] |
| `subtract_baseline` | Subtract each dataset's own functions from its data (use with care) |

## Configuration Reference

All keys, grouped as in `fityk_config.lua`. Defaults shown in parentheses.

### 1. Workflow
* `mode` (`"full_process"`) — see the table above.

### 2. Fitting region
* `x_min`, `x_max` (`1`, `0`) — X-axis window used for fitting; points outside are deactivated. Leave `x_min > x_max` to use **all** data.
* `exclude_regions` (`{}`) — list of `{lower, upper}` X-ranges to punch out of the window (spikes, cosmic rays, unwanted peaks). Example: `{{20, 25}, {100, 110}}`.

### 3. Dataset selection
* `first_dataset`, `last_dataset` (`0`, `0`) — range of dataset indices (`@0`, `@1`, …) to fit; `last_dataset = 0` means "to the end".

### 4. Report layout
* `error_columns` (`true`) — uncertainty column next to each parameter (`eCenter`, `eHeight`, …); a list of custom names is accepted with a manual `parameter_names`; `false` disables.
* `parameter_names` (`{}`) — leave empty to **auto-detect** the parameters of each peak position (mixed function types each contribute their own parameters); or force a fixed list such as `{"center", "height", "hwhm"}`.
* `group_columns_by_parameter` (`true`) — `true`: columns grouped by parameter (`center1, center2, …, height1, height2, …`), best for plotting one parameter vs. file; `false`: grouped by peak.
* `sort_peaks_by_center` (`true`) — order peaks left-to-right by center in each dataset, so "peak 1" means the same physical peak across rows.
* `center_first` (`true`) — put `center` as the first column of each peak group when parameters are auto-detected.
* `file_label_pattern` (`""`) — Lua pattern applied to each filename to build the `File` column, e.g. `"sample_(%d+)"` turns `sample_010.txt` into `010`.
* `background_function_names` (`{"Linear", "Quadratic"}`) — function types fitted normally but left out of the report.
* `report_fit_quality` (`true`) — append `rChi2` (= WSSR/DoF), `R2`, and `DoF` columns to every row; invaluable for spotting bad fits in long batches.
* `track_peaks` (`false`) — when peaks move during a series: `false` re-sorts by center per dataset (crossing peaks swap columns); `true` uses nearest-neighbor tracking so each peak keeps its column through crossings.

### 5. Output files
* `report_output_file` (`""`) — `""` prints to screen only; a filename saves to disk and prints.
* `append_range_to_report_name` (`false`) — appends the fitting range to the report **and** session filenames (e.g. `parameters_report_450-1800.txt`). The suffix uses only shell-safe characters (no brackets or commas), so the names work in PowerShell, glob patterns, etc.
* `output_delimiter` (`"TAB"`) — `"TAB"` or `"CSV"`.
* `auto_plot` (`false`) — launch `plot_fityk_table.py` (or a bundled `.exe`) automatically after the report is saved, without blocking Fityk.
* `save_session` (`false`) + `session_output_file` (`"fityk_session.fit"`) — save the complete Fityk session (data + models + fitted parameters) after processing. Reopening it restores every fitted spectrum exactly as it was: `exec 'fityk_session.fit'`.

### 6. Model & fitting control
* `model_propagation` (`"previous"`) — where each dataset gets its starting model: `"previous"` (last dataset that fitted well — recommended for series that change gradually), `"first"`, or `"none"`.
* `sanity_check` (`true`) — after each fit, reject obviously broken results (peak center outside the data range, width collapsed to ~0 or wider than the whole spectrum). Rejected datasets are reported and never used as the starting model for the next one, stopping error cascades.
* `fitting_method` (`""`) — `""` keeps Fityk's current method. Required for `parameter_bounds`: use a bound-aware method such as `"mpfit"` or `"nlopt_lbfgs"` (the default Levenberg-Marquardt ignores domains).
* `parameter_bounds` (`{}`) — allowed interval per parameter name, applied to every peak before each fit, e.g. `{hwhm = {0.1, 50}, shape = {0, 1}}`. Locked/linked variables are skipped, so constraints between parameters are never destroyed.
* `custom_functions` (`{}`) — extra function types defined before fitting; each entry is a Fityk `define` command. Note: `x` is implicit and must **not** appear in the parameter list.

### 7. Updates
* `check_for_updates` (`true`) — at most once a day, the script checks GitHub for a newer FitykTools version and prints a notice. It is a read-only request (via `curl`, falling back to the PowerShell web client on Windows networks with proxies/TLS inspection where `curl` fails); nothing is downloaded or installed automatically, and it is completely silent when offline. Set to `false` to disable. The check runs at the end of the workflow, so it never delays fitting; the once-a-day throttle is kept in a small `.fityktools_update_check` file next to the script.

### Config compatibility

* Keys from versions < 3.5 (`lowerL`, `headerStr`, `sortByType`, …) are **migrated automatically** at load time, with a warning listing the renames to apply to your file.
* Unknown or misspelled keys are ignored with a warning and a suggestion: `Unknown config key 'x_mim' ignored - did you mean 'x_min'?`.

## Outputs

**Parameter report** (TAB or CSV) — one row per dataset:

```text
File     center1   eCenter1  center2  eCenter2  height1  ...  rChi2   R2        DoF
s01.dat  24.7222   0.0030    41.8108  0.7019    65454.1  ...  292.71  0.994383  837
```

Missing values (a peak absent in a dataset, or a parameter the function type doesn't have) appear as `-` in their own cell — columns never shift or misalign.

**XY data files** (`mode = "full_process_and_save"`) — one file per dataset, ready for plotting the data, the total fit, and the fit decomposition together: the original `x` and `y` in the first two columns, the total fit `F(x)` in the third, and one column per fit component (background included). `F(x)` is always the exact sum of all `F_i(x)`, and every point of the spectrum is exported (active or not):

```text
x	y	F(x)	F_1(x)	F_2(x) ...
10.0	25.1	24.9	12.0	12.9
```

Files are named `<index>_<title>.xy`, using only the last path segment of the dataset title; the index prefix guarantees unique names even when titles repeat. The script never overwrites a dataset's own source data file: if the generated name would collide with it, the output is saved as `<index>_<title>_fit.xy` instead and a warning is logged.

**Session file** (`save_session = true`) — a single `.fit` file that restores the whole fitted batch in Fityk, months later, with one `exec`.

## Plotting Tool

`plot_fityk_table.py` visualizes the report as a matrix of subplots (parameters × peaks), with error bars. Requires Python 3 with `matplotlib`.

```bash
python plot_fityk_table.py parameters_report_450-1800.txt
```

* Detects the delimiter automatically (or reads it from the `fityk_config.lua` next to the report).
* Saves and opens `<report>_matrix.png`; reports of different fitting ranges each get their own PNG.
* Options: `--x-column temperature`, `--output plot.png`, `--delimiter csv`, `--no-errors`, `--no-open`.
* When error bars are larger than the spread of the values, each subplot rescales its y-axis to the data's own range so noisy points don't hide the real trend.
* Set `auto_plot = true` in the config to launch it automatically after each run.

## License
MIT License. See [LICENSE](LICENSE) for details.

## Author
**Alejandro Pedro Ayala**
Federal University of Ceará
