-- IQ / guilherme951516: painel original com abertura por rota publica.
local ROOT = "https://raw.githubusercontent.com/guilherme951516/iq-sem-key/main/"
local function loadModule(path)
    local source = game:HttpGet(ROOT .. path, true)
    local chunk, err = loadstring(source, "@IQ/" .. path)
    if not chunk then error("[IQ] " .. path .. ": " .. tostring(err), 0) end
    return chunk()
end
local start = loadModule("panel.lua")
return start({rootUrl = ROOT, load = loadModule})
