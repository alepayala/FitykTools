--[[
Fityk Batch Processing Script

Author:      Alejandro Pedro Ayala, Federal University of Ceará
Version:     3.0
Last Updated: 2026-02-11

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

------------------------------------------------------------
-- 📦 SCRIPT LOGIC (Do not edit below this line)
------------------------------------------------------------

local BatchProcessor = {}

-- Helper: Logging
function BatchProcessor.log(level, message)
    print(string.format("[%s] %s", level, message))
end

-- Helper: Validation
function BatchProcessor.validateConfig()
    if not UserConfig.headerStr or #UserConfig.headerStr == 0 then
        error("Config Error: 'headerStr' cannot be empty.")
    end
    if type(UserConfig.errorStr) == "table" and #UserConfig.errorStr ~= #UserConfig.headerStr then
        error("Config Error: 'errorStr' length as a list must match 'headerStr'. Use `true` for auto-naming.")
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

-- Core: Save All Data
function BatchProcessor.saveAllData()
    BatchProcessor.forEachDataset(function(n)
        local title = F:get_info("title", n)
        -- Sanitize title for filename
        local filename = title:gsub("[^%w%-_]", "_") .. ".xy"
        F:execute(string.format("@%d: print all: x, y, F(x) > '%s'", n, filename))
    end)
end

-- Core: Generate Parameter Report
function BatchProcessor.generateReport()
    local all_datasets_params = {}
    local max_peaks = 0
    local dataset_count = F:get_dataset_count()

    -- 1. Extraction
    for n = 0, dataset_count - 1 do
        local components = F:get_components(n)
        local current_dataset_params = {}

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
                local peak_params = {}
                -- Extract generic params
                for _, param_name in ipairs(UserConfig.headerStr) do
                    -- Try to get value using pcall to avoid crash if param doesn't exist
                    local status, val = pcall(function() return func:get_param_value(param_name) end)
                    
                    if status and val then
                        table.insert(peak_params, val)
                        if UserConfig.errorStr then
                            local err_status, err_val = pcall(function()
                                local var_full_name = func:var_name(param_name)
                                return F:calculate_expr('$' .. var_full_name .. '.error')
                            end)
                            if err_status then
                                table.insert(peak_params, err_val)
                            else
                                table.insert(peak_params, nil) -- Error calculation failed
                            end
                        end
                    else
                        table.insert(peak_params, nil) -- Param not found
                        if UserConfig.errorStr then
                            table.insert(peak_params, nil) -- Error placeholder
                        end
                    end
                end
                table.insert(current_dataset_params, peak_params)
            end
        end

        -- 2. Sorting (by first parameter, typically 'center')
        table.sort(current_dataset_params, function(a, b)
            return a[1] < b[1]
        end)

        all_datasets_params[n] = current_dataset_params
        if #current_dataset_params > max_peaks then
            max_peaks = #current_dataset_params
        end
    end

    -- 3. Formatting
    local delim = BatchProcessor.getDelimiter()
    local report_lines = {}

    -- Header
    local header_parts = {"File"}
    local function addHeaderCols(peak_idx)
        for j, param_name in ipairs(UserConfig.headerStr) do
            table.insert(header_parts, param_name .. peak_idx)
            if UserConfig.errorStr then
                local err_name
                if type(UserConfig.errorStr) == "table" and UserConfig.errorStr[j] then
                    err_name = UserConfig.errorStr[j]
                else
                    -- Auto-generate error name (e.g. "center" -> "eCenter")
                    err_name = "e" .. param_name:gsub("^%l", string.upper)
                end
                table.insert(header_parts, err_name .. peak_idx)
            end
        end
    end

    if UserConfig.sortByType then
        for j, param_name in ipairs(UserConfig.headerStr) do
            for k = 1, max_peaks do
                table.insert(header_parts, param_name .. k)
                if UserConfig.errorStr then
                     local err_name
                    if type(UserConfig.errorStr) == "table" and UserConfig.errorStr[j] then
                        err_name = UserConfig.errorStr[j]
                    else
                        err_name = "e" .. param_name:gsub("^%l", string.upper)
                    end
                    table.insert(header_parts, err_name .. k)
                end
            end
        end
    else
        for k = 1, max_peaks do
            addHeaderCols(k)
        end
    end
    table.insert(report_lines, table.concat(header_parts, delim))

    -- Rows
    for n = 0, dataset_count - 1 do
        local row_parts = {}
        local fileN = string.match(F:get_info("filename", n), "[^/\\]+$") or ""
        if UserConfig.fileinfo_mask and #UserConfig.fileinfo_mask > 0 then
            fileN = string.match(fileN, UserConfig.fileinfo_mask) or fileN
        end
        table.insert(row_parts, fileN)
        
        local params = all_datasets_params[n]

        -- Logic to fill row with empty cells if peaks are missing
        if UserConfig.sortByType then
            for j = 1, #UserConfig.headerStr do
                for k = 1, max_peaks do
                    local val_index = 1
                    if UserConfig.errorStr then val_index = 2 * (j - 1) + 1 end
                    
                    if params[k] then
                        local val = params[k][val_index]
                        if val then
                            table.insert(row_parts, string.format("%.4f", val))
                        else
                            table.insert(row_parts, "-")
                        end
                        if UserConfig.errorStr then
                            local err = params[k][val_index + 1]
                            if err then
                                table.insert(row_parts, string.format("%.4f", err))
                            else
                                table.insert(row_parts, "-")
                            end
                        end
                    else
                        table.insert(row_parts, "-")
                        if UserConfig.errorStr then table.insert(row_parts, "-") end
                    end
                end
            end
        else
            for k = 1, max_peaks do
                if params[k] then
                    for _, val in ipairs(params[k]) do
                        if val then
                            table.insert(row_parts, string.format("%.4f", val))
                        else
                            table.insert(row_parts, "-")
                        end
                    end
                else
                    local col_count = #UserConfig.headerStr
                    if UserConfig.errorStr then col_count = col_count * 2 end
                    for _ = 1, col_count do table.insert(row_parts, "-") end
                end
            end
        end
        table.insert(report_lines, table.concat(row_parts, delim))
    end

    -- 4. Output
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


-- Main Run Function
function BatchProcessor.run()
    BatchProcessor.loadExternalConfig()
    BatchProcessor.validateConfig()
    
    print("🚀 Starting Fityk Batch Processing Script...")
    print(string.format("Info: Running in mode '%s'", UserConfig.mode))

    if UserConfig.mode == "full_process" then
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        BatchProcessor.generateReport()

    elseif UserConfig.mode == "full_process_and_save" then
        if UserConfig.report_output_file == "" then 
            UserConfig.report_output_file = "parameters_report.txt" 
        end
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        BatchProcessor.generateReport()
        BatchProcessor.saveAllData()

    elseif UserConfig.mode == "save_table" then
        if UserConfig.report_output_file == "" then 
            UserConfig.report_output_file = "parameters_report.txt" 
        end
        BatchProcessor.generateReport()

    elseif UserConfig.mode == "fit_only" then
        BatchProcessor.setLimits()
        BatchProcessor.batchFit()
        BatchProcessor.replot()

    elseif UserConfig.mode == "report_only" then
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