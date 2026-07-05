--[[
Fityk Batch Processing Script

Author:      Alejandro Pedro Ayala, Federal University of Ceará
Version:     3.1
Last Updated: 2026-07-04

Description:
This script provides a comprehensive framework for batch processing spectral data in Fityk.
It automates fitting, parameter and error extraction, data normalization, baseline
subtraction, and saving results.

Configuration:
- All settings are managed in the 'User Configuration' section below.
- Alternatively, you can place a file named 'fityk_config.lua' in the same directory 
  as your data to override these defaults without modifying the script.

Instructions:
1. Load your data into Fityk.
2. (Optional) Create a 'fityk_config.lua' file in your data folder to customize settings.
3. Run the script from the Fityk command line using: exec 'path/to/FitykTools.lua'
]]

------------------------------------------------------------
-- 🛠️ USER CONFIGURATION
------------------------------------------------------------
local UserConfig = {
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
    report_output_file = "", 

    -- If true, appends the fitting range to the report output filename (e.g., "[min,max]")
    append_range_to_report_name = false,

    -- Output format: "TAB" (default, good for reading) or "CSV" (good for Excel/Pandas).
    output_delimiter = "TAB", 

    -- If true, automatically launch the external plotter after saving the
    -- parameter report. The plotter is launched non-blocking so Fityk continues
    -- running. Default: false
    auto_plot = false,

    -- Data range for processing (X-axis limits).
    -- If 'lowerL > upperL' (e.g. 1, 0), the limit is DISABLED and all data is used.
    lowerL = 1,
    upperL = 0,

    -- Spectrum range for fitting (Dataset indices).
    n_i = 0,       -- First spectrum index to fit.
    n_f = 0,       -- Last spectrum index to fit. (0 means fit to the end).

    -- Report layout: `true` groups by parameter type (c1, c2 ... h1, h2 ...); 
    -- `false` groups by peak (c1, h1 ... c2, h2 ...).
    sortByType = true,

    -- Sort peaks by the first parameter (typically 'center'). Set to `false` to disable sorting.
    sortByFirstParam = true,

    -- List of background function names to exclude from parameter reports.
    backgroundFuncNames = {"Linear", "Quadratic"},

    -- List of parameter names to extract from each peak, applied identically
    -- to every peak column (e.g. {"center", "height", "hwhm"}).
    -- Set to {} or nil to auto-detect instead: parameters are then discovered
    -- independently PER PEAK POSITION (via get_info on each function actually
    -- found there, across all datasets), so peak 1 and peak 2 can end up with
    -- different parameter sets if they use different function types.
    headerStr = {},

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
    -- Example: {"define PearsonIV(height, center, width, shape_m, skewness, x) = height * (1 + ((x - center)/width)^2)^(-shape_m) * exp(-skewness * atan((x - center)/width))"}
    custom_functions = {},
}

------------------------------------------------------------
-- 📦 SCRIPT LOGIC (Do not edit below this line)
------------------------------------------------------------

local BatchProcessor = {}

-- Helper: Logging
function BatchProcessor.log(level, message)
    print(string.format("[%s] %s", level, message))
end

-- Helper: Cache of function-template name -> ordered list of its own parameter
-- names, discovered via F:get_info(template). Looking parameters up by name
-- (instead of a fixed shared index) is what lets different function types
-- coexist at the same peak column without misaligning other columns.
BatchProcessor._templateParamCache = {}
function BatchProcessor.getTemplateParamNames(template)
    local cached = BatchProcessor._templateParamCache[template]
    if cached then return cached end

    local names = {}
    local status, val = pcall(function() return F:get_info(template) end)
    if status and val then
        -- [DEBUG] Show get_info output for control
        BatchProcessor.log("INFO", "get_info(" .. template .. ") -> " .. tostring(val))

        -- Extract parameters from signature (e.g. "Voigt(height, center, gwidth=...)")
        local paramsStr = val:match(template .. "%((.-)%)")
        if paramsStr then
            for p in paramsStr:gmatch("[^,]+") do
                local pname = p:match("^%s*([%w_]+)")
                if pname then table.insert(names, pname) end
            end
        end
    end
    BatchProcessor._templateParamCache[template] = names
    return names
