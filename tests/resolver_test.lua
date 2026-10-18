local Resolver = dofile("resolver.lua")
local total = 0
local function test(name, callback)
    callback()
    total = total + 1
    print("OK " .. name)
end
local function factory(routes, decoded, options)
    local calls = {}
    local resolver = Resolver.new({
        endpoint = "https://lookup/?gameId=",
        request = function(url)
            calls[#calls + 1] = url
            local result = routes[url]
            if type(result) == "string" then error(result) end
            return result and result[1] or 404, result and result[2] or "missing"
        end,
        decode = function(body)
            if decoded[body] == nil then error("invalid JSON") end
            return decoded[body]
        end,
        compile = function(source, name) return load(source, name, "t", {}) end,
        catalog = (options or {}).catalog or {},
    })
    return resolver, calls
end

test("direct lookup does not call a Key endpoint", function()
    local resolver, calls = factory({["https://lookup/?gameId=10"] = {200, "json"}}, {json = {["10"] = "https://code/script"}})
    assert(resolver:resolve(10, 20).url == "https://code/script")
    assert(#calls == 1 and calls[1] == "https://lookup/?gameId=10")
end)
test("canonical place fallback", function()
    local resolver = factory({["https://lookup/?gameId=10"] = {200, "json"}}, {json = {["10"] = "https://code/script"}}, {catalog = {{p="10",u="20",n="Example"}}})
    local record = assert(resolver:resolve(99, 20))
    assert(record.resolvedPlaceId == "10" and record.usedCanonicalPlace and record.name == "Example")
end)
test("cache and manual refresh", function()
    local resolver, calls = factory({["https://lookup/?gameId=10"] = {200, "json"}}, {json = {["10"] = "https://code/script"}})
    assert(resolver:resolve(10,20)); assert(resolver:resolve(10,20)); assert(#calls==1)
    assert(resolver:resolve(10,20,true)); assert(#calls==2)
end)
test("404 remains unavailable", function()
    local resolver = factory({}, {})
    local record, err = resolver:resolve(10,20)
    assert(not record and err.code == "not_found")
end)
test("invalid JSON cannot become success", function()
    local resolver = factory({["https://lookup/?gameId=10"] = {200,"bad"}}, {})
    local record, err = resolver:resolve(10,20)
    assert(not record and err.code == "invalid_json")
end)
test("wrong game ID is not selected", function()
    local resolver = factory({["https://lookup/?gameId=10"] = {200,"json"}}, {json = {["11"]="https://code/other"}})
    local record, err = resolver:resolve(10,20)
    assert(not record and err.code == "not_found")
end)
test("network error is reported", function()
    local resolver = factory({["https://lookup/?gameId=10"] = "offline"}, {})
    local record, err = resolver:resolve(10,20)
    assert(not record and err.code == "network")
end)
test("array response supported", function()
    assert(Resolver.selectUrl({["10"]={"https://code/first","https://code/second"}},10) == "https://code/first")
    assert(not Resolver.selectUrl({["10"]="javascript:alert(1)"},10))
end)
test("known intermediate GUI is skipped without running it", function()
    local wrapper = [[local keylessScript = 'loadstring(game:HttpGet("https://code/final"))()' -- KeylessTinyGui]]
    local resolver = factory({["https://code/wrapper"]={200,wrapper},["https://code/final"]={200,"return 42"}}, {})
    local chunk, err, details = resolver:prepare({url="https://code/wrapper",resolvedPlaceId="10"})
    assert(chunk and not err and chunk()==42 and #details.chain==2)
end)
test("wrapper loops are stopped", function()
    local source = [[local keylessScript = 'loadstring(game:HttpGet("https://code/loop"))()' -- KeylessTinyGui]]
    local resolver = factory({["https://code/loop"]={200,source}}, {})
    local chunk, err = resolver:prepare({url="https://code/loop",resolvedPlaceId="10"})
    assert(not chunk and err.code=="loop")
end)
test("compile failure does not run a script", function()
    local resolver = factory({["https://code/bad"]={200,"this is not Lua"}}, {})
    local chunk, err = resolver:prepare({url="https://code/bad",resolvedPlaceId="10"})
    assert(not chunk and err.code=="compile_error")
end)
test("return to the Key form is reported", function()
    local resolver = factory({["https://code/auth"]={200,"M.validateKeyNew()"}}, {})
    local chunk, err = resolver:prepare({url="https://code/auth",resolvedPlaceId="10"})
    assert(not chunk and err.code=="auth_loader")
end)
print("PASSED " .. total .. " resolver tests")
