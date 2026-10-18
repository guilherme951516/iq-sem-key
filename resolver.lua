-- IQ: resolver de rotas publicas. Nao chama o endpoint de validacao de Key.
local Resolver = {}
Resolver.__index = Resolver

local function failure(code, message)
    return { code = code, message = message }
end

local function validUrl(value)
    return type(value) == "string" and value:match("^https://[^%s]+$") ~= nil
end

local function selectUrl(data, id)
    if type(data) ~= "table" then return nil end
    local value = data[tostring(id)]
    if type(value) == "table" then value = value[1] or value.url end
    if validUrl(value) then return value end
    return nil
end

local function wrapperTarget(source)
    if not source:find("KeylessTinyGui", 1, true) then return nil end
    if not source:find("keylessScript", 1, true) then return nil end
    return source:match([=[loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*["']([^"']+)["']]=])
end

function Resolver.new(options)
    assert(type(options.request) == "function", "request ausente")
    assert(type(options.decode) == "function", "decode ausente")
    return setmetatable({
        request = options.request,
        decode = options.decode,
        compile = options.compile or loadstring,
        catalog = options.catalog or {},
        endpoint = options.endpoint or "https://combo0-chroncile.vercel.app/api/roblox?gameId=",
        cache = {},
    }, Resolver)
end

function Resolver:_catalog()
    if type(self.catalog) == "function" then
        local ok, value = pcall(self.catalog)
        if ok and type(value) == "table" then self.catalog = value end
    end
    return type(self.catalog) == "table" and self.catalog or {}
end

function Resolver:_get(url)
    local ok, status, body = pcall(self.request, url)
    if not ok then return nil, failure("network", "Falha na conexao: " .. tostring(status)) end
    if type(body) ~= "string" then
        return nil, failure("invalid_response", "A resposta recebida nao contem texto.")
    end
    if status == 404 then return nil, failure("not_found", "Nenhum script publicado para este lugar.") end
    if status ~= 200 then
        return nil, failure("http_error", "O servidor respondeu HTTP " .. tostring(status) .. ".")
    end
    return body
end

function Resolver:resolve(placeId, universeId, refresh)
    placeId, universeId = tostring(placeId), tostring(universeId)
    local cacheKey = placeId .. ":" .. universeId
    if refresh then self.cache[cacheKey] = nil end
    if self.cache[cacheKey] then return self.cache[cacheKey] end

    local candidates, known, gameName = {placeId}, {[placeId] = true}, nil
    for _, game in ipairs(self:_catalog()) do
        if tostring(game.p) == placeId or tostring(game.u) == universeId then
            gameName = game.n
            local canonical = tostring(game.p)
            if not known[canonical] then
                candidates[#candidates + 1], known[canonical] = canonical, true
            end
        end
    end

    local lastError
    for _, candidate in ipairs(candidates) do
        local body, err = self:_get(self.endpoint .. candidate)
        if body then
            local ok, data = pcall(self.decode, body)
            if not ok or type(data) ~= "table" then
                lastError = failure("invalid_json", "A lista de scripts retornou JSON invalido.")
            else
                local url = selectUrl(data, candidate)
                if url then
                    local record = {url = url, placeId = placeId, resolvedPlaceId = candidate,
                        universeId = universeId, name = gameName or ("Jogo " .. placeId),
                        usedCanonicalPlace = candidate ~= placeId}
                    self.cache[cacheKey] = record
                    return record
                end
                lastError = failure("not_found", "A rota nao publicou um script para este jogo.")
            end
        else
            lastError = err
            if err.code ~= "not_found" then break end
        end
    end
    return nil, lastError or failure("not_found", "Nenhuma rota encontrada.")
end

function Resolver:prepare(record)
    if type(self.compile) ~= "function" then
        return nil, failure("no_compiler", "O executor nao oferece loadstring.")
    end
    if type(record) ~= "table" or not validUrl(record.url) then
        return nil, failure("invalid_url", "O script nao possui uma URL HTTPS valida.")
    end
    local url, seen, source = record.url, {}, nil
    local chain = {}
    for _ = 1, 4 do
        if seen[url] then return nil, failure("loop", "O carregador retornou para a mesma URL.") end
        seen[url], chain[#chain + 1] = true, url
        local body, err = self:_get(url)
        if not body then return nil, err end
        if body == "" then return nil, failure("empty_source", "O arquivo do script esta vazio.") end
        local target = wrapperTarget(body)
        if target then
            if not validUrl(target) then return nil, failure("invalid_url", "O atalho publicou uma URL invalida.") end
            url = target
        else
            source = body
            break
        end
    end
    if not source then return nil, failure("wrapper_limit", "O limite de atalhos do carregador foi atingido.") end
    if source:find("M.validateKeyNew", 1, true) then
        return nil, failure("auth_loader", "Esta rota retornou novamente o formulario de Key.")
    end
    local ok, chunk, compileError = pcall(self.compile, source, "@IQ/" .. record.resolvedPlaceId)
    if not ok or type(chunk) ~= "function" then
        return nil, failure("compile_error", "Nao foi possivel compilar o script: " .. tostring(compileError or chunk))
    end
    return chunk, nil, {url = url, chain = chain, sourceBytes = #source}
end

Resolver.selectUrl = selectUrl
return Resolver