end

-- Helper: Validation
function BatchProcessor.validateConfig()
    if type(UserConfig.errorStr) == "table" then
        if UserConfig.headerStr and #UserConfig.headerStr > 0 then
            if #UserConfig.errorStr ~= #UserConfig.headerStr then
                error("Config Error: 'errorStr' length as a list must match 'headerStr'. Use `true` for auto-naming.")
            end
        else
            -- A fixed error-name list has no clear meaning once headers are
            -- auto-detected independently per peak position (different
            -- positions can end up with different parameter sets/lengths).
            BatchProcessor.log("WARN", "'errorStr' as a list requires a manual 'headerStr'; falling back to auto-naming (e.g. 'eCenter') since headers are auto-detected per peak position.")
            UserConfig.errorStr = true
        end
    end
end

-- Helper: Ensure a report file is always available for full-process workflows
function BatchProcessor.ensureReportOutputFile()
    if not UserConfig.report_output_file or UserConfig.report_output_file == "" then
        UserConfig.report_output_file = "parameters_report.txt"
    end
end

-- Helper: Format Report File Name with Range
function BatchProcessor.formatReportFileName()
    if UserConfig.append_range_to_report_name and UserConfig.report_output_file and UserConfig.report_output_file ~= "" then
        local lo, up
        if UserConfig.lowerL > UserConfig.upperL then
            if F:get_dataset_count() > 0 then
                lo = F:calculate_expr("min(x)", 0)
                up = F:calculate_expr("max(x)", 0)
            else
                lo = 0
                up = 0
            end
        else
            lo = UserConfig.lowerL
            up = UserConfig.upperL
        end
        
        local filename = UserConfig.report_output_file
        local name, ext = filename:match("^(.*)(%..-)$")
        if not name then
            name = filename
            ext = ""
        end
        UserConfig.report_output_file = string.format("%s_[%g,%g]%s", name, lo, up, ext)
    end
end

-- Helper: Load External Config
function BatchProcessor.loadExternalConfig()
    local config_file = "fityk_config.lua"
    local f = io.open(config_file, "r")
    if f then
        f:close()
        BatchProcessor.log("INFO", "Loading external configuration from '" .. config_file .. "'")
        local status, external_config = pcall(dofile, config_file)
        if status and type(external_config) == "table" then
            for k, v in pairs(external_config) do
                UserConfig[k] = v
            end
            BatchProcessor.log("INFO", "External configuration loaded successfully.")
        else
            BatchProcessor.log("ERROR", "Failed to load external config: " .. tostring(external_config))
        end
    else
        BatchProcessor.log("INFO", "No external config found ('" .. config_file .. "'). Using defaults.")
    end
end

-- Helper: Get Delimiter
function BatchProcessor.getDelimiter()
    if UserConfig.output_delimiter == "CSV" then return "," else return "\t" end
end

-- Core: For Each Dataset Iterator
function BatchProcessor.forEachDataset(action, start_index, end_index)
    local count = F:get_dataset_count()
    if count == 0 then
        BatchProcessor.log("WARN", "No datasets found in Fityk.")
        return
    end

    local start = start_index or 0
    local last_available = count - 1
    
    local stop = end_index
    if not stop or stop <= 0 or stop > last_available then
        stop = last_available
    end

    for n = start, stop do
        action(n)
    end
end

-- Core: Limits
function BatchProcessor.setLimits()
    if UserConfig.lowerL > UserConfig.upperL then
        -- Fityk trick to enable all points if range is invalid/inverted
        F:execute("@*: A = a or not a") 
    else
        -- Disable all, then enable only in range
        F:execute("@*: A = a and not a") 
        F:execute(string.format("@*: A = a or (%f < x and x < %f)", UserConfig.lowerL, UserConfig.upperL)) 
    end
end

-- Core: Normalize
function BatchProcessor.normalize()
    BatchProcessor.forEachDataset(function(n)
        local base = F:calculate_expr("min(y)", n)
        local max_y = F:calculate_expr("max(y)", n)
        if max_y > base then
            F:execute(string.format("@%d: Y = (Y - %f)/(%f - %f)", n, base, max_y, base))
        end
    end)
