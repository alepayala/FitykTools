--[[
Fityk Batch Processing Script

Author:      Alejandro Pedro Ayala, Federal University of Ceará
Version:     3.9
Last Updated: 2026-07-11

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

-- Keep in sync with the 'Version:' line in the header above.
local SCRIPT_VERSION = "3.9"
local UPDATE_URL = "https://raw.githubusercontent.com/alepayala/FitykTools/main/FitykTools.lua"

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
    -- "normalize":               Normalize Y to [0,1] -> Plot
    -- "subtract_baseline":       Subtract background functions -> Plot
    mode = "full_process",
    
    -- Report output file. "" prints to screen; "filename.txt" saves to file AND prints to screen.
    report_output_file = "", 

    -- If true, appends the fitting range to the report AND session output
    -- filenames (e.g., "report_24.5-982.3.txt"), so runs over different
    -- regions of the same data never overwrite each other's results.
    append_range_to_report_name = false,

    -- Output format: "TAB" (default, good for reading) or "CSV" (good for Excel/Pandas).
    output_delimiter = "TAB", 

    -- If true, automatically launch the external plotter after saving the
    -- parameter report. The plotter is launched non-blocking so Fityk continues
    -- running. Default: false
    auto_plot = false,

    -- X-axis range used for fitting/processing.
    -- If 'x_min > x_max' (e.g. 1, 0), the limit is DISABLED and all data is used.
    x_min = 1,
    x_max = 0,

    -- List of [lower, upper] X-ranges to EXCLUDE from fitting (e.g. to skip a
    -- spike, cosmic ray, or known artifact), applied on top of x_min/x_max.
    -- Example: exclude_regions = {{20, 25}, {100, 110}}
    exclude_regions = {},

    -- Dataset index range for fitting.
    first_dataset = 0,   -- First dataset index to fit.
    last_dataset = 0,    -- Last dataset index to fit (0 = fit to the end).

    -- Report layout: `true` groups columns by parameter type (c1, c2 ... h1, h2 ...);
    -- `false` groups by peak (c1, h1 ... c2, h2 ...).
    group_columns_by_parameter = true,

    -- Sort peaks by their center (or first parameter). Set to `false` to disable sorting.
    sort_peaks_by_center = true,

    -- List of background function names to exclude from parameter reports.
    background_function_names = {"Linear", "Quadratic"},

    -- List of parameter names to extract from each peak, applied identically
    -- to every peak column (e.g. {"center", "height", "hwhm"}).
    -- Set to {} or nil to auto-detect instead: parameters are then discovered
    -- independently PER PEAK POSITION (via get_info on each function actually
    -- found there, across all datasets), so peak 1 and peak 2 can end up with
    -- different parameter sets if they use different function types.
    parameter_names = {},

    -- Error columns for the report.
    -- Set to `true` (or "auto") to automatically generate error headers (e.g. "eCenter").
    -- Set to a list of strings (e.g. {"eCenter", "eHeight"}) to customize names.
    -- Set to `nil` or `false` to disable.
    error_columns = true,

    -- Optional Lua pattern to extract part of a filename for the column "File". "" uses the full name.
    -- Example: "filename_(%d+)" extracts '010' from 'filename_010-suffix.txt'.
    file_label_pattern = "",

    -- List of custom fitting functions to define in Fityk.
    -- Each string in the list should be a valid Fityk command.
    -- Note: 'x' is implicit in Fityk defines and must NOT appear in the parameter list.
    -- Example: {"define PearsonIV(height, center, width=1, shape_m=1, skewness=0) = height * (1 + ((x - center)/width)^2)^(-shape_m) * exp(-skewness * atan((x - center)/width))"}
    custom_functions = {},

    -- Fitting method for the batch fit ("" keeps Fityk's current setting).
    -- NOTE: parameter 'bounds' below are only honored by methods that support
    -- box constraints, e.g. "mpfit" or "nlopt_lbfgs"; the default
    -- Levenberg-Marquardt ignores variable domains.
    fitting_method = "",

    -- Parameter bounds (variable domains) applied before each fit, keyed by
    -- parameter name. Example: parameter_bounds = {hwhm = {0.1, 50}, shape = {0, 1}}
    -- Only simple (fittable, "~value") variables are touched; locked or
    -- compound variables are skipped.
    parameter_bounds = {},

    -- Post-fit sanity check: after each fit, the dataset is flagged as bad if
    -- any peak 'center' left the data x-range (with a 10% margin) or any
    -- width-like parameter (name containing 'hwhm' or 'width') collapsed to
    -- ~0 or exceeded the data span. A flagged dataset is never used as the
    -- model source for the next dataset (see 'model_propagation').
    sanity_check = true,

    -- Source of the initial model copied to each dataset during the batch fit:
    -- "previous": last dataset that passed the sanity check (falls back to n-1)
    -- "first":    always the first fitted dataset (first_dataset)
    -- "none":     no copying; each dataset must already have its own model
    model_propagation = "previous",

    -- If true, appends fit-quality columns to each report row:
    -- rChi2 (= WSSR/DoF, reduced chi-square), R2 and DoF.
    report_fit_quality = true,

    -- If true, 'center' is moved to the front of each peak's auto-detected
    -- parameter list, so it becomes the first column of each peak group and
    -- the key used by 'sort_peaks_by_center'. (Manual 'parameter_names' is not affected.)
    center_first = true,

    -- Peak-to-column matching across datasets:
    -- false: peaks are sorted by center in each dataset independently, so two
    --        peaks that cross during a series will swap columns.
    -- true:  nearest-neighbor tracking - each peak goes to the column whose
    --        last known center is closest, so crossing peaks keep their columns.
    track_peaks = false,

    -- If true, saves the full Fityk session (data, models, fitted parameters)
    -- after processing, so any spectrum of the batch can be reopened later
    -- with all its fitted functions: exec 'session_file.fit' in Fityk.
    save_session = false,

    -- Session output file, used when save_session = true.
    session_output_file = "fityk_session.fit",

    -- If true, at most once a day the script checks GitHub for a newer
    -- version of itself and prints a notice. Read-only request via curl;
    -- nothing is downloaded or installed automatically, and failures
    -- (offline, no curl) are silent. Set to false to disable.
    check_for_updates = true,
}

------------------------------------------------------------
-- 📦 SCRIPT LOGIC (Do not edit below this line)
------------------------------------------------------------

local BatchProcessor = {}

-- Helper: Logging
function BatchProcessor.log(level, message)
    print(string.format("[%s] %s", level, message))
end

-- Old configuration keys (used up to v3.4) -> current self-explanatory names.
-- External config files written with the old names still work: their values
-- are migrated automatically, but a warning asks the user to update the file.
BatchProcessor.deprecated_keys = {
    lowerL              = "x_min",
    upperL              = "x_max",
    excludeRegions      = "exclude_regions",
    n_i                 = "first_dataset",
    n_f                 = "last_dataset",
    sortByType          = "group_columns_by_parameter",
    sortByFirstParam    = "sort_peaks_by_center",
    backgroundFuncNames = "background_function_names",
    headerStr           = "parameter_names",
    errorStr            = "error_columns",
    fileinfo_mask       = "file_label_pattern",
    bounds              = "parameter_bounds",
    sanityCheck         = "sanity_check",
    propagation         = "model_propagation",
    reportFitQuality    = "report_fit_quality",
    centerFirst         = "center_first",
    trackPeaks          = "track_peaks",
}

-- Old mode values -> current names.
BatchProcessor.deprecated_modes = {
    normalize_and_replot = "normalize",
}

-- Helper: Levenshtein edit distance, used for "did you mean" suggestions.
local function editDistance(a, b)
    local la, lb = #a, #b
    local prev, cur = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev, cur = cur, prev
    end
    return prev[lb]
end

-- Helper: directory where this Lua script is located.
function BatchProcessor.getScriptDir()
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

-- Helper: closest valid config key to 'key', or nil if nothing is close
-- enough to be a plausible typo.
function BatchProcessor.suggestKey(key)
    local best, best_d = nil, 4
    local lk = key:lower()
    for valid in pairs(UserConfig) do
        local d = editDistance(lk, valid:lower())
        if d < best_d then
            best_d, best = d, valid
        end
    end
    return best
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

        -- Extract parameters from signature (e.g. "Voigt(height, center, gwidth=...)").
        -- %b() matches the full balanced parenthesis group, so default values
        -- containing parentheses (e.g. "q=exp(...)") don't truncate the list;
        -- the split below only breaks on top-level commas for the same reason.
        local sig = val:match(template .. "%s*%b()")
        if sig then
            local paramsStr = sig:match("%((.*)%)")
            local depth, start = 0, 1
            local function addParam(chunk)
                local pname = chunk:match("^%s*([%w_]+)")
                if pname then table.insert(names, pname) end
            end
            for i = 1, #paramsStr do
                local ch = paramsStr:sub(i, i)
                if ch == "(" then
                    depth = depth + 1
                elseif ch == ")" then
                    depth = depth - 1
                elseif ch == "," and depth == 0 then
                    addParam(paramsStr:sub(start, i - 1))
                    start = i + 1
                end
            end
            addParam(paramsStr:sub(start))
        end
    end

    -- Optionally promote 'center' to the front, so it becomes the first
    -- report column of each peak and the key used by sort_peaks_by_center.
    if UserConfig.center_first then
        for i, pname in ipairs(names) do
            if pname == "center" then
                if i > 1 then
                    table.remove(names, i)
                    table.insert(names, 1, pname)
                end
                break
            end
        end
    end

    BatchProcessor._templateParamCache[template] = names
    return names
end

-- Helper: is this function instance one of the configured background types?
function BatchProcessor.isBackground(func)
    for _, name in pairs(UserConfig.background_function_names) do
        if func:get_template_name() == name then return true end
    end
    return false
end

-- Helper: Validation
function BatchProcessor.validateConfig()
    local new_mode = BatchProcessor.deprecated_modes[UserConfig.mode]
    if new_mode then
        BatchProcessor.log("WARN", string.format("Mode '%s' was renamed to '%s'. Please update your config.", UserConfig.mode, new_mode))
        UserConfig.mode = new_mode
    end

    if type(UserConfig.error_columns) == "table" then
        if UserConfig.parameter_names and #UserConfig.parameter_names > 0 then
            if #UserConfig.error_columns ~= #UserConfig.parameter_names then
                error("Config Error: 'error_columns' length as a list must match 'parameter_names'. Use `true` for auto-naming.")
            end
        else
            -- A fixed error-name list has no clear meaning once headers are
            -- auto-detected independently per peak position (different
            -- positions can end up with different parameter sets/lengths).
            BatchProcessor.log("WARN", "'error_columns' as a list requires a manual 'parameter_names'; falling back to auto-naming (e.g. 'eCenter') since headers are auto-detected per peak position.")
            UserConfig.error_columns = true
        end
    end
end

-- Helper: Ensure a report file is always available for full-process workflows
function BatchProcessor.ensureReportOutputFile()
    if not UserConfig.report_output_file or UserConfig.report_output_file == "" then
        UserConfig.report_output_file = "parameters_report.txt"
    end
end

-- Helper: Append the fitting range to the output file names.
-- When append_range_to_report_name is enabled, both the report file and the
-- session file get a "_min-max" suffix, so runs over different regions of
-- the same data never overwrite each other's results.
function BatchProcessor.applyRangeToOutputNames()
    if not UserConfig.append_range_to_report_name then return end

    local lo, up
    if UserConfig.x_min > UserConfig.x_max then
        if F:get_dataset_count() > 0 then
            lo = F:calculate_expr("min(x)", 0)
            up = F:calculate_expr("max(x)", 0)
        else
            lo = 0
            up = 0
        end
    else
        lo = UserConfig.x_min
        up = UserConfig.x_max
    end

    -- Shell-safe suffix: no brackets (glob/wildcard metacharacters in
    -- PowerShell, Python glob, etc.) and no commas. Locale-formatted
    -- decimal commas ("24,5") are normalized to dots as well.
    local function fmtnum(v)
        return (string.format("%g", v):gsub(",", "."))
    end

    local function appendRange(filename)
        if not filename or filename == "" then return filename end
        local name, ext = filename:match("^(.*)(%..-)$")
        if not name then
            name = filename
            ext = ""
        end
        return string.format("%s_%s-%s%s", name, fmtnum(lo), fmtnum(up), ext)
    end

    UserConfig.report_output_file = appendRange(UserConfig.report_output_file)
    UserConfig.session_output_file = appendRange(UserConfig.session_output_file)
end

-- Helper: Load External Config
-- Looks for 'fityk_config.lua' in, by priority: the current working directory,
-- the directory of the first loaded dataset, and the directory of this script.
function BatchProcessor.loadExternalConfig()
    local config_name = "fityk_config.lua"
    local candidates = {config_name}

    local ok, fname = pcall(function() return F:get_info("filename", 0) end)
    if ok and fname and #fname > 0 then
        local data_dir = fname:match("^(.*)[/\\]")
        if data_dir and #data_dir > 0 then
            table.insert(candidates, data_dir .. "/" .. config_name)
        end
    end

    local info = debug.getinfo(1, "S")
    if info and info.source then
        local path = tostring(info.source):match("@?(.*)")
        local script_dir = path and path:match("^(.*)[/\\]")
        if script_dir and #script_dir > 0 then
            table.insert(candidates, script_dir .. "/" .. config_name)
        end
    end

    for _, config_file in ipairs(candidates) do
        local f = io.open(config_file, "r")
        if f then
            f:close()
            BatchProcessor.log("INFO", "Loading external configuration from '" .. config_file .. "'")
            local status, external_config = pcall(dofile, config_file)
            if status and type(external_config) == "table" then
                local old_keys, unknown_keys = {}, {}
                for k, v in pairs(external_config) do
                    local new_key = BatchProcessor.deprecated_keys[k]
                    if new_key then
                        UserConfig[new_key] = v
                        table.insert(old_keys, string.format("'%s' -> '%s'", k, new_key))
                    elseif UserConfig[k] ~= nil then
                        UserConfig[k] = v
                    else
                        table.insert(unknown_keys, k)
                    end
                end
                if #unknown_keys > 0 then
                    table.sort(unknown_keys)
                    for _, k in ipairs(unknown_keys) do
                        local hint = BatchProcessor.suggestKey(k)
                        if hint then
                            BatchProcessor.log("WARN", string.format("Unknown config key '%s' ignored - did you mean '%s'?", k, hint))
                        else
                            BatchProcessor.log("WARN", string.format("Unknown config key '%s' ignored.", k))
                        end
                    end
                end
                if #old_keys > 0 then
                    table.sort(old_keys)
                    BatchProcessor.log("WARN", "==============================================================")
                    BatchProcessor.log("WARN", "This 'fityk_config.lua' uses OLD configuration key names.")
                    BatchProcessor.log("WARN", "The values were migrated for this run, but please update the file:")
                    for _, m in ipairs(old_keys) do
                        BatchProcessor.log("WARN", "    " .. m)
                    end
                    BatchProcessor.log("WARN", "==============================================================")
                end
                BatchProcessor.log("INFO", "External configuration loaded successfully.")
            else
                BatchProcessor.log("ERROR", "Failed to load external config: " .. tostring(external_config))
            end
            return
        end
    end
    BatchProcessor.log("INFO", "No external config found ('" .. config_name .. "' in working, data or script directory). Using defaults.")
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
    if UserConfig.x_min > UserConfig.x_max then
        -- Fityk trick to enable all points if range is invalid/inverted
        F:execute("@*: A = a or not a")
    else
        -- Disable all, then enable only in range
        F:execute("@*: A = a and not a")
        F:execute(string.format("@*: A = a or (%f < x and x < %f)", UserConfig.x_min, UserConfig.x_max))
    end

    -- Punch out any excluded regions on top of the range above, without
    -- touching the active state of points outside of them.
    if UserConfig.exclude_regions then
        for _, region in ipairs(UserConfig.exclude_regions) do
            local lo, hi = region[1], region[2]
            if lo and hi then
                if lo > hi then lo, hi = hi, lo end
                F:execute(string.format("@*: A = a and not (%f < x and x < %f)", lo, hi))
            end
        end
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
-- Subtracts whatever function(s) are currently attached to each dataset, with
-- no name filtering at all - it's up to the user to have only the intended
-- baseline/background function(s) defined on the dataset before running this.
function BatchProcessor.subtractBaseline()
    BatchProcessor.log("INFO", "Subtracting baseline from data...")
    BatchProcessor.forEachDataset(function(n)
        local components = F:get_components(n) or {}
        local bg_terms = {}

        for i = 0, #components - 1 do
            local func = components[i]
            table.insert(bg_terms, "%" .. func.name .. "(x)")
        end

        if #bg_terms > 0 then
            F:execute(string.format("@%d: Y = Y - (%s)", n, table.concat(bg_terms, " + ")))
        else
            BatchProcessor.log("WARN", "Dataset " .. n .. " has no functions defined; skipping baseline subtraction.")
        end
    end)
end

-- Core: Apply configured parameter bounds (variable domains) to all
-- non-background functions of dataset n. Only simple variables ("~value")
-- are rewritten; locked or compound variables are left untouched so
-- constraints between parameters are never silently destroyed.
function BatchProcessor.applyBounds(n)
    if not UserConfig.parameter_bounds or next(UserConfig.parameter_bounds) == nil then return end
    local components = F:get_components(n) or {}
    for i = 0, #components - 1 do
        local func = components[i]
        if not BatchProcessor.isBackground(func) then
            local paramNames = BatchProcessor.getTemplateParamNames(func:get_template_name())
            for _, pname in ipairs(paramNames) do
                local range = UserConfig.parameter_bounds[pname]
                if range and range[1] and range[2] then
                    local ok, err = pcall(function()
                        local vname = func:var_name(pname)
                        local vinfo = F:get_info("$" .. vname)
                        if vinfo and vinfo:match("=%s*~") then
                            local val = func:get_param_value(pname)
                            -- Clamp the current value into the domain so the fit starts inside it
                            if val < range[1] then val = range[1] end
                            if val > range[2] then val = range[2] end
                            F:execute(string.format("$%s = ~%.8g [%g:%g]", vname, val, range[1], range[2]))
                        end
                    end)
                    if not ok then
                        BatchProcessor.log("WARN", string.format("Could not set bounds for '%s' of %%%s: %s", pname, func.name, tostring(err)))
                    end
                end
            end
        end
    end
end

-- Core: Post-fit sanity check for dataset n. Returns true when the fitted
-- peaks look reasonable: every 'center' inside the data x-range (+/- 10%
-- margin) and every width-like parameter neither collapsed (~0) nor wider
-- than the whole data span.
function BatchProcessor.checkFitSanity(n)
    local ok1, xmin = pcall(function() return F:calculate_expr("min(x)", n) end)
    local ok2, xmax = pcall(function() return F:calculate_expr("max(x)", n) end)
    if not (ok1 and ok2 and xmin and xmax) then return true end
    local span = xmax - xmin
    if span <= 0 then return true end
    local margin = 0.1 * span

    local components = F:get_components(n) or {}
    for i = 0, #components - 1 do
        local func = components[i]
        if not BatchProcessor.isBackground(func) then
            local paramNames = BatchProcessor.getTemplateParamNames(func:get_template_name())
            for _, pname in ipairs(paramNames) do
                local st, val = pcall(function() return func:get_param_value(pname) end)
                if st and val then
                    if pname == "center" and (val < xmin - margin or val > xmax + margin) then
                        BatchProcessor.log("WARN", string.format(
                            "Sanity: dataset %d, %%%s center=%.6g is outside the data range [%.6g, %.6g].",
                            n, func.name, val, xmin, xmax))
                        return false
                    end
                    local lname = pname:lower()
                    if lname:find("hwhm", 1, true) or lname:find("width", 1, true) then
                        local w = math.abs(val)
                        if w < span * 1e-6 or w > span then
                            BatchProcessor.log("WARN", string.format(
                                "Sanity: dataset %d, %%%s %s=%.6g collapsed or exceeds the data span (%.6g).",
                                n, func.name, pname, val, span))
                            return false
                        end
                    end
                end
            end
        end
    end
    return true
end

-- Core: Batch Fit
function BatchProcessor.batchFit()
    BatchProcessor.log("INFO", "Starting batch fit...")

    if UserConfig.fitting_method and UserConfig.fitting_method ~= "" then
        local ok, err = pcall(function()
            F:execute("set fitting_method = " .. UserConfig.fitting_method)
        end)
        if ok then
            BatchProcessor.log("INFO", "Fitting method set to '" .. UserConfig.fitting_method .. "'.")
        else
            BatchProcessor.log("WARN", "Could not set fitting method '" .. UserConfig.fitting_method .. "': " .. tostring(err))
        end
    elseif UserConfig.parameter_bounds and next(UserConfig.parameter_bounds) ~= nil then
        BatchProcessor.log("WARN", "'parameter_bounds' are set but no 'fitting_method' was chosen; the default Levenberg-Marquardt ignores domains (use e.g. \"mpfit\" or \"nlopt_lbfgs\").")
    end

    local first = UserConfig.first_dataset or 0
    local last_good = nil

    BatchProcessor.forEachDataset(function(n)
        BatchProcessor.log("INFO", "Fitting Dataset: " .. n)

        -- Pick the source model to copy into this dataset (never for the
        -- first one processed, which must already carry its own model).
        local source = nil
        if n > 0 and n > first then
            if UserConfig.model_propagation == "first" then
                source = first
            elseif UserConfig.model_propagation ~= "none" then -- "previous"
                source = last_good or (n - 1)
            end
        end
        if source then
            if source ~= n - 1 then
                BatchProcessor.log("INFO", string.format("Copying model from dataset %d (last good) instead of %d.", source, n - 1))
            end
            F:execute(string.format("@%d.F = copy(@%d.F)", n, source))
            -- Also propagate the zero-shift (x-correction) function list
            F:execute(string.format("@%d.Z = copy(@%d.Z)", n, source))
        end

        -- Check if model exists (has components) before fitting to avoid "No parametrized functions" error
        local components = F:get_components(n)
        if components and #components > 0 then
            BatchProcessor.applyBounds(n)
            F:execute(string.format("fit @%d", n))
            if not UserConfig.sanity_check or BatchProcessor.checkFitSanity(n) then
                last_good = n
            else
                BatchProcessor.log("WARN", string.format("Dataset %d failed the sanity check; it will not be used as the model source for later datasets.", n))
            end
        else
            BatchProcessor.log("WARN", "Dataset " .. n .. " has no functions. Skipping fit.")
        end
    end, UserConfig.first_dataset, UserConfig.last_dataset)
end

-- Core: Replot
function BatchProcessor.replot()
    BatchProcessor.forEachDataset(function(n)
        local lo, up
        if UserConfig.x_min > UserConfig.x_max then
            lo = F:calculate_expr("min(x)", n)
            up = F:calculate_expr("max(x)", n)
        else
            lo = UserConfig.x_min
            up = UserConfig.x_max
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
        -- Titles inherit the full file path when data is loaded with one;
        -- keep only the last path segment, then sanitize it. The dataset
        -- index prefix guarantees a unique file even when titles repeat.
        local base = (title:match("[^/\\]+$") or title):gsub("[^%w%-_]", "_")
        local filename = string.format("%d_%s.xy", n, base)

        -- Never overwrite the dataset's own source data file: if the
        -- generated name collides with it, add a '_fit' suffix.
        local ok_src, src = pcall(function() return F:get_info("filename", n) end)
        if ok_src and src and #src > 0 then
            local src_base = src:match("[^/\\]+$") or src
            if filename:lower() == src_base:lower() then
                filename = string.format("%d_%s_fit.xy", n, base)
                BatchProcessor.log("WARN", string.format(
                    "Dataset %d: output name would overwrite the source data file '%s'; saving as '%s' instead.",
                    n, src_base, filename))
            end
        end

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
    -- Peak-tracking state (used when UserConfig.track_peaks is true):
    local trackCenters = {}   -- column position k -> last known center
    local trackCount = 0      -- number of columns created so far

    for n = 0, dataset_count - 1 do
        local components = F:get_components(n) or {}
        local peaks = {}

        for i = 0, #components - 1 do
            local func = components[i]
            if not BatchProcessor.isBackground(func) then
                local template = func:get_template_name()
                local paramNames = BatchProcessor.getTemplateParamNames(template)
                local values, errors = {}, {}

                for _, pname in ipairs(paramNames) do
                    local status, val = pcall(function() return func:get_param_value(pname) end)
                    if status and val then
                        values[pname] = val
                        if UserConfig.error_columns then
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

        -- 2. Column assignment.
        --    Default: sort by 'center' so column k means "k-th peak left to
        --    right" in each dataset independently.
        --    track_peaks: nearest-neighbor matching against each column's last
        --    known center, so peaks that cross during a series keep their
        --    columns instead of swapping.
        if UserConfig.track_peaks then
            local arranged = {}
            if trackCount == 0 then
                -- First dataset with peaks establishes the column order.
                table.sort(peaks, function(a, b) return a.sortKey < b.sortKey end)
                for k, peak in ipairs(peaks) do
                    arranged[k] = peak
                    trackCenters[k] = peak.sortKey
                end
                trackCount = #peaks
            else
                -- Greedy best-match: closest (peak, column) pairs first.
                local candidates = {}
                for pi, peak in ipairs(peaks) do
                    for k = 1, trackCount do
                        table.insert(candidates, {d = math.abs(peak.sortKey - trackCenters[k]), pi = pi, k = k})
                    end
                end
                table.sort(candidates, function(a, b) return a.d < b.d end)
                local usedPeak, usedCol = {}, {}
                for _, cand in ipairs(candidates) do
                    if not usedPeak[cand.pi] and not usedCol[cand.k] then
                        usedPeak[cand.pi], usedCol[cand.k] = true, true
                        arranged[cand.k] = peaks[cand.pi]
                        trackCenters[cand.k] = peaks[cand.pi].sortKey
                    end
                end
                -- More peaks than known columns: append new columns.
                for pi, peak in ipairs(peaks) do
                    if not usedPeak[pi] then
                        trackCount = trackCount + 1
                        arranged[trackCount] = peak
                        trackCenters[trackCount] = peak.sortKey
                    end
                end
            end
            all_datasets_peaks[n] = arranged
            if trackCount > max_peaks then
                max_peaks = trackCount
            end
        else
            if UserConfig.sort_peaks_by_center then
                table.sort(peaks, function(a, b) return a.sortKey < b.sortKey end)
            end
            all_datasets_peaks[n] = peaks
            if #peaks > max_peaks then
                max_peaks = #peaks
            end
        end
    end

    if max_peaks == 0 then
        -- Legitimate situation, e.g. fitting only the background in
        -- preparation for a baseline subtraction - warn and skip the report
        -- instead of aborting the whole run.
        BatchProcessor.log("WARN", "No non-background functions found in any dataset (only types listed in 'background_function_names'?). Parameter report skipped.")
        return false
    end

    -- 3. Header resolution per peak position.
    --    - Manual 'parameter_names' (non-empty): applied identically to every position (legacy behavior).
    --    - Otherwise: auto-detected independently per position, starting from
    --      whichever function is found there first (in its own declared param
    --      order) and growing if a later dataset places a different function
    --      type (with previously-unseen params) at that same position.
    local manualHeaders = UserConfig.parameter_names and #UserConfig.parameter_names > 0
    local positionHeaders = {}

    if manualHeaders then
        for k = 1, max_peaks do
            positionHeaders[k] = UserConfig.parameter_names
        end
    else
        BatchProcessor.log("INFO", "'parameter_names' is empty. Auto-detecting parameters per peak position...")
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
    --    or grouped by parameter type (c1,c2,...,h1,h2,...) when
    --    group_columns_by_parameter is enabled. Built as (position, name)
    --    pairs so both the header and every row can be driven off the exact
    --    same list.
    local columnOrder = {}
    if UserConfig.group_columns_by_parameter then
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
        if UserConfig.error_columns then
            local err_name
            if manualHeaders and type(UserConfig.error_columns) == "table" then
                for j, hn in ipairs(UserConfig.parameter_names) do
                    if hn == col.name then err_name = UserConfig.error_columns[j] break end
                end
            end
            err_name = err_name or ("e" .. col.name:gsub("^%l", string.upper))
            table.insert(header_parts, err_name .. col.k)
        end
    end
    if UserConfig.report_fit_quality then
        table.insert(header_parts, "rChi2")
        table.insert(header_parts, "R2")
        table.insert(header_parts, "DoF")
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
        if UserConfig.file_label_pattern and #UserConfig.file_label_pattern > 0 then
            fileN = string.match(fileN, UserConfig.file_label_pattern) or fileN
        end
        table.insert(row_parts, fileN)

        local peaks = all_datasets_peaks[n]
        for _, col in ipairs(columnOrder) do
            local peak = peaks[col.k]
            local val = peak and peak.values[col.name]
            table.insert(row_parts, fmt(val))
            if UserConfig.error_columns then
                local err_val = peak and peak.errors[col.name]
                table.insert(row_parts, fmt(err_val))
            end
        end

        -- Fit-quality columns: reduced chi-square (WSSR/DoF), R2 and DoF.
        if UserConfig.report_fit_quality then
            local okw, wssr = pcall(function() return F:get_wssr(n) end)
            local okd, dof = pcall(function() return F:get_dof(n) end)
            local okr, r2 = pcall(function() return F:get_rsquared(n) end)
            local rchi2
            if okw and okd and wssr and dof and dof > 0 then
                rchi2 = wssr / dof
            end
            table.insert(row_parts, rchi2 and string.format("%.6g", rchi2) or "-")
            table.insert(row_parts, (okr and r2) and string.format("%.6f", r2) or "-")
            table.insert(row_parts, (okd and dof) and string.format("%d", dof) or "-")
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

    return true
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

    local workdir = get_workdir()
    local script_dir = BatchProcessor.getScriptDir()

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

-- Helper: numeric version comparison ("3.10" > "3.9" > "3.8.1" > "3.8").
local function isNewerVersion(remote, current)
    local function parts(s)
        local t = {}
        for num in tostring(s):gmatch("%d+") do table.insert(t, tonumber(num)) end
        return t
    end
    local r, c = parts(remote), parts(current)
    for i = 1, math.max(#r, #c) do
        local a, b = r[i] or 0, c[i] or 0
        if a > b then return true end
        if a < b then return false end
    end
    return false
end

-- Helper: at most once a day, check GitHub for a newer version of this
-- script and print a notice. Never disturbs the workflow: any failure
-- (offline, no curl, repo unreachable) is silent, and every attempt -
-- successful or not - postpones the next check by a day, so an offline
-- machine stalls on curl's timeout at most once per day.
function BatchProcessor.checkForUpdates()
    if not UserConfig.check_for_updates then return end

    pcall(function()
        local stamp_file = BatchProcessor.getScriptDir() .. "/.fityktools_update_check"

        local f = io.open(stamp_file, "r")
        if f then
            local last = tonumber(f:read("*l") or "")
            f:close()
            if last and os.time() - last < 86400 then return end
        end

        local sf = io.open(stamp_file, "w")
        if sf then
            sf:write(tostring(os.time()))
            sf:close()
        end

        local p = io.popen('curl -s --max-time 3 "' .. UPDATE_URL .. '"')
        if not p then return end
        local body = p:read("*a") or ""
        p:close()

        -- The 'Version:' line of the remote script's header comes first.
        local remote = body:match("Version:%s*([%d%.]+)")
        if remote and isNewerVersion(remote, SCRIPT_VERSION) then
            BatchProcessor.log("INFO", string.format(
                "A newer FitykTools version is available: %s (you are running %s). Get it at https://github.com/alepayala/FitykTools",
                remote, SCRIPT_VERSION))
        end
    end)
end

-- Helper: Save the full Fityk session (data, models, fitted parameters) so
-- any spectrum of the batch can be reopened and inspected later.
function BatchProcessor.saveSession()
    if not UserConfig.save_session then return end
    local fname = UserConfig.session_output_file
    if not fname or fname == "" then fname = "fityk_session.fit" end
    local ok, err = pcall(function()
        F:execute(string.format("info state > '%s'", fname))
    end)
    if ok then
        BatchProcessor.log("INFO", "Session saved to '" .. fname .. "'. Reload it with: exec '" .. fname .. "'")
    else
        BatchProcessor.log("WARN", "Could not save session: " .. tostring(err))
    end
end

-- Helper: Launch the plotter when auto_plot is enabled and a report file exists
function BatchProcessor.maybeAutoPlot()
    if not UserConfig.auto_plot then return end
    if not UserConfig.report_output_file or UserConfig.report_output_file == "" then
        BatchProcessor.log("WARN", "auto_plot is enabled but no 'report_output_file' is set; skipping plotter.")
        return
    end
    local ok, err = pcall(function()
        BatchProcessor.launchPlotter(UserConfig.report_output_file)
    end)
    if not ok then
        BatchProcessor.log("WARN", "Auto-plot failed: " .. tostring(err))
    end
end

-- Main Run Function
function BatchProcessor.run()
    BatchProcessor.loadExternalConfig()
    BatchProcessor.validateConfig()
    
    print("🚀 Starting Fityk Batch Processing Script v" .. SCRIPT_VERSION .. "...")
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
                elseif tostring(err):lower():find("already defined", 1, true) then
                    BatchProcessor.log("INFO", "Function '" .. func_name .. "' is already defined.")
                else
                    BatchProcessor.log("ERROR", "Failed to define '" .. func_name .. "': " .. tostring(err))
                end
            else
                -- Execute generic Fityk command safely
                pcall(function() F:execute(func_cmd) end)
            end
        end
    end

    local valid_mode = true

    -- Modes that always write a report get a default filename if none is set;
    -- then the range suffix (if enabled) is applied to all output names.
    if UserConfig.mode == "full_process" or UserConfig.mode == "full_process_and_save" or UserConfig.mode == "save_table" then
        BatchProcessor.ensureReportOutputFile()
    end
    BatchProcessor.applyRangeToOutputNames()

    -- Apply the fitting window and exclusions in EVERY mode, so the active
    -- points of the spectra always reflect the configuration (not only when
    -- fitting).
    BatchProcessor.setLimits()

    if UserConfig.mode == "full_process" then
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        if BatchProcessor.generateReport() then
            BatchProcessor.maybeAutoPlot()
        end

    elseif UserConfig.mode == "full_process_and_save" then
        BatchProcessor.batchFit()
        BatchProcessor.replot()
        local report_ok = BatchProcessor.generateReport()
        BatchProcessor.saveAllData()
        if report_ok then
            BatchProcessor.maybeAutoPlot()
        end

    elseif UserConfig.mode == "save_table" then
        if BatchProcessor.generateReport() then
            BatchProcessor.maybeAutoPlot()
        end

    elseif UserConfig.mode == "fit_only" then
        BatchProcessor.batchFit()
        BatchProcessor.replot()

    elseif UserConfig.mode == "report_only" then
        if BatchProcessor.generateReport() then
            BatchProcessor.maybeAutoPlot()
        end

    elseif UserConfig.mode == "normalize" then
        BatchProcessor.normalize()
        BatchProcessor.replot()

    elseif UserConfig.mode == "subtract_baseline" then
        BatchProcessor.subtractBaseline()
        BatchProcessor.replot()

    else
        BatchProcessor.log("ERROR", "Unknown process_mode: " .. tostring(UserConfig.mode))
        valid_mode = false
    end

    if valid_mode then
        BatchProcessor.saveSession()
    end

    BatchProcessor.checkForUpdates()

    print("✅ Script finished.")
end

-- Execute
BatchProcessor.run()
