#!tarantool


local re = require 'relabel'
local fio = require 'fio'

local index_rst = '../tarantool-doc/doc/reference/reference_lua/index.rst'
local basepath
local fulltext

local backlog = {}
local verbose = true
local currfile
local currfunction
local modules = {}
local module

local function report_file(path)
    if verbose and path ~= nil then
        print('processing: ', path)
    end
end

local function report_title(title)
    if verbose and title ~= nil then
        print('title: ', title)
    end
end

local function report_module(name)
    if verbose and name ~= nil then
        print('module: ', name)
    end
end

local function report_function(name, is_alias)
    if verbose and name ~= nil then
        print(is_alias and 'alias:' or 'function: ', name)
    end
end

local function report_param_descr(name, text)
    if verbose and name ~= nil then
        print('param: ', name)
    end
    if verbose and text ~= nil then
        print('descr: ', text)
    end
end

local function report_modules()
    if verbose then
        print('modules:\n', require'json'.encode(modules))
    end
end

local function save_current_module()
    if module == nil then
        return
    end
    assert(module.name ~= nil)
    modules[module.name] = module -- FIXME - merge
end

local function merge_module(name)
end

local function open_new_module(path)
    save_current_module()
    local guessedname = fio.basename(path, '.rst')
    module = {
        name = guessedname,
        file = path
    }
end

local function file_open(path)
    if path == nil then
        fulltext = nil
        return
    end
    basepath = fio.dirname(path)
    currfile = fio.open(path, 'O_RDONLY')
    fulltext = currfile ~= nil and currfile:read()
    open_new_module(path)
    report_file(path)
end

local function enqueue_file(ref)
    local fullpath = fio.pathjoin(basepath, ref .. '.rst')
    if not backlog[fullpath] then
        table.insert(backlog, fullpath)
        backlog[fullpath] = true
    end
end

local function dequeue_file()
    if #backlog < 1 then
        return nil
    end
    -- backlog[head] = nil -- do not clean, to not process twice
    return table.remove(backlog, 1)
end

local function report_queue()
    if not verbose then
        return
    end
    if #backlog < 1 then
        print('backlog is empty')
        return
    end
    for key, v in ipairs(backlog) do
        print(('%d. %s'):format(key, v))
    end
end

local function save_title(s)
    if s == nil then
        return
    end
    assert(module ~= nil)
    module.title = s
    report_title(s)
end

local function save_module(s)
    if s == nil then
        return
    end
    assert(currfile ~= nil)
    assert(module ~= nil)
    -- modules[currfile] = s
    -- preload values if already existing
    module = modules[s] or module
    module.name = s
    report_module(s)
end

local function save_function(name, is_alias)
    assert(name ~= nil)
    assert(type(name) == 'string')
    assert(module ~= nil)
    if module.funcs == nil then
        module.funcs = {}
    end
    if not is_alias then
        table.insert(module.funcs, name)
        module.funcs[name] = {}
        currfunction = name
    else
        assert(currfunction ~= nil)
        if module.funcs[currfunction].aliases == nil then
            module.funcs[currfunction].aliases = {}
        end
        table.insert(module.funcs[currfunction].aliases, name)
    end
    report_function(name, is_alias)
end

local function save_paramdescr(name, text)
    --assert(text ~= nil)
    --assert(type(text) == 'string')
    assert(name ~= nil)
    assert(type(name) == 'string')
    assert(module ~= nil)
    assert(module.funcs ~= nil)
    assert(currfunction ~= nil)
    if module.funcs[currfunction].params == nil then
        module.funcs[currfunction].params = {}
    end
    table.insert(module.funcs[currfunction].params, {name = name, descr = text})

    report_param_descr(name, text)
end

local pattern = re.compile([[ --lpeg
    RST             <- (TocTree / ModuleHeader / Module /
                        FunctionDef / SkipLine )*
    SkipLine        <- {[^%nl]* %nl}
    keyword         <- {[a-zA-Z]+}
    WsIndent        <- %s^+4

    TocTree         <- TocTreeHeader SkipHeaders References
    SkipHeaders     <- (WsIndent ':' keyword ':' [^%nl]* %nl)* %nl
    TocTreeHeader   <- '..' [ ]^+1 'toctree::' [^%nl]* %nl
    References      <- (WsIndent Reference %nl? / %nl)*
    Reference       <- { [a-zA-Z0-9_/]+ } -> matchr

    ModuleHeader    <- Divisor Title Divisor
    Divisor         <- '-'^+4 %nl
    Title           <- IndentSpace ModuleTitle %nl
    IndentSpace     <- %s^+4
    ModuleTitle     <- {[^%nl]+} -> match_title

    Module          <- '..' [ ]^+1 'module::' ModuleName %nl
    ModuleName      <- {[^%nl]*} -> match_module

    FunctionDef     <- '..' [ ]^+1 'function::' FuncHeader FuncDescription
                       FuncParams FuncReturn
    FuncHeader      <- FuncName %nl ([ ]^+12 FuncNameCont %nl)*
    FuncName        <- [ ]*{[^%nl]*} -> match_funcname1
    FuncNameCont    <- [ ]*{[^%nl]*} -> match_funcname2
    FuncDescription <- (WsIndent Description %nl? / %nl)*
    Description     <- (!(':param' / ':return:' / ':rtype:' / '..') [^%nl]+)

    FuncParams      <- (WsIndent ':param' FuncParamName %nl? / %nl)*
    FuncParamName   <- ({[^:]+} ':' {[^%nl]*}) -> match_paramdescr
    FuncReturn      <- (FuncReturnInfo / FuncReturnType / %nl)*
    FuncReturnInfo  <- (WsIndent ':return:' [ ]* {[^%nl]*} %nl) -> match_skip
    FuncReturnType  <- (WsIndent ':rtype:' [ ]* {[^%nl]*} %nl) -> match_skip
]], {
    matchr = function(s) enqueue_file(s) end,
    match_title = function(s) save_title(s) end,
    match_module = function(s) save_module(s) end,
    match_funcname1 = function(s) save_function(s, false) end,
    match_funcname2 = function(s) save_function(s, true) end,
    match_paramdescr = function(p, d) save_paramdescr(p, d) end,
    match_skip = function(a, ...) print('...', a, ...) end,
})

-- start from root documentation index
file_open(index_rst)

while fulltext do
    pattern:match(fulltext)
    -- then continue with all submitted references
    local next = dequeue_file()
    if next == nil then
        break
    end
    file_open(next)
    -- stop if we have failed to open any of enqueued files
end
save_current_module()
report_queue()
report_modules()

os.exit(0)