end

-- Core: Subtract Baseline
function BatchProcessor.subtractBaseline()
    BatchProcessor.log("INFO", "Subtracting baseline from data...")
    BatchProcessor.forEachDataset(function(n)
        -- Assumes background function is named 'bg' + dataset index (standard Fityk behavior often uses specific naming, 
        -- but 'bg' prefix logic depends on user setup. Preserving original logic: %bgN)
        F:execute(string.format("@%d: Y = Y - %%bg%d(x)", n, n))
    end)
end

-- Core: Batch Fit
function BatchProcessor.batchFit()
    BatchProcessor.log("INFO", "Starting batch fit...")
    BatchProcessor.forEachDataset(function(n)
        BatchProcessor.log("INFO", "Fitting Dataset: " .. n)
        -- Only copy from the previous dataset if it's not the very first one processed in this loop
        -- AND it's not the absolute first dataset (0).
        if n > 0 and n > UserConfig.n_i then
             -- Copy model definition and parameters from previous dataset
            F:execute(string.format("@%d.F = copy(@%d.F)", n, n - 1))
        end
        
        -- Check if model exists (has components) before fitting to avoid "No parametrized functions" error
        local components = F:get_components(n)
        if components and #components > 0 then
            F:execute(string.format("fit @%d", n))
        else
            BatchProcessor.log("WARN", "Dataset " .. n .. " has no functions. Skipping fit.")
        end
    end, UserConfig.n_i, UserConfig.n_f)
end

-- Core: Replot
function BatchProcessor.replot()
    BatchProcessor.forEachDataset(function(n)
        local lo, up
        if UserConfig.lowerL > UserConfig.upperL then
            lo = F:calculate_expr("min(x)", n)
            up = F:calculate_expr("max(x)", n)
        else
            lo = UserConfig.lowerL
            up = UserConfig.upperL
        end
        F:execute(string.format("plot [%s:%s][:] @%d", tostring(lo), tostring(up), n))
    end)
end

-- Core: Save All Data (spectrum, total fit, and each individual fit
-- component as its own column: x, y, F(x), F_1(x), F_2(x), ... where
-- F(x) = sum of all F_i(x)).
function BatchProcessor.saveAllData()
    BatchProcessor.forEachDataset(function(n)
        local title = F:get_info("title", n)
        -- Sanitize title for filename
        local filename = title:gsub("[^%w%-_]", "_") .. ".xy"

        local components = F:get_components(n) or {}
        local header_cols = {"x", "y", "F(x)"}
        local expr_cols = {"x", "y", "F(x)"}
        for i = 0, #components - 1 do
            local func = components[i]
            table.insert(header_cols, string.format("F_%d(x)", i + 1))
            -- func.name is Fityk's own identifier for this function instance
            -- (e.g. "_3"), which must be referenced with a '%' prefix.
            table.insert(expr_cols, "%" .. func.name .. "(x)")
        end

        -- Write header
        local f_header = io.open(filename, "w")
        if f_header then
            f_header:write(table.concat(header_cols, "\t") .. "\n")
            f_header:close()
        end

        -- Append data (using >> to append to the file we just created)
        F:execute(string.format("@%d: print all: %s >> '%s'", n, table.concat(expr_cols, ", "), filename))
    end)
end

