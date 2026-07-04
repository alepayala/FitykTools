--[[
    FitykTools External Configuration File
    --------------------------------------
    Place this file in the same directory as your data/script to override default settings.
    This file is optional; if not present, the script uses internal defaults.
]]

return {
    -- Workflow to run.
    -- Options: 
    -- "full_process":            Fit -> Plot -> Report
    -- "full_process_and_save":   Fit -> Plot -> Report -> Save Report & Data (.xy)
    -- "fit_only":                Fit -> Plot
    -- "report_only":             Generate Report (no fitting)
    -- "save_table":              Generate & Save Report (no fitting)
    -- "normalize_and_replot":    Normalize Y to [0,1] -> Plot
    -- "subtract_baseline":       Subtract background functions -> Plot
    mode = "full_process",
    
    -- Report output file. "" prints to screen; "filename.txt" saves to file AND prints to screen.
    report_output_file = "parameters_report.txt", 
    
    -- If true, appends the fitting range to the report output filename (e.g., "[min,max]")
    append_range_to_report_name = true,

    -- Output format: "TAB" (default, good for reading) or "CSV" (good for Excel/Pandas).
    output_delimiter = "TAB", 

    -- If true, automatically launch the external plotter after saving the
    -- parameter report. The plotter is launched non-blocking so Fityk continues.
    auto_plot = true,
    
    -- Data range for processing (X-axis limits).
    -- If 'lowerL > upperL' (e.g. 1, 0), the limit is DISABLED and all data is used.
    lowerL = 1,
    upperL = 0,
    
    -- Spectrum range for fitting (Dataset indices).
    n_i = 0,      -- First spectrum index to fit.
    n_f = 0,       -- Last spectrum index to fit. (0 means fit to the end).
    
    -- Report layout: `true` groups by parameter type (c1, c2 ... h1, h2 ...); 
    -- `false` groups by peak (c1, h1 ... c2, h2 ...).
    sortByType = true,

    -- Sort peaks by the first parameter (typically 'center'). Set to `false` to disable sorting.
    sortByFirstParam = true,
    
    -- List of background function names to exclude from parameter reports.
    backgroundFuncNames = {"Linear", "Quadratic","Cubic"},
    
    -- List of parameter names to extract from each peak, applied identically
    -- to every peak column. Left empty here on purpose: parameters are
    -- auto-detected independently PER PEAK POSITION (via get_info on each
    -- function actually found there, across all datasets), so peaks that use
    -- different function types (Voigt, PseudoVoigt, Lorentzian, ...) at the
    -- same position just accumulate their own parameter sets automatically.
    --
    -- Uncomment one of these to force the same fixed parameter list for
    -- every peak column instead (legacy behavior):
    -- headerStr = {"center", "height", "gwidth", "shape"},   -- Voigt
    -- headerStr = {"center", "height", "hwhm", "shape"},     -- PseudoVoigt
    -- headerStr = {"center", "height", "hwhm"},              -- Lorentzian

    -- List of error names for the report. 
    -- Set to `true` (or "auto") to automatically generate error headers (e.g. "eCenter").
    -- Set to a list of strings (e.g. {"eCenter", "eHeight"}) to customize names.
    -- Set to `nil` or `false` to disable.
    errorStr = true,
    
    -- Optional regex to extract part of a filename for the column "File". "" uses the full name.
    -- Example: "filename_(%d+)" extracts '010' from 'filename_010-suffix.txt'.
    fileinfo_mask = "",

    -- List of custom fitting functions to define in Fityk.
    -- Each string in the list should be a valid Fityk command.
    custom_functions = {
        "define PearsonIV(height, center, width=1, shape_m=1, skewness=0) = height * (1 + ((x - center)/width)^2)^(-shape_m) * exp(-skewness * atan((x - center)/width))",
        "define BWF(height, center, hwhm=1, q=100) = height * (1 + (x - center) / (q * hwhm))^2 / (1 + ((x - center) / hwhm)^2)",
        "define PVL(height, center, hwhm, shape, rel_int, delta_x, hwhm_L) = PseudoVoigt(height, center, hwhm, shape) + Lorentzian(height * rel_int, center + delta_x, hwhm_L)",
    },
}
