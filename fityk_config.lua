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
    mode = "save_table",
    
    -- Report output file. "" prints to screen; "filename.txt" saves to file AND prints to screen.
    report_output_file = "", 
    
    -- Output format: "TAB" (default, good for reading) or "CSV" (good for Excel/Pandas).
    output_delimiter = "TAB", 
    
    -- Data range for processing (X-axis limits).
    lowerL = -200,
    upperL = -100,
    
    -- Spectrum range for fitting (Dataset indices).
    n_i = 12,      -- First spectrum index to fit.
    n_f = 0,       -- Last spectrum index to fit. (0 means fit to the end).
    
    -- Report layout: `true` groups by parameter type (c1, c2 ... h1, h2 ...); 
    -- `false` groups by peak (c1, h1 ... c2, h2 ...).
    sortByType = true,
    
    -- List of background function names to exclude from parameter reports.
    backgroundFuncNames = {"Linear", "Quadratic"},
    
    -- List of parameter names to extract from each peak. 
    -- 'center' MUST be first for robust sorting.
    headerStr = {"center", "height", "hwhm"}, 
    
    -- List of error names for the report. 
    -- Set to `true` (or "auto") to automatically generate error headers (e.g. "eCenter").
    -- Set to a list of strings (e.g. {"eCenter", "eHeight"}) to customize names.
    -- Set to `nil` or `false` to disable.
    errorStr = true,
    
    -- Optional regex to extract part of a filename for the column "File". "" uses the full name.
    -- Example: "Br5_(%d+)K" extracts '014' from 'Br5_014K-S.txt'.
    fileinfo_mask = "Br5_(%d+)K", 
}
