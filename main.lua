local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TesteGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 120)
frame.Position = UDim2.new(0.5, -125, 0.5, -60)
frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Teste GitHub"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(0.8, 0, 0, 40)
button.Position = UDim2.new(0.1, 0, 0.5, 0)
button.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
button.Text = "Executar"
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 16
button.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.Parent = button

button.MouseButton1Click:Connect(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/danielsolzapo-dev/teste/main/Teste"))()
end)
