local ROOT = "https://raw.githubusercontent.com/guilherme951516/iq-sem-key/main/"
local fetched = {}
game = {HttpGet = function(_, url)
    assert(url:sub(1,#ROOT)==ROOT)
    assert(url:sub(-13)=="?v=20261018.2")
    fetched[#fetched+1] = url
    return url:find("panel.lua",1,true) and "mock-panel" or "mock-dependency"
end}
loadstring = function(source)
    if source=="mock-panel" then
        return function()
            return function(context)
                assert(context.entryUrl==ROOT.."IQ.lua?v=20261018.2")
                assert(context.resource("catalog.json")==ROOT.."catalog.json?v=20261018.2")
                assert(context.load("resolver.lua")=="dependency-loaded")
                return "panel-started"
            end
        end
    end
    assert(source=="mock-dependency")
    return function() return "dependency-loaded" end
end
assert(dofile("IQ.lua")=="panel-started" and #fetched==2)
print("OK entry versions every dependency URL and starts the panel")