-- Core: Generate Parameter Report
--
-- This must run after fitting: it inspects whatever functions are currently
-- attached to each dataset (F:get_components), so it only sees the final,
-- fitted model - not a placeholder from before batchFit() propagated it.
function BatchProcessor.generateReport()
    local dataset_count = F:get_dataset_count()

    -- Helper to format numbers, using '-' for missing/not-applicable values
    local function fmt(v)
        if v then
            return string.format("%.4f", v)
        else
            return "-"
        end
    end

    -- 1. Extraction: read each function's OWN declared parameters (by name,
    --    via get_info) into a name -> value map. Peaks are self-describing,
    --    so two different function types can occupy the same column
    --    position (across datasets) without disturbing other positions.
    local all_datasets_peaks = {}
    local max_peaks = 0

    for n = 0, dataset_count - 1 do
        local components = F:get_components(n) or {}
        local peaks = {}

        for i = 0, #components - 1 do
            local func = components[i]
            local is_background = false
            for _, name in pairs(UserConfig.backgroundFuncNames) do
                if func:get_template_name() == name then
                    is_background = true
                    break
                end
            end

            if not is_background then
                local template = func:get_template_name()
                local paramNames = BatchProcessor.getTemplateParamNames(template)
                local values, errors = {}, {}

                for _, pname in ipairs(paramNames) do
                    local status, val = pcall(function() return func:get_param_value(pname) end)
                    if status and val then
                        values[pname] = val
                        if UserConfig.errorStr then
                            local err_status, err_val = pcall(function()
                                return F:calculate_expr('$' .. func:var_name(pname) .. '.error')
                            end)
                            if err_status then errors[pname] = err_val end
                        end
                    end
                end

                -- Sort key: prefer 'center'; fall back to this function's own first param.
                local sortKey = values["center"]
                if sortKey == nil and paramNames[1] then sortKey = values[paramNames[1]] end

                table.insert(peaks, {values = values, errors = errors, paramOrder = paramNames, sortKey = sortKey or 0})
            end
        end

        -- 2. Sorting (by 'center', typically) so column position k means
        --    "k-th peak left to right" consistently across datasets.
        if UserConfig.sortByFirstParam then
            table.sort(peaks, function(a, b) return a.sortKey < b.sortKey end)
        end

        all_datasets_peaks[n] = peaks
        if #peaks > max_peaks then
            max_peaks = #peaks
        end
    end

    if max_peaks == 0 then
        error("Config Error: no (non-background) functions were found in any dataset. Define 'headerStr' manually or add functions/fit before generating the report.")
    end

    -- 3. Header resolution per peak position.
    --    - Manual 'headerStr' (non-empty): applied identically to every position (legacy behavior).
    --    - Otherwise: auto-detected independently per position, starting from
    --      whichever function is found there first (in its own declared param
    --      order) and growing if a later dataset places a different function
    --      type (with previously-unseen params) at that same position.
    local manualHeaders = UserConfig.headerStr and #UserConfig.headerStr > 0
    local positionHeaders = {}

    if manualHeaders then
        for k = 1, max_peaks do
            positionHeaders[k] = UserConfig.headerStr
        end
    else
        BatchProcessor.log("INFO", "headerStr is empty. Auto-detecting parameters per peak position...")
        for k = 1, max_peaks do
            local seen, ordered = {}, {}
            for n = 0, dataset_count - 1 do
                local peak = all_datasets_peaks[n][k]
                if peak then
                    for _, pname in ipairs(peak.paramOrder) do
                        if not seen[pname] then
                            seen[pname] = true
                            table.insert(ordered, pname)
                        end
                    end
                end
            end
            positionHeaders[k] = ordered
            BatchProcessor.log("INFO", string.format("Peak position %d parameters: %s", k, table.concat(ordered, ", ")))
        end
    end

    -- 4. Column order: natural (peak-grouped: c1,h1,...,c2,h2,...) by default,
    --    or grouped by parameter type (c1,c2,...,h1,h2,...) when sortByType
    --    is enabled. Built as (position, name) pairs so both the header and
    --    every row can be driven off the exact same list.
    local columnOrder = {}
    if UserConfig.sortByType then
        local typeSeen, typeOrder = {}, {}
        for k = 1, max_peaks do
            for _, name in ipairs(positionHeaders[k]) do
                if not typeSeen[name] then
                    typeSeen[name] = true
                    table.insert(typeOrder, name)
                end
            end
        end
        for _, name in ipairs(typeOrder) do
            for k = 1, max_peaks do
                for _, hname in ipairs(positionHeaders[k]) do
                    if hname == name then
                        table.insert(columnOrder, {k = k, name = name})
                        break
                    end
                end
            end
        end
    else
        for k = 1, max_peaks do
            for _, name in ipairs(positionHeaders[k]) do
                table.insert(columnOrder, {k = k, name = name})
            end
        end
    end

    -- 5. Header row
    local delim = BatchProcessor.getDelimiter()
    local header_parts = {"File"}
    for _, col in ipairs(columnOrder) do
        table.insert(header_parts, col.name .. col.k)
        if UserConfig.errorStr then
            local err_name
            if manualHeaders and type(UserConfig.errorStr) == "table" then
                for j, hn in ipairs(UserConfig.headerStr) do
                    if hn == col.name then err_name = UserConfig.errorStr[j] break end
                end
            end
            err_name = err_name or ("e" .. col.name:gsub("^%l", string.upper))
            table.insert(header_parts, err_name .. col.k)
        end
    end

    local report_lines = {}
    table.insert(report_lines, table.concat(header_parts, delim))

    -- 6. Rows: look up each value/error by name, using '-' whenever the peak
    --    at that position doesn't exist in this dataset, or its function
    --    doesn't define that parameter. Every column is emitted individually
    --    (never via a bulk/omitted insert), so a missing value can never
    --    shift subsequent columns - it just fills its own cell with '-'.
    for n = 0, dataset_count - 1 do
        local row_parts = {}
        local fileN = string.match(F:get_info("filename", n), "[^/\\]+$") or ""
        if UserConfig.fileinfo_mask and #UserConfig.fileinfo_mask > 0 then
            fileN = string.match(fileN, UserConfig.fileinfo_mask) or fileN
        end
        table.insert(row_parts, fileN)

        local peaks = all_datasets_peaks[n]
        for _, col in ipairs(columnOrder) do
            local peak = peaks[col.k]
            local val = peak and peak.values[col.name]
            table.insert(row_parts, fmt(val))
            if UserConfig.errorStr then
                local err_val = peak and peak.errors[col.name]
                table.insert(row_parts, fmt(err_val))
            end
        end

        table.insert(report_lines, table.concat(row_parts, delim))
    end

    -- 7. Output
    print("\n--- Parameter Report ---")
    for _, line in ipairs(report_lines) do
        print(line)
    end
    print("------------------------\n")

    if UserConfig.report_output_file and UserConfig.report_output_file ~= "" then
        BatchProcessor.log("INFO", "Saving parameter report to '" .. UserConfig.report_output_file .. "'")
        local file, err = io.open(UserConfig.report_output_file, "w")
        if file then
            for _, line in ipairs(report_lines) do
                file:write(line .. "\n")
            end
            file:close()
        else
            BatchProcessor.log("ERROR", "Could not open report file: " .. tostring(err))
        end
    end
