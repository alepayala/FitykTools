--[[
=======================================================================
 FitykTools - Batch fitting configuration      (for FitykTools.lua 3.6+)
=======================================================================

 HOW TO USE
 ----------
 1. Put this file in the SAME FOLDER as your spectra files. (The script
    also looks in Fityk's working directory and next to FitykTools.lua.)
 2. In Fityk, load your spectra and build the model on the FIRST dataset
    (guess/add the peak functions and the background).
 3. Run the batch script from the Fityk command line:
        exec 'C:/path/to/FitykTools.lua'
    It finds this file automatically, prints which configuration was
    loaded, fits every dataset (propagating the model), and writes the
    parameter report.
 4. Everything in this file is OPTIONAL: any key you delete falls back
    to the default built into FitykTools.lua, which is also the
    authoritative reference of all available keys. Unknown or misspelled
    keys are reported with a suggestion; keys from versions < 3.5 are
    migrated automatically with a warning.

 TYPICAL WORKFLOW - several fits over the same files changing regions
 --------------------------------------------------------------------
 Edit 'x_min'/'x_max' (section 2), keep append_range_to_report_name =
 true (section 5), and re-run. Each region produces its own report,
 plot and session file, named "..._<min>-<max>...", so no run ever
 overwrites the results of a previous region.
=======================================================================
]]

return {

    ------------------------------------------------------------------
    -- 1. WORKFLOW
    ------------------------------------------------------------------

    -- What the script should do, start to finish:
    --   "full_process"          - Fit all datasets -> Plot -> Report
    --   "full_process_and_save" - Same + save each spectrum with its fit
    --                             components as columns (.xy files)
    --   "fit_only"              - Fit and plot, no report
    --   "report_only"           - Report the CURRENT parameters (no fitting)
    --   "save_table"            - Same as report_only, forcing save to file
    --   "normalize"             - Rescale Y of every dataset to [0,1]
    --   "subtract_baseline"     - Subtract each dataset's own functions
    --                             from its data (use with care)
    mode = "full_process",

    ------------------------------------------------------------------
    -- 2. FITTING REGION (edited most often between runs)
    ------------------------------------------------------------------

    -- X-axis window used for fitting. Points outside are deactivated.
    -- To use ALL data, leave x_min > x_max (e.g. 1 and 0).
    x_min = 1,
    x_max = 0,

    -- X-ranges to EXCLUDE inside the window above, e.g. a spike, cosmic
    -- ray or a peak you do not want to influence the fit.
    -- Example: exclude_regions = {{20, 25}, {100, 110}},
    exclude_regions = {},

    ------------------------------------------------------------------
    -- 3. DATASET SELECTION
    ------------------------------------------------------------------

    -- Range of dataset indices to fit (as shown in Fityk: @0, @1, ...).
    first_dataset = 0,   -- first index to fit
    last_dataset = 0,    -- last index to fit; 0 = continue to the end

    ------------------------------------------------------------------
    -- 4. REPORT LAYOUT
    ------------------------------------------------------------------

    -- Uncertainty columns next to each parameter:
    --   true (or "auto") - automatic names: eCenter, eHeight, ...
    --   {"eC", "eH", ...} - custom names (requires manual parameter_names)
    --   false            - no error columns
    error_columns = true,

    -- Parameters to report for every peak. Leave {} (recommended) to
    -- auto-detect them per peak position - mixed function types (Voigt,
    -- PseudoVoigt, custom, ...) each contribute their own parameters.
    -- Or force a fixed list for all peaks:
    -- parameter_names = {"center", "height", "hwhm"},
    parameter_names = {},

    -- true:  columns grouped by parameter (center1, center2, ... height1,
    --        height2, ...) - best for plotting one parameter vs. file.
    -- false: columns grouped by peak (center1, height1, ... center2, ...).
    group_columns_by_parameter = true,

    -- Order peaks left-to-right by their center in each dataset, so
    -- "peak 1" means the same physical peak across rows.
    sort_peaks_by_center = true,

    -- Put 'center' as the FIRST column of each peak group when the
    -- parameter list is auto-detected.
    center_first = true,

    -- Lua pattern applied to each spectrum's filename to build the
    -- "File" column, e.g. extract just the number from "sample_010.txt":
    -- file_label_pattern = "sample_(%d+)",   -- File column shows "010"
    -- "" keeps the full filename.
    file_label_pattern = "",

    -- Function types treated as background: they are fitted normally
    -- but left out of the parameter report.
    background_function_names = {"Linear", "Quadratic", "Cubic"},

    -- Add fit-quality columns to each row of the report:
    -- rChi2 (= WSSR/DoF, reduced chi-square), R2 and DoF.
    -- Useful to spot bad fits at a glance in long batches.
    report_fit_quality = true,

    -- Column identity across datasets when peaks MOVE during a series:
    --   false - peaks are re-sorted by center in every dataset, so two
    --           peaks that cross each other swap columns mid-series.
    --   true  - nearest-neighbor tracking: each peak stays in the column
    --           whose last known center is closest, surviving crossings.
    track_peaks = false,


    ------------------------------------------------------------------
    -- 5. OUTPUT FILES
    ------------------------------------------------------------------

    -- Parameter report file. "" prints to the screen only;
    -- a filename saves to disk AND prints to the screen.
    report_output_file = "parameters_report.txt",

    -- If true, the fitting range is appended to the report AND session
    -- filenames (e.g. "parameters_report_450-1800.txt"), so consecutive
    -- runs over different regions never overwrite each other.
    append_range_to_report_name = true,

    -- Column separator of the report: "TAB" (easy to read) or
    -- "CSV" (comma; best for Excel/Pandas).
    output_delimiter = "TAB",

    -- If true, opens the parameter plots automatically after the report
    -- is saved (runs plot_fityk_table.py/.exe found next to
    -- FitykTools.lua, without blocking Fityk).
    auto_plot = true,

    -- If true, saves the complete Fityk session (data + models + fitted
    -- parameters) after processing. Reopening it restores every fitted
    -- spectrum exactly as it was:  exec 'fityk_session.fit'
    save_session = false,
    session_output_file = "fityk_session.fit",

    -- At most once a day, check GitHub for a newer FitykTools version and
    -- print a notice (read-only request; nothing is installed
    -- automatically; silent when offline). false disables the check.
    check_for_updates = true,

    ------------------------------------------------------------------
    -- 6. MODEL & FITTING CONTROL
    ------------------------------------------------------------------

    -- Where each dataset gets its starting model from during the batch:
    --   "previous" - the last dataset that fitted well (recommended for
    --                series where spectra change gradually)
    --   "first"    - always the first fitted dataset
    --   "none"     - no copying; every dataset must already have a model
    model_propagation = "previous",

    -- After each fit, reject obviously broken results: a peak center
    -- outside the data range, or a width that collapsed to ~0 or grew
    -- beyond the whole spectrum. Rejected datasets are reported and are
    -- never used as the starting model for the next one.
    sanity_check = true,

    -- Fitting method ("" keeps Fityk's current setting, normally
    -- Levenberg-Marquardt). Required for 'parameter_bounds' to work:
    -- use a method with box constraints, e.g. "mpfit" or "nlopt_lbfgs".
    fitting_method = "",

    -- Allowed interval per parameter name, applied to every peak before
    -- each fit. Prevents runaway widths/shapes. Needs a bound-aware
    -- 'fitting_method' (see above). Locked/linked variables are skipped.
    -- Example: parameter_bounds = {hwhm = {0.1, 50}, shape = {0, 1}},
    parameter_bounds = {},

    -- Extra function types, defined before fitting. Each entry is a
    -- Fityk 'define' (or any other) command. Note: 'x' is implicit and
    -- must NOT appear in the parameter list.
    custom_functions = {
        "define PearsonIV(height, center, width=1, shape_m=1, skewness=0) = height * (1 + ((x - center)/width)^2)^(-shape_m) * exp(-skewness * atan((x - center)/width))",
        "define BWF(height, center, hwhm=1, q=100) = height * (1 + (x - center) / (q * hwhm))^2 / (1 + ((x - center) / hwhm)^2)",
        "define PVL(height, center, hwhm, shape, rel_int, delta_x, hwhm_L) = PseudoVoigt(height, center, hwhm, shape) + Lorentzian(height * rel_int, center + delta_x, hwhm_L)",
    },
}
