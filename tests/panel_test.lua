local start = dofile("panel.lua")
local Resolver = dofile("resolver.lua")
local ROOT = "https://raw.githubusercontent.com/guilherme951516/iq-sem-key/main/"
local ENTRY = ROOT .. "IQ.lua?v=20261018.2"
local function scenario(available, mode)
    local calls, buttons, labels, clipboard = {}, {}, {}, nil
    local library = {Options = {}, unloaded = false}
    local unloadedCallback
    function library:OnUnload(callback) unloadedCallback = callback end
    function library:Unload() self.unloaded = true; if unloadedCallback then unloadedCallback() end end
    function library:Notify(data) calls[#calls+1] = "notify:" .. data.Description end
    local function label(text)
        local value = {Text = text}
        function value:SetText(newText) self.Text = newText end
        function value:AddKeyPicker(id) library.Options[id] = {}; return self end
        labels[#labels+1] = value
        return value
    end
    local function group()
        local value = {}
        function value:AddLabel(text) return label(text) end
        function value:AddButton(options) buttons[options.Text] = options.Func end
        function value:AddDivider() end
        function value:AddToggle() end
        return value
    end
    local function tab(name)
        local value = {name = name}
        function value:AddLeftGroupbox() return group() end
        function value:AddRightGroupbox() return group() end
        function value:Show() calls[#calls+1] = "show:" .. self.name end
        return value
    end
    function library:CreateWindow(options)
        assert(options.Title == "COMBOWICK" and options.AutoShow)
        local value = {}
        function value:AddTab(name) return tab(name) end
        return value
    end
    local manager = setmetatable({}, {__index=function() return function() end end})
    local module = {LANG = "en"}
    function module.buildHomeTab() return tab("Info") end
    function module.buildGamesTab() return tab("Jogos") end
    function module.addGoldTheme() calls[#calls+1] = "gold-theme" end
    function module.validateKeyNew() error("Key endpoint must not be called") end
    function module.checkSession() error("HWID session must not be requested") end
    local player = {Name="TestPlayer", UserId=1}
    local httpService = {}
    function httpService:JSONDecode(body)
        if body == "catalog" then return {{p="10",u="20",n="Jogo de teste"}} end
        if body == "route" then return {["10"]="https://code/script"} end
        error("invalid JSON")
    end
    _G.game = {PlaceId=mode=="http_get" and 99 or 10, GameId=20}
    function game:IsLoaded() return true end
    function game:GetService(name)
        return ({Players={LocalPlayer=player},HttpService=httpService,StarterGui={SetCore=function() end}})[name]
    end
    function game:HttpGet(url)
        if url==ROOT.."catalog.json" then return "catalog" end
        if url:find("/api/roblox?gameId=99",1,true) then error("HTTP 404 (Not Found)") end
        if url:find("/api/roblox?gameId=10",1,true) then return "route" end
        if url=="https://code/script" then return "mock-payload" end
        error("Unexpected HttpGet: "..url)
    end
    local requestMock = function(options)
        assert(options.Method=="GET", "Unexpected non-lookup request")
        calls[#calls+1] = options.Url
        if options.Url:find("/api/roblox?gameId=10",1,true) then
            return {StatusCode=available and 200 or 404, Body=available and "route" or "missing"}
        end
        if options.Url=="https://code/script" then return {StatusCode=200,Body="mock-payload"} end
        error("Unexpected request: "..options.Url)
    end
    _G.request, _G.http_request, _G.fluxus = nil, nil, nil
    if mode=="fluxus" then _G.fluxus={request=requestMock}
    elseif mode=="http_request" then _G.request={}; _G.http_request=requestMock
    elseif mode~="http_get" then _G.request=requestMock end
    _G.loadstring = function(source)
        assert(source=="mock-payload")
        return function() assert(library.unloaded); calls[#calls+1]="payload-started" end
    end
    _G.task = {spawn=function(callback) callback() end}
    _G.UDim2 = {fromOffset=function(x,y) return {x,y} end}
    _G.setclipboard = function(value) clipboard=value end
    _G.getgenv = function() return _G end
    _G.warn = function() end
    local context = {rootUrl=ROOT,entryUrl=ENTRY,load=function(path)
        if path=="vendor/combowick_module.lua" then return module end
        if path=="vendor/obsidian/Library.lua" then return library end
        if path=="resolver.lua" then return Resolver end
        if path:find("Manager.lua",1,true) then return manager end
        error("Unexpected dependency: "..path)
    end}
    local result = start(context)
    assert(result.Tabs.Open and result.Tabs.Games and not result.Tabs.Key)
    assert(buttons["Abrir painel"] and buttons["Atualizar deteccao"])
    buttons["Copiar nossa versao"]()
    assert(clipboard=='loadstring(game:HttpGet("'..ENTRY..'"))()')
    local hasGold=false
    for _,call in ipairs(calls) do if call=="gold-theme" then hasGold=true end end
    assert(hasGold)
    buttons["Abrir painel"]()
    local ran=false
    for _,call in ipairs(calls) do if call=="payload-started" then ran=true end end
    assert(ran==available and library.unloaded==available)
    return true
end
assert(scenario(true))
print("OK original panel integration, gold theme, our GitHub copy and open without Key calls")
assert(scenario(false))
print("OK unavailable route leaves the panel open and does not run code")
assert(scenario(true,"http_get"))
print("OK HttpGet-only executor recognizes 404 and resolves the canonical place")
assert(scenario(true,"fluxus"))
print("OK Fluxus request compatibility")
assert(scenario(true,"http_request"))
print("OK non-function request does not mask a valid http_request function")