end


-- Helper: Launch external plotter (non-blocking)
function BatchProcessor.launchPlotter(report_file)
    -- Determine working directory: prefer the dataset folder (if available),
    -- otherwise use current working dir.
    local function get_workdir()
        -- Try to get filename for dataset 0
        local ok, fname = pcall(function() return F:get_info("filename", 0) end)
        if ok and fname and #fname > 0 then
            local d = fname:match('^(.*)[/\\]')
            if d and #d > 0 then return d end
        end
        -- Fallback to current process dir (cmd/PowerShell 'cd')
        local p = io.popen("cd")
        if p then
            local cur = p:read("*l")
            p:close()
            if cur and #cur > 0 then return cur end
        end
        return "."
    end

    -- Determine script directory (where this Lua file is located)
    local function get_script_dir()
        local info = debug.getinfo(1, 'S')
        if info and info.source then
            local s = tostring(info.source)
            local path = s:match('@?(.*)')
            if path and path:match('[/\\]') then
                return path:match('^(.*)[/\\]')
            end
        end
        if arg and arg[0] then
            local p = tostring(arg[0])
            if p:match('[/\\]') then return p:match('^(.*)[/\\]') end
        end
        return "."
    end

    local workdir = get_workdir()
    local script_dir = get_script_dir()

    -- Prefer a bundled EXE named 'plot_fityk_table.exe' next to this script,
    -- otherwise look for 'plot_fityk_table.py'.
    local exe_path = script_dir .. "/plot_fityk_table.exe"
    local py_path = script_dir .. "/plot_fityk_table.py"

    local function exists(path)
        local f = io.open(path, "r")
        if f then f:close(); return true end
        return false
    end

    local cmd
    if exists(exe_path) then
        cmd = string.format('start "" /D "%s" cmd /C ""%s" "%s""', workdir, exe_path, report_file)
    elseif exists(py_path) then
        -- Use system python on PATH
        cmd = string.format('start "" /D "%s" cmd /C "python "%s" "%s""', workdir, py_path, report_file)
    else
        error("No plotter found next to script: looked for 'plot_fityk_table.exe' and 'plot_fityk_table.py' in " .. tostring(script_dir))
    end

    BatchProcessor.log("INFO", "Launching plotter (non-blocking): " .. cmd)
    -- Non-blocking launch; Windows 'start' returns immediately.
    os.execute(cmd)
