#!tarantool


local re = require 'relabel'
local fio = require 'fio'

local index_rst = '../tarantool-doc/doc/reference/reference_lua/index.rst'

local file = fio.open(index_rst, 'O_RDONLY')
local fulltext = file:read()

local toctree = {}

local pattern = re.compile ([[ --lpeg
        RST             <- (TocTree / SkipLine )*
        SkipLine        <- {[^%nl]* %nl}
        TocTree         <- TocTreeHeader SkipHeaders References
        SkipHeaders     <- (WsIndent ':' keyword ':' [^%nl]* %nl)* %nl
        TocTreeHeader   <- '..' [ ] { 'toctree' }'::' [^%nl]* %nl
        References      <- (WsIndent Reference %nl)*
        Reference       <- { [a-zA-Z0-9_]+ } -> matchr
        WsIndent        <- [ \t\n]^+4
        keyword         <- {[a-zA-Z]+}
]], {
        matchr = function (s)
                table.insert(toctree, s)
                -- print('ref', require'json'.encode(s), ...)
        end,
})

local T = pattern:match(fulltext)
-- print(require'json'.encode(T))
print(require'json'.encode(toctree))

os.exit(0)
