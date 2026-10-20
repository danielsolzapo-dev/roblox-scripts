-- FastAttack (extracted from Matsune Blox Fruits script)
-- Server-side real fast attack: uses RE/RegisterAttack and RE/RegisterHit
-- Usage:
--   local FastAttack = require(script:FindFirstChild("FastAttack"))
--   FastAttack:Start() / FastAttack:Stop()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local Net
local function resolveNet()
	local pkg = ReplicatedStorage:FindFirstChild("Packages")
	if pkg then
		local n = pkg:FindFirstChild("Net")
		if n then return n end
	end
	local n = ReplicatedStorage:FindFirstChild("Net")
	if n then return n end
	local mods = ReplicatedStorage:FindFirstChild("Modules")
	if mods then
		local n2 = mods:FindFirstChild("Net")
		if n2 then return n2 end
	end
	return nil
end

local function SafeWaitForChild(parent, name)
	if not parent then return nil end
	for i = 1, 40 do
		local c = parent:FindFirstChild(name)
		if c then return c end
		task.wait(0.25)
	end
	return parent:FindFirstChild(name)
end

Net = resolveNet()

local Enemies = Workspace:FindFirstChild("Enemies") or Workspace:FindFirstChild("Hostiles")
local Characters = Workspace:FindFirstChild("Characters")

local Settings = {
	AutoClick = false,
	ClickDelay = 0
}

local FastAttack = {
	Distance = 100,
	attackMobs = true,
	attackPlayers = true,
	Equipped = nil,
	Running = false,
	_thread = nil
}

local RegisterAttack, RegisterHit

if Net then
	RegisterAttack = SafeWaitForChild(Net, "RE/RegisterAttack")
	RegisterHit = SafeWaitForChild(Net, "RE/RegisterHit")
end

local function IsAlive(character)
	return character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0
end

local function ProcessEnemies(OthersEnemies, Folder)
	local BasePart = nil
	if not Folder then return BasePart end
	for _, Enemy in Folder:GetChildren() do
		local Head = Enemy:FindFirstChild("Head")
		if Head and IsAlive(Enemy) and Player:DistanceFromCharacter(Head.Position) < FastAttack.Distance then
			if Enemy ~= Player.Character then
				table.insert(OthersEnemies, { Enemy, Head })
				BasePart = Head
			end
		end
	end
	return BasePart
end

function FastAttack:Attack(BasePart, OthersEnemies)
	if not BasePart or #OthersEnemies == 0 then return end
	if RegisterAttack then
		RegisterAttack:FireServer(Settings.ClickDelay or 0)
	end
	if RegisterHit then
		RegisterHit:FireServer(BasePart, OthersEnemies)
	end
end

function FastAttack:AttackNearest()
	local OthersEnemies = {}
	local Part1 = ProcessEnemies(OthersEnemies, Enemies)
	local Part2 = ProcessEnemies(OthersEnemies, Characters)

	local character = Player.Character
	if not character then return end
	local equippedWeapon = character:FindFirstChildOfClass("Tool")

	if equippedWeapon and equippedWeapon:FindFirstChild("LeftClickRemote") then
		for _, enemyData in ipairs(OthersEnemies) do
			local enemy = enemyData[1]
			local direction = (enemy.HumanoidRootPart.Position - character:GetPivot().Position).Unit
			pcall(function()
				equippedWeapon.LeftClickRemote:FireServer(direction, 1)
			end)
		end
	elseif #OthersEnemies > 0 then
		self:Attack(Part1 or Part2, OthersEnemies)
	else
		task.wait(0)
	end
end

function FastAttack:BladeHits()
	local Equipped = IsAlive(Player.Character) and Player.Character:FindFirstChildOfClass("Tool")
	if Equipped and Equipped.ToolTip ~= "Gun" then
		self:AttackNearest()
	else
		task.wait(0)
	end
end

function FastAttack:Start()
	if self.Running then return end
	self.Running = true
	Settings.AutoClick = true
	self._thread = task.spawn(function()
		while self.Running and Settings.AutoClick do
			self:BladeHits()
			task.wait(Settings.ClickDelay)
		end
	end)
end

function FastAttack:Stop()
	self.Running = false
	Settings.AutoClick = false
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
end

function FastAttack:SetDelay(v)
	Settings.ClickDelay = v or 0
end

function FastAttack:SetDistance(v)
	self.Distance = v or 100
end

_G.MatsuneFastAttack = FastAttack

return FastAttack
