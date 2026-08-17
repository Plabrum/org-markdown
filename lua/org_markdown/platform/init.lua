-- Platform shim: a thin, stable interface over filesystem, path, and
-- notification primitives. Core modules call this instead of `vim.*` directly
-- so they run both in-editor and under the standalone CLI (plain luajit).
--
-- The backend is chosen once at load time: the Neovim runtime when a `vim`
-- global with libuv is present, otherwise the pure-Lua standalone backend.
--
--- @class OrgPlatformFs
--- @field scandir fun(dir: string): { name: string, type: string }[]
--- @field cwd fun(): string
--- @field read_file fun(path: string): string|nil, string|nil
--- @field write_file fun(path: string, content: string): boolean, string|nil
---
--- @class OrgPlatformPath
--- @field expand fun(p: string): string
--- @field basename fun(p: string): string
--- @field relative fun(p: string): string
---
--- @class OrgPlatform
--- @field fs OrgPlatformFs
--- @field path OrgPlatformPath
--- @field notify fun(msg: string, level?: integer)

local function in_neovim()
	return _G.vim ~= nil and vim.uv ~= nil
end

---@type OrgPlatform
local backend
if in_neovim() then
	backend = require("org_markdown.platform.nvim")
else
	backend = require("org_markdown.platform.standalone")
end

return backend
