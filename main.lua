local RepoURL = getgenv().Dragonsz_Repo or "https://raw.githubusercontent.com/MvPx7/Dragonsz/main/"

local function LoadModule(path)
    local url = RepoURL .. path
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if not success then
        warn("[Dragonsz] Falha ao carregar o módulo: " .. path)
        warn("Erro: " .. tostring(result))
    end
    return result
end

local Modules = {
    Fly = LoadModule("modules/fly.lua"),
    Highlight = LoadModule("modules/highlight.lua"),
    Noclip = LoadModule("modules/noclip.lua"),
    Autofarm = LoadModule("modules/autofarm.lua"),
    Void = LoadModule("modules/void.lua"),
    Esp = LoadModule("modules/esp.lua"),
    Teleport = LoadModule("modules/teleport.lua")
}

local initUI = LoadModule("ui/ui.lua")
if initUI then
    initUI(Modules)
else
    warn("[Dragonsz] Falha ao inicializar a UI.")
end
