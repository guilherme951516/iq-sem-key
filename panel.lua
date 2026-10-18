-- Interface derivada do combowick_main.lua: Obsidian, layout e modulo visual preservados.
-- A area de Key foi substituida por deteccao e abertura; nao valida nem armazena chaves.
return function(context)
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local StarterGui = game:GetService("StarterGui")
    if not game:IsLoaded() then game.Loaded:Wait() end
    local player = Players.LocalPlayer
    if not player then error("[IQ] Jogador local indisponivel.", 0) end
    if not game.PlaceId or game.PlaceId == 0 then error("[IQ] Entre em um jogo antes de abrir o painel.", 0) end

    local env = (getgenv and getgenv()) or _G
    if env.__IQ_OURS_PANEL then pcall(function() env.__IQ_OURS_PANEL:Unload() end) end
    local M = context.load("vendor/combowick_module.lua")
    assert(type(M) == "table", "[IQ] O modulo visual nao carregou neste executor.")
    M.LANG = "pt"
    M.EXIST_URL = context.rootUrl .. "IQ.lua"
    M.WEBSITE_URL = "https://github.com/guilherme951516/iq-sem-key"
    M.showKeyPrompt = function() end
    M.reloadExist = function()
        local chunk = assert(loadstring(game:HttpGet(context.rootUrl .. "IQ.lua", true)))
        return chunk()
    end

    local Library = context.load("vendor/obsidian/Library.lua")
    local ThemeManager = context.load("vendor/obsidian/addons/ThemeManager.lua")
    local SaveManager = context.load("vendor/obsidian/addons/SaveManager.lua")
    local Resolver = context.load("resolver.lua")
    local Options = Library.Options
    env.__IQ_OURS_PANEL = Library
    Library:OnUnload(function()
        if env.__IQ_OURS_PANEL == Library then env.__IQ_OURS_PANEL = nil end
    end)

    local requestFn
    if type(request) == "function" then requestFn = request
    elseif type(http_request) == "function" then requestFn = http_request
    elseif syn and type(syn.request) == "function" then requestFn = syn.request
    elseif http and type(http.request) == "function" then requestFn = http.request
    elseif fluxus and type(fluxus.request) == "function" then requestFn = fluxus.request end
    local function transport(url)
        if type(requestFn) == "function" then
            local response = requestFn({Url = url, Method = "GET"})
            return tonumber(response.StatusCode or response.status_code or response.statusCode or response.Status or response.status), response.Body or response.body
        end
        local ok, body = pcall(function() return game:HttpGet(url, true) end)
        if ok then return 200, body end
        local message = tostring(body)
        if message:find("404", 1, true) then return 404, message end
        return 0, message
    end
    local function catalog()
        if type(requestFn) == "function" and M.GAMES_RPC_URL and M.GAMES_RPC_ANON then
            local ok, value = pcall(function()
                local response = requestFn({Url = M.GAMES_RPC_URL, Method = "POST", Body = "{}",
                    Headers = {["Content-Type"] = "application/json", apikey = M.GAMES_RPC_ANON,
                        Authorization = "Bearer " .. M.GAMES_RPC_ANON}})
                assert(tonumber(response.StatusCode or response.status_code or response.statusCode or response.Status or response.status) == 200)
                return HttpService:JSONDecode(response.Body or response.body)
            end)
            if ok and type(value) == "table" then return value end
        end
        local ok, value = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(context.rootUrl .. "catalog.json", true))
        end)
        return ok and type(value) == "table" and value or {}
    end
    local resolver = Resolver.new({request = transport, decode = function(body) return HttpService:JSONDecode(body) end,
        compile = loadstring, catalog = catalog})

    local Window = Library:CreateWindow({Title = "COMBOWICK", Footer = "guilherme951516 | Sem Key",
        NotifySide = "Right", ShowCustomCursor = false, AutoShow = true, Size = UDim2.fromOffset(560, 340)})
    local Tabs = {}
    pcall(function() if M.buildHomeTab then Tabs.Info = M.buildHomeTab(Library, Window) end end)
    Tabs.Main = Window:AddTab("Inicio", "user")
    Tabs.Open = Window:AddTab("Abrir painel", "play")
    pcall(function() if M.buildGamesTab then Tabs.Games = M.buildGamesTab(Library, Window) end end)
    Tabs.Help = Window:AddTab("Ajuda", "life-buoy")
    Tabs.UI = Window:AddTab("Configuracoes", "settings")

    local function set(label, value) pcall(function() label:SetText(value) end) end
    local function notify(message)
        Library:Notify({Title = "IQ", Description = message, Time = 5})
    end
    local gameGroup = Tabs.Main:AddLeftGroupbox("Jogo atual", "info")
    local nameLabel = gameGroup:AddLabel("Detectando jogo...", true)
    local routeLabel = gameGroup:AddLabel("Lugar: " .. tostring(game.PlaceId), true)
    local statusGroup = Tabs.Main:AddRightGroupbox("Status", "shield")
    local statusLabel = statusGroup:AddLabel("Consultando disponibilidade...", true)
    local hintLabel = statusGroup:AddLabel("", true)
    local openGroup = Tabs.Open:AddLeftGroupbox("Abrir o painel do jogo", "play")
    local openStatus = openGroup:AddLabel("O detector usa o jogo em que voce esta.", true)
    local idGroup = Tabs.Open:AddRightGroupbox("Identificacao", "search")
    idGroup:AddLabel("PlaceId: " .. tostring(game.PlaceId), true)
    idGroup:AddLabel("UniverseId: " .. tostring(game.GameId), true)
    idGroup:AddButton({Text = "Copiar ID do jogo", Func = function()
        if setclipboard then setclipboard(tostring(game.PlaceId)); notify("ID copiado.") end
    end})

    local busy, selected = false, nil
    local function detect(refresh)
        set(statusLabel, "Detectando jogo...")
        local record, err = resolver:resolve(game.PlaceId, game.GameId, refresh)
        selected = record
        if record then
            set(nameLabel, record.name)
            set(statusLabel, "Painel disponivel")
            set(openStatus, "Pronto para abrir: " .. record.name)
            set(routeLabel, "Lugar detectado: " .. record.resolvedPlaceId)
            set(hintLabel, record.usedCanonicalPlace and "Detectado pelo jogo principal." or "Detectado pela partida atual.")
        else
            set(statusLabel, "Painel indisponivel nesta rota")
            set(openStatus, err.message)
            set(hintLabel, err.message)
        end
        return record, err
    end
    local function refresh()
        if busy then return end
        busy = true
        task.spawn(function()
            local ok, err = pcall(detect, true)
            busy = false
            if not ok then set(statusLabel, "Falha na deteccao"); notify(tostring(err)) end
        end)
    end
    local function open()
        if busy then notify("Aguarde a consulta atual."); return end
        busy = true
        task.spawn(function()
            local ok, err = pcall(function()
                local record, resolveError = selected, nil
                if not record then record, resolveError = detect(false) end
                if not record then notify(resolveError.message); return end
                set(statusLabel, "Carregando painel...")
                set(openStatus, "Preparando o script do jogo...")
                local chunk, prepareError = resolver:prepare(record)
                if not chunk then
                    set(statusLabel, "Nao foi possivel abrir")
                    set(openStatus, prepareError.message)
                    notify(prepareError.message)
                    return
                end
                Library:Unload()
                task.spawn(function()
                    local ran, runtimeError = pcall(chunk)
                    if not ran then
                        warn("[IQ] Erro no script do jogo: " .. tostring(runtimeError))
                        pcall(function() StarterGui:SetCore("SendNotification", {Title = "IQ",
                            Text = "O script do jogo falhou. Reabra o IQ para tentar novamente.", Duration = 8}) end)
                    end
                end)
            end)
            busy = false
            if not ok then set(statusLabel, "Falha ao carregar"); notify(tostring(err)) end
        end)
    end
    gameGroup:AddButton({Text = "Detectar novamente", Func = refresh})
    gameGroup:AddButton({Text = "Abrir painel", Func = open})
    openGroup:AddButton({Text = "Abrir painel", Func = open})
    openGroup:AddButton({Text = "Atualizar deteccao", Func = refresh})
    openGroup:AddDivider()
    openGroup:AddButton({Text = "Copiar nossa versao", Func = function()
        if setclipboard then
            setclipboard('loadstring(game:HttpGet("' .. context.rootUrl .. 'IQ.lua"))()')
            notify("Carregador copiado.")
        end
    end})

    local help = Tabs.Help:AddLeftGroupbox("Como usar", "info")
    help:AddLabel("1. Entre no jogo e aguarde a deteccao.\n2. Clique em Abrir painel.\n3. Use os controles do script carregado.", true)
    help:AddLabel("Se a rota nao publicar um script, o painel mostra a indisponibilidade.", true)
    local links = Tabs.Help:AddRightGroupbox("Nossa versao", "link")
    links:AddButton({Text = "Copiar GitHub", Func = function()
        if setclipboard then setclipboard(M.WEBSITE_URL); notify("Link copiado.") end
    end})
    links:AddButton({Text = "Detectar novamente", Func = refresh})

    local menu = Tabs.UI:AddLeftGroupbox("Menu", "wrench")
    menu:AddToggle("ShowCustomCursor", {Text = "Cursor personalizado", Default = false,
        Callback = function(value) Library.ShowCustomCursor = value end})
    menu:AddLabel("Atalho do menu"):AddKeyPicker("MenuKeybind", {Default = "RightShift", NoUI = true, Text = "Atalho do menu"})
    menu:AddButton({Text = "Fechar painel", Func = function() Library:Unload() end})
    Library.ToggleKeybind = Options.MenuKeybind
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({"MenuKeybind"})
    ThemeManager:SetFolder("IQ-NossaVersao")
    SaveManager:SetFolder("IQ-NossaVersao/config")
    SaveManager:BuildConfigSection(Tabs.UI)
    ThemeManager:ApplyToTab(Tabs.UI)
    pcall(function() if M.addGoldTheme then M.addGoldTheme(Library, Tabs.UI) end end)
    SaveManager:LoadAutoloadConfig()
    Tabs.Open:Show()
    refresh()
    return {Library = Library, Window = Window, Tabs = Tabs, Resolver = resolver}
end
