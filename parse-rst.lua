#!tarantool


local re = require 'relabel'
local fio = require 'fio'

local index_rst = '../tarantool-doc/doc/reference/reference_lua/index.rst'
local basepath
local fulltext

local backlog = {}
local verbose = true
local currfile
local titles = {}
local modules = {}

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

local function file_open(path)
    if path == nil then
        fulltext = nil
        return
    end
    basepath = fio.dirname(path)
    currfile = fio.open(path, 'O_RDONLY')
    fulltext = currfile ~= nil and currfile:read()
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
    assert(currfile ~= nil)
    assert(titles[currfile] == nil)
    titles[currfile] = s
    report_title(s)
end

local function save_module(s)
    if s == nil then
        return
    end
    assert(currfile ~= nil)
    assert(modules[currfile] == nil)
    modules[currfile] = s
    modules[s] = currfile
    report_module(s)
end

local pattern = re.compile([[ --lpeg
    RST             <- (TocTree / ModuleHeader / Module / SkipLine )*
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
]], {
    matchr = function(s) enqueue_file(s) end,
    match_title = function(s) save_title(s) end,
    match_module = function(s) save_module(s) end,
    match_skip = function(s) print('...', s) end,
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
report_queue()

os.exit(0)
