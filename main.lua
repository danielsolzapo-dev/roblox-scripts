-- XERECA entry point: visible download/compile/startup diagnostics.
local build = "6909ccf724b018c8fdf52b8862d9cc9d166cf718"
local sourceUrl = "https://raw.githubusercontent.com/danielsolzapo-dev/roblox-scripts/" .. build .. "/RobloxUILibrary/Standalone.client.luau"
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
local panel, message
local function show(text)
    warn("[XERECA Loader] " .. text)
    if not playerGui then return end
    if not panel then
        local old = playerGui:FindFirstChild("_XerecaLoader")
        if old then old:Destroy() end
        panel = Instance.new("ScreenGui")
        panel.Name = "_XerecaLoader"
        panel.ResetOnSpawn = false
        panel.DisplayOrder = 1000
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0.86, 0, 0.45, 0)
        frame.Position = UDim2.fromScale(0.07, 0.2)
        frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
        frame.Parent = panel
        local close = Instance.new("TextButton")
        close.Size = UDim2.new(1, 0, 0, 32)
        close.Text = "XERECA • diagnóstico de inicialização • fechar"
        close.TextColor3 = Color3.new(1, 1, 1)
        close.BackgroundColor3 = Color3.fromRGB(65, 35, 45)
        close.Parent = frame
        close.MouseButton1Click:Connect(function()panel:Destroy();panel=nil end)
        message = Instance.new("TextBox")
        message.Position = UDim2.fromOffset(12, 40)
        message.Size = UDim2.new(1, -24, 1, -52)
        message.BackgroundTransparency = 1
        message.TextColor3 = Color3.new(1, 1, 1)
        message.TextSize = 14
        message.Font = Enum.Font.Code
        message.TextWrapped = true
        message.MultiLine = true
        message.TextEditable = false
        message.ClearTextOnFocus = false
        message.TextXAlignment = Enum.TextXAlignment.Left
        message.TextYAlignment = Enum.TextYAlignment.Top
        message.Parent = frame
        panel.Parent = playerGui
    end
    message.Text = text:sub(1, 3500)
end
if not player then
    show("Execute no cliente Roblox após entrar no jogo; LocalPlayer indisponível.")
    return
end
if not playerGui then
    playerGui = player:WaitForChild("PlayerGui", 10)
end
-- Only this loader's in-flight launch is guarded; successful hubs can be reloaded.
local state = shared._XerecaLoaderState
if type(state) == "table" and state.Busy then
    show("Uma inicialização já está em andamento. Aguarde o download atual.")
    return
end
state = {Busy=true, Build=build, Stage="download"}
shared._XerecaLoaderState = state
local function fail(stage, detail)
    state.Busy=false;state.Stage=stage;state.Error=tostring(detail)
    show("Falha na etapa: " .. stage .. "\nVersão: " .. build .. "\n\n" .. tostring(detail)
        .. "\n\nEnvie uma captura desta mensagem para identificar a causa.")
end
local ok, source = pcall(function()return game:HttpGet(sourceUrl)end)
if not ok then fail("download HTTP", source);return end
if type(source) ~= "string" or not source:find("Standalone Roblox UI Library", 1, true) then
    fail("conteúdo recebido", "O endereço não retornou o Standalone esperado.");return
end
state.Stage = "compilação"
if type(loadstring) ~= "function" then
    fail("compilação", "loadstring indisponível neste ambiente.");return
end
local compiled, chunk, compileError = pcall(loadstring, source, "XERECA_" .. build)
if not compiled or type(chunk) ~= "function" then
    fail("compilação", compiled and compileError or chunk);return
end
state.Stage = "inicialização"
local started, result = xpcall(chunk, function(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end)
if not started then fail("inicialização", result);return end
state.Busy=false;state.Stage="pronto";state.Error=nil
local old = playerGui and playerGui:FindFirstChild("_XerecaLoader")
if old then old:Destroy()end
return result