end

-- Main Run Function
function BatchProcessor.run()
    BatchProcessor.loadExternalConfig()
    BatchProcessor.validateConfig()
    
    print("🚀 Starting Fityk Batch Processing Script...")
    print(string.format("Info: Running in mode '%s'", UserConfig.mode))

    if UserConfig.custom_functions and #UserConfig.custom_functions > 0 then
        BatchProcessor.log("INFO", "Checking custom functions...")
        for _, func_cmd in ipairs(UserConfig.custom_functions) do
            local func_name = string.match(func_cmd, "define%s+([%w_]+)")
            if func_name then
                -- Try to define the function gracefully.
                -- We use pcall so that if it's already defined (and in use by a model), 
                -- the script continues to run successfully without aborting.
                local success, err = pcall(function() F:execute(func_cmd) end)
                if success then
                    BatchProcessor.log("INFO", "Defined custom function: " .. func_name)
                else
                    BatchProcessor.log("INFO", "Function '" .. func_name .. "' is already defined.")
                end
            else
                -- Execute generic Fityk command safely
                pcall(function() F:execute(func_cmd) end)
            end
        end
    end

    if UserConfig.mode == "full_process" then
        BatchProcessor.ensureReportOutputFile()
        BatchProcessor.formatReportFileName()
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        BatchProcessor.generateReport()
        if UserConfig.auto_plot then
            local ok, err = pcall(function()
                BatchProcessor.launchPlotter(UserConfig.report_output_file)
            end)
            if not ok then
                BatchProcessor.log("WARN", "Auto-plot failed: " .. tostring(err))
            end
        end

    elseif UserConfig.mode == "full_process_and_save" then
        BatchProcessor.ensureReportOutputFile()
        BatchProcessor.formatReportFileName()
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        BatchProcessor.generateReport()
        BatchProcessor.saveAllData()
        if UserConfig.auto_plot then
            local ok, err = pcall(function()
                BatchProcessor.launchPlotter(UserConfig.report_output_file)
            end)
            if not ok then
                BatchProcessor.log("WARN", "Auto-plot failed: " .. tostring(err))
            end
        end

    elseif UserConfig.mode == "save_table" then
        BatchProcessor.ensureReportOutputFile()
        BatchProcessor.formatReportFileName()
        BatchProcessor.generateReport()
        if UserConfig.auto_plot then
            -- Try to launch the external plotter in a non-blocking way.
            -- The helper will look for a local EXE first, then a python script
            -- placed alongside this Lua script.
            local ok, err = pcall(function()
                BatchProcessor.launchPlotter(UserConfig.report_output_file)
            end)
            if not ok then
                BatchProcessor.log("WARN", "Auto-plot failed: " .. tostring(err))
            end
        end

    elseif UserConfig.mode == "fit_only" then
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()

    elseif UserConfig.mode == "report_only" then
        BatchProcessor.formatReportFileName()
        BatchProcessor.generateReport()

    elseif UserConfig.mode == "normalize_and_replot" then
        BatchProcessor.normalize()
        BatchProcessor.replot()

    elseif UserConfig.mode == "subtract_baseline" then
        BatchProcessor.subtractBaseline()
        BatchProcessor.replot()

    else
        BatchProcessor.log("ERROR", "Unknown process_mode: " .. tostring(UserConfig.mode))
    end

    print("✅ Script finished.")
end

-- Execute
BatchProcessor.run()
