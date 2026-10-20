-- ESP module extracted from Matsune logic (Roblox)
-- Toggles: Island, Player, Chest, DevilFruit, Flower, Apple/RealFruit
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local ESP = {
	IslandESP=false,
	PlayerESP=false,
	ChestESP=false,
	DevilFruitESP=false,
	FlowerESP=false,
	RealFruitESP=false
}
ESP.__index = ESP

local Number = tostring(math.random(1,999))

local function round(n) return math.floor(n+0.5) end

local function makeBillboard(parent, name, text, color, size)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.new(0,220,0,50)
	bb.AlwaysOnTop = true
	bb.ExtentsOffset = Vector3.new(0,3,0)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1,0,1,0)
	tl.BackgroundTransparency = 1
	tl.TextStrokeTransparency = 0.5
	tl.Font = Enum.Font.GothamBold
	tl.TextSize = 14
	tl.TextColor3 = color or Color3.fromRGB(255,255,255)
	tl.Text = text or ""
	tl.Parent = bb
	bb.Parent = parent
	return bb
end

local function cleanup(parent, name)
	if parent and parent:FindFirstChild(name) then pcall(function() parent[name]:Destroy() end) end
end

function ESP:UpdateIsland()
	for _, v in pairs(Workspace:GetChildren()) do
		if v.Name and v.Name:match("Island") or (v:FindFirstChild("Head")==nil and v.ClassName=="Part") then
			if self.IslandESP then
				if not v:FindFirstChild("NameEsp") then
					makeBillboard(v, "NameEsp", v.Name, Color3.fromRGB(255,255,255))
				end
				if v:FindFirstChild("NameEsp") then
					local d = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") and LocalPlayer.Character.Head.Position - v.Position).Magnitude or 0
					v.NameEsp.TextLabel.Text = (v.Name .. "\n" .. round(d/3) .. " Distance")
				end
			else
				cleanup(v, "NameEsp")
			end
		end
	end
end

function ESP:UpdatePlayers()
	for _, v in pairs(Players:GetPlayers()) do
		if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("Head") then
			if self.PlayerESP then
				if not v.Character.Head:FindFirstChild("NameEsp"..Number) then
					makeBillboard(v.Character.Head, "NameEsp"..Number, v.Name, Color3.fromRGB(0,255,100))
				end
				local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
				local other = v.Character.Head
				if root and other then
					local d = (root.Position - other.Position).Magnitude
					local hp = v.Character:FindFirstChild("Humanoid")
					local pct = hp and (hp.Health*100/math.max(1,hp.MaxHealth)) or 0
					v.Character.Head["NameEsp"..Number].TextLabel.Text = (v.Name .. " | " .. round(d/3) .. " Distance\nHealth: " .. round(pct) .. "%")
				end
			else
				cleanup(v.Character.Head, "NameEsp"..Number)
			end
		end
	end
end

function ESP:UpdateChest()
	for _, chest in pairs(Workspace:GetDescendants()) do
		if chest.Name and chest.Name:lower():match("chest") then
			if self.ChestESP then
				if not chest:FindFirstChild("ChestEsp") then
					makeBillboard(chest, "ChestEsp", "Chest", Color3.fromRGB(255,215,0))
				end
				if chest:FindFirstChild("ChestEsp") then
					local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
					if root then
						local d = (root.Position - chest.Position).Magnitude
						chest.ChestEsp.TextLabel.Text = ("Chest\n" .. round(d/3) .. " M")
					end
				end
			else
				cleanup(chest, "ChestEsp")
			end
		end
	end
end

function ESP:UpdateDevilFruit()
	for _, v in pairs(Workspace:GetChildren()) do
		if v.Name and v.Name:match("Fruit") then
			if self.DevilFruitESP then
				if not (v:FindFirstChild("Handle") or v.PrimaryPart) then continue end
				local attach = v:FindFirstChild("Handle") or v.PrimaryPart
				if not attach then continue end
				if not attach:FindFirstChild("NameEsp"..Number) then
					makeBillboard(attach, "NameEsp"..Number, v.Name, Color3.fromRGB(255,0,255))
				end
				if attach:FindFirstChild("NameEsp"..Number) then
					local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
					if root then
						local d = (root.Position - attach.Position).Magnitude
						attach["NameEsp"..Number].TextLabel.Text = (v.Name .. "\n" .. round(d/3) .. " Distance")
					end
				end
			else
				local attach = v:FindFirstChild("Handle") or v.PrimaryPart
				if attach then cleanup(attach, "NameEsp"..Number) end
			end
		end
	end
end

function ESP:UpdateFlower()
	for _, v in pairs(Workspace:GetChildren()) do
		if v.Name == "Flower1" or v.Name == "Flower2" then
			if self.FlowerESP then
				if not v:FindFirstChild("EspFlower"..Number) then
					makeBillboard(v, "EspFlower"..Number, (v.Name=="Flower1" and "Blue Flower" or "Red Flower"), Color3.fromRGB(100,100,255))
				end
				if v:FindFirstChild("EspFlower"..Number) then
					local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
					if root then
						local d = (root.Position - v.Position).Magnitude
						v["EspFlower"..Number].TextLabel.Text = ((v.Name=="Flower1" and "Blue Flower" or "Red Flower") .. "\n" .. round(d/3) .. " Distance")
						v["EspFlower"..Number].TextLabel.TextColor3 = (v.Name=="Flower1" and Color3.fromRGB(40,40,255) or Color3.fromRGB(255,100,100))
					end
				end
			else
				cleanup(v, "EspFlower"..Number)
			end
		end
	end
end

function ESP:UpdateRealFruit()
	local spawner = Workspace:FindFirstChild("AppleSpawner")
	if not spawner then return end
	for _, v in pairs(spawner:GetChildren()) do
		if self.RealFruitESP then
			if v.Name == "Fruit" then
				if not v:FindFirstChild("NameEsp"..Number) then
					makeBillboard(v, "NameEsp"..Number, "Apple (Real)", Color3.fromRGB(255,50,50))
				end
				if v:FindFirstChild("NameEsp"..Number) then
					local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
					if root then
						local d = (root.Position - v.Position).Magnitude
						v["NameEsp"..Number].TextLabel.Text = ("Apple (Real)" .. "\n" .. round(d/3) .. " Distance")
					end
				end
			end
		else
			cleanup(v, "NameEsp"..Number)
		end
	end
end

function ESP:StartLoop()
	if self._loop then return end
	self._loop = task.spawn(function()
		while true do
			pcall(function() self:UpdateIsland() end)
			pcall(function() self:UpdatePlayers() end)
			pcall(function() self:UpdateChest() end)
			pcall(function() self:UpdateDevilFruit() end)
			pcall(function() self:UpdateFlower() end)
			pcall(function() self:UpdateRealFruit() end)
			task.wait(1)
		end
	end)
end

function ESP:StopLoop()
	if self._loop then pcall(task.cancel, self._loop); self._loop = nil end
end

function ESP:Set(name, v)
	if self[name.."ESP"] == nil then
		-- support keys like IslandESP already present
	end
	self[name] = v
	-- map simple names
	self[name.."ESP"] = v
end

_G.MatsuneESP = ESP
ESP:StartLoop()

return ESP
