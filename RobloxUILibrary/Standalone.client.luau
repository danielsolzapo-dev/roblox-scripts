-- Standalone Roblox UI Library (XERECA HUB) - corrected
-- Pure Luau; no Markdown artifacts.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Maid / connections
local conns = {}
local tasksPending = {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns+1]=c; return c end
local function trackTask(t) tasksPending[#tasksPending+1]=t end
local destroyed = false
local cleanupFns = {}
local ownedGui
local function unload()
    if destroyed then return end
    destroyed = true
    for i = #cleanupFns, 1, -1 do pcall(cleanupFns[i]) end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(tasksPending) do pcall(function() if typeof(t)=="thread" then task.cancel(t) end end) end
    if ownedGui then pcall(function() ownedGui:Destroy() end) end
    if shared._uilibGui == ownedGui then shared._uilibGui = nil end
    if shared._UILibUnload == unload then shared._UILibUnload = nil end
end
if shared._UILibUnload then pcall(shared._UILibUnload) end
local old = PlayerGui:FindFirstChild("_UILib"); if old then old:Destroy() end

-- viewport & sizing
local function viewport() return (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920,1080) end
local vp0 = viewport()
local function computeSizes()
    local vp = viewport()
    local baseW = math.min(600, vp.X - 24)
    local baseH = math.min(450, vp.Y - 24)
    local maxW = math.min(900, vp.X - 24)
    local maxH = math.min(600, vp.Y - 24)
    return baseW, baseH, maxW, maxH
end
local baseW, baseH, maxW, maxH = computeSizes()
local HDR, SIDEBAR, BTN, CORNER = 52, 180, 36, 12
if baseW < 520 then SIDEBAR = 56 end

local THEMES = {
    Dark = {Background=Color3.fromRGB(24,26,32), Sidebar=Color3.fromRGB(30,33,40), Accent=Color3.fromRGB(99,102,241), Text=Color3.fromRGB(230,232,240), TextMuted=Color3.fromRGB(150,153,165), Border=Color3.fromRGB(46,50,60), Hover=Color3.fromRGB(40,44,52), ComponentBg=Color3.fromRGB(34,37,45), Surface=Color3.fromRGB(28,30,38)},
    Midnight = {Background=Color3.fromRGB(11,14,24), Sidebar=Color3.fromRGB(16,20,32), Accent=Color3.fromRGB(129,140,248), Text=Color3.fromRGB(230,232,240), TextMuted=Color3.fromRGB(160,163,175), Border=Color3.fromRGB(34,41,60), Hover=Color3.fromRGB(28,32,46), ComponentBg=Color3.fromRGB(22,26,38), Surface=Color3.fromRGB(18,22,32)},
    Light = {Background=Color3.fromRGB(245,246,248), Sidebar=Color3.fromRGB(236,238,242), Accent=Color3.fromRGB(79,70,229), Text=Color3.fromRGB(20,22,28), TextMuted=Color3.fromRGB(100,105,120), Border=Color3.fromRGB(210,212,220), Hover=Color3.fromRGB(225,227,232), ComponentBg=Color3.fromRGB(255,255,255), Surface=Color3.fromRGB(242,244,248)},
}
local activeTheme = "Dark"
local function T() return THEMES[activeTheme] end

local themeRegistry = {}
local themeRefreshers = {}
local function reg(obj, prop, key)
    obj[prop] = T()[key]
    table.insert(themeRegistry, {Obj=obj, Prop=prop, Key=key})
    return obj
end
local function applyTheme(updateFns)
    for i = #themeRegistry, 1, -1 do
        local e = themeRegistry[i]
        local o, prop, key = e.Obj, e.Prop, e.Key
        if not o or not o.Parent then table.remove(themeRegistry, i)
        else pcall(function() o[prop] = T()[key] end) end
    end
    for _, refresh in ipairs(themeRefreshers) do refresh() end
    if typeof(updateFns) == "table" then for _, fn in ipairs(updateFns) do pcall(fn) end end
end

local function new(cls, props, parent)
    local o = Instance.new(cls)
    local themeSet = props.Theme; props.Theme = nil
    for k,v in pairs(props) do o[k]=v end
    if themeSet then for prop,key in pairs(themeSet) do reg(o,prop,key) end end
    if parent then o.Parent = parent end
    return o
end

local uiGui = new("ScreenGui", {Name="_UILib", ResetOnSpawn=false, IgnoreGuiInset=true, ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, PlayerGui)
shared._uilibGui = uiGui
ownedGui = uiGui
bind(uiGui.Destroying, unload)
shared._UILibUnload = unload

-- state
local isUIOpen = false
local state = "normal" -- normal/min/max
local previousState = "normal"
-- Visibility and geometry own separate tweens; neither can interrupt the other.
local openTween, sizeTween
local openVersion = 0
table.insert(cleanupFns, function()
    openVersion = openVersion + 1
    if openTween then openTween:Cancel() end
    if sizeTween then sizeTween:Cancel() end
end)
local function sizeFor(s)
    baseW,baseH,maxW,maxH = computeSizes()
    if s == "min" then return UDim2.fromOffset(baseW, HDR) end
    if s == "max" then return UDim2.fromOffset(maxW, maxH) end
    return UDim2.fromOffset(baseW, baseH)
end

local UIScale = nil
local Main = nil
-- Float
local Float = new("TextButton", {Size=UDim2.fromOffset(64,64), Position=UDim2.new(0,20,0,80), AutoButtonColor=false, Text="UI", Font=Enum.Font.GothamBold, TextSize=18, Theme={BackgroundColor3="Accent", TextColor3="Text"}}, uiGui)
Instance.new("UICorner", Float).CornerRadius = UDim.new(0.5,0)
reg(new("UIStroke", {Thickness=1.5, Transparency=0.6, Theme={Color="Border"}}, Float), "Color", "Border")

Main = new("Frame", {Name="Main", AnchorPoint=Vector2.new(0.5,0.5), Size=UDim2.fromOffset(baseW,baseH), Position=UDim2.new(0.5,0,0.5,0), ClipsDescendants=true, Visible=false, Theme={BackgroundColor3="Background"}}, uiGui)
new("UICorner", {CornerRadius=UDim.new(0,CORNER)}, Main)
reg(new("UIStroke", {Thickness=1, Theme={Color="Border"}}, Main), "Color", "Border")
UIScale = new("UIScale", {Scale=0.92}, Main)

local function setOpen(v)
    if destroyed then return end
    isUIOpen = v
    openVersion = openVersion + 1
    local version = openVersion
    if openTween then openTween:Cancel() end
    if v then Main.Visible = true end
    openTween = TweenService:Create(UIScale, TweenInfo.new(v and 0.2 or 0.15),
        {Scale = v and 1 or 0.92})
    if not v then
        openTween.Completed:Once(function(playback)
            if playback == Enum.PlaybackState.Completed and not destroyed
                and openVersion == version and not isUIOpen then
                Main.Visible = false
            end
        end)
    end
    openTween:Play()
end
local function toggleUI()
    if isUIOpen then setOpen(false) else setOpen(true) end
end

-- Header
local Header = new("Frame", {Size=UDim2.new(1,0,0,HDR), Theme={BackgroundColor3="Sidebar"}}, Main)
new("UICorner", {CornerRadius=UDim.new(0,CORNER)}, Header)
new("Frame", {Size=UDim2.new(1,0,0,CORNER), Position=UDim2.new(0,0,1,-CORNER), BorderSizePixel=0, Theme={BackgroundColor3="Sidebar"}}, Header)

local Title = new("TextLabel", {Text="XERECA HUB", Size=UDim2.new(1,-200,0,30), Position=UDim2.new(0,16,0,0), Font=Enum.Font.GothamBold, TextSize=18, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="Text"}}, Header)
Title.ZIndex = 2
local Sub = new("TextLabel", {Text="Roblox UI Library", Size=UDim2.new(1,-200,0,16), Position=UDim2.new(0,16,0,30), Font=Enum.Font.Gotham, TextSize=12, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="TextMuted"}}, Header)
Sub.ZIndex = 2

local function topBtn(symbol, xOff)
    local b = new("TextButton", {Size=UDim2.fromOffset(BTN,BTN), Position=UDim2.new(1,xOff,0,8), Text=symbol, Font=Enum.Font.GothamBold, TextSize=16, AutoButtonColor=false, Active=true, Theme={TextColor3="Text", BackgroundColor3="ComponentBg"}}, Header)
    new("UICorner", {CornerRadius=UDim.new(0,6)}, b)
    b.ZIndex = 2
    bind(b.MouseEnter, function() b.BackgroundColor3 = T().Hover end)
    bind(b.MouseLeave, function() b.BackgroundColor3 = T().ComponentBg end)
    return b
end
local CloseBtn = topBtn("×", -44)
local MaxBtn = topBtn("□", -(44+36+8))
local MinBtn = topBtn("–", -(44+36+8+36+8))

new("Frame", {Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), BorderSizePixel=0, Theme={BackgroundColor3="Border"}}, Header)

-- setState with prev save
local function setState(s)
    if destroyed then return end
    if s == "min" and state ~= "min" then previousState = state end
    state = s
    if sizeTween then sizeTween:Cancel() end
    sizeTween = TweenService:Create(Main, TweenInfo.new(0.2), {Size = sizeFor(state)})
    sizeTween:Play()
end
bind(MinBtn.MouseButton1Click, function() if state=="min" then setState(previousState or "normal") else setState("min") end end)
bind(MaxBtn.MouseButton1Click, function() setState(state=="max" and "normal" or "max") end)
bind(CloseBtn.MouseButton1Click, function() setOpen(false) end)

-- drag
local draggingHeader=false
local headerTouch
local hdStart, hmStart
bind(Header.InputBegan, function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingHeader=true; hdStart=i.Position
        headerTouch = i.UserInputType==Enum.UserInputType.Touch and i or nil
        -- absolute position in pixels from current UDim2
        local pos = Main.Position
        local vp = viewport()
        local absX, absY
        if pos.X.Scale ~= 0 then absX = pos.X.Scale*vp.X + pos.X.Offset else absX = pos.X.Offset end
        if pos.Y.Scale ~= 0 then absY = pos.Y.Scale*vp.Y + pos.Y.Offset else absY = pos.Y.Offset end
        hmStart = Vector2.new(absX, absY)
    end
end)
bind(UserInputService.InputChanged, function(i)
    if draggingHeader and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        if headerTouch and i ~= headerTouch then return end
        local d = i.Position - hdStart
        local sz = Main.AbsoluteSize
        local vp = viewport()
        local ap = Main.AnchorPoint
        local x = math.clamp(hmStart.X + d.X, sz.X*ap.X, math.max(sz.X*ap.X, vp.X-sz.X*(1-ap.X)))
        local y = math.clamp(hmStart.Y + d.Y, sz.Y*ap.Y, math.max(sz.Y*ap.Y, vp.Y-sz.Y*(1-ap.Y)))
        Main.Position = UDim2.fromOffset(x, y)
    end
end)
bind(UserInputService.InputEnded, function(i)
    if (headerTouch and i == headerTouch) or (not headerTouch and i.UserInputType==Enum.UserInputType.MouseButton1) then draggingHeader=false; headerTouch=nil end
end)

-- Sidebar
local Sidebar = new("Frame", {Size=UDim2.new(0,SIDEBAR,1,-HDR), Position=UDim2.new(0,0,0,HDR), Theme={BackgroundColor3="Sidebar"}}, Main)
new("UICorner", {CornerRadius=UDim.new(0,CORNER)}, Sidebar)
new("Frame", {Size=UDim2.new(1,0,0,CORNER), Position=UDim2.new(0,0,0,0), BorderSizePixel=0, Theme={BackgroundColor3="Sidebar"}}, Sidebar)
new("Frame", {Size=UDim2.new(0,CORNER,1,0), Position=UDim2.new(1,-CORNER,0,0), BorderSizePixel=0, Theme={BackgroundColor3="Sidebar"}}, Sidebar)
local SidebarList = new("ScrollingFrame", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, ScrollBarThickness=4, BorderSizePixel=0, AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0)}, Sidebar)
new("UIListLayout", {Padding=UDim.new(0,4), SortOrder=Enum.SortOrder.LayoutOrder}, SidebarList)
new("UIPadding", {PaddingTop=UDim.new(0,8), PaddingBottom=UDim.new(0,8), PaddingLeft=UDim.new(0,6), PaddingRight=UDim.new(0,6)}, SidebarList)

new("Frame", {Size=UDim2.new(0,1,1,-HDR), Position=UDim2.new(0,SIDEBAR,0,HDR), BorderSizePixel=0, Theme={BackgroundColor3="Border"}}, Main)
local Content = new("Frame", {Size=UDim2.new(1,-SIDEBAR,1,-HDR), Position=UDim2.new(0,SIDEBAR,0,HDR), ClipsDescendants=true, BackgroundTransparency=1}, Main)
local Pages = new("Frame", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1}, Content)

-- forward decl
local refreshNamed
local tabs = {}
local function addTab(name)
    local btn = new("TextButton", {Size=UDim2.new(1,0,0,36), Text=name, Font=Enum.Font.Gotham, TextSize=14, AutoButtonColor=false, Active=true, Theme={TextColor3="TextMuted", BackgroundColor3="ComponentBg"}}, SidebarList)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    new("UIPadding", {PaddingLeft=UDim.new(0,12)}, btn)
    if SIDEBAR <= 56 then btn.Text = string.sub(name,1,1); btn.TextXAlignment = Enum.TextXAlignment.Center end
    local indicator = new("Frame", {Size=UDim2.new(0,3,1,-8), Position=UDim2.new(0,0,0,4), BackgroundTransparency=1, Theme={BackgroundColor3="Accent"}}, btn)
    local page = new("ScrollingFrame", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, ScrollBarThickness=4, BorderSizePixel=0, AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0), Visible=false}, Pages)
    page.ScrollingEnabled = true
    new("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, page)
    new("UIPadding", {PaddingTop=UDim.new(0,12), PaddingBottom=UDim.new(0,12), PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,12)}, page)
    local tab = {Name=name, Btn=btn, Page=page, Indicator=indicator, Selected=false}
    local updateFns = {}
    tab.RefreshTheme = function()
        if tab.Indicator then tab.Indicator.BackgroundTransparency = tab.Selected and 0 or 1 end
        if tab.Btn then tab.Btn.TextColor3 = tab.Selected and T().Text or T().TextMuted end
        if tab.Btn then tab.Btn.BackgroundColor3 = tab.Selected and T().Hover or T().ComponentBg end
    end
    table.insert(themeRefreshers, function() if btn.Parent then tab.RefreshTheme() end end)
    bind(btn.MouseButton1Click, function()
        for _, t in ipairs(tabs) do
            t.Page.Visible = false
            t.Selected = false
            t.Btn.BackgroundColor3 = T().ComponentBg
            refreshNamed(t)
        end
        tab.Page.Visible = true
        tab.Selected = true
        tab.Btn.BackgroundColor3 = T().Hover
        tab.Btn.TextColor3 = T().Text
        tab.Indicator.BackgroundTransparency = 0
    end)
    bind(btn.MouseEnter, function() if not tab.Selected then tab.Btn.BackgroundColor3 = T().Hover end end)
    bind(btn.MouseLeave, function() if not tab.Selected then tab.Btn.BackgroundColor3 = T().ComponentBg end end)
    table.insert(tabs, tab)
    return page
end

refreshNamed = function(t)
    if t and t.RefreshTheme then t.RefreshTheme() end
end

local Home = addTab("Home")
local PlayerT = addTab("Player")
local Visual = addTab("Visual")
local Settings = addTab("Settings")
local Farm = addTab("Farm")
local ESPtab = addTab("ESP")
local Fruit = addTab("Fruit")

for i,t in ipairs(tabs) do
    t.Page.Visible = (i==1); t.Selected = (i==1)
    t.Btn.BackgroundColor3 = (i==1) and T().Hover or T().ComponentBg
    t.Btn.TextColor3 = (i==1) and T().Text or T().TextMuted
    t.Indicator.BackgroundTransparency = (i==1) and 0 or 1
end

-- Notifications
local NotifContainer = new("Frame", {Size=UDim2.new(0,320,1,0), Position=UDim2.new(1,-332,0,12), BackgroundTransparency=1}, uiGui)
new("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder, HorizontalAlignment=Enum.HorizontalAlignment.Right}, NotifContainer)
local function notify(opts)
    opts = opts or {}
    local wrapper = new("Frame", {Size=UDim2.new(1,0,0,64), BackgroundTransparency=1}, NotifContainer)
    local card = new("Frame", {Size=UDim2.new(1,0,1,0), Position=UDim2.new(1,12,0,0), Theme={BackgroundColor3="ComponentBg"}}, wrapper)
    new("UICorner", {CornerRadius=UDim.new(0,8)}, card)
    reg(new("UIStroke", {Thickness=1, Theme={Color="Border"}}, card), "Color","Border")
    new("TextLabel", {Text=opts.Title or "Info", Size=UDim2.new(1,-16,0,20), Position=UDim2.new(0,8,0,6), Font=Enum.Font.GothamBold, TextSize=13, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="Text"}}, card)
    new("TextLabel", {Text=opts.Text or "", Size=UDim2.new(1,-16,0,30), Position=UDim2.new(0,8,0,26), Font=Enum.Font.Gotham, TextSize=12, BackgroundTransparency=1, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="TextMuted"}}, card)
    local prog = new("Frame", {Size=UDim2.new(1,0,0,2), Position=UDim2.new(0,0,1,-2), Theme={BackgroundColor3="Accent"}}, card)
    TweenService:Create(card, TweenInfo.new(0.4), {Position=UDim2.new(0,0,0,0)}):Play()
    local dur = opts.Duration or 3
    local progTween = TweenService:Create(prog, TweenInfo.new(dur, Enum.EasingStyle.Linear), {Size=UDim2.new(0,0,0,2)})
    progTween:Play()
    local t = task.delay(dur, function()
        TweenService:Create(card, TweenInfo.new(0.4), {Position=UDim2.new(1,12,0,0)}):Play()
        local t2 = task.delay(0.45, function() if wrapper and wrapper.Parent then wrapper:Destroy() end end)
        trackTask(t2)
    end)
    trackTask(t)
end

-- Float drag with viewport clamp + touch id
local fd, fmoved = false, false
local fs, fstart = nil, nil
local touchId = nil
bind(Float.InputBegan, function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        fd=true; fmoved=false; fs=i.Position; fstart=Float.Position
        if i.UserInputType==Enum.UserInputType.Touch then touchId=i end
    end
end)
bind(UserInputService.InputChanged, function(i)
    if fd and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        if touchId and i ~= touchId then return end
        local d = i.Position - fs
        if d.Magnitude > 4 then fmoved=true end
        local vp = viewport()
        local nx = fstart.X.Offset + d.X
        local ny = fstart.Y.Offset + d.Y
        nx = math.clamp(nx, 0, vp.X - 64)
        ny = math.clamp(ny, 0, vp.Y - 64)
        Float.Position = UDim2.new(0, nx, 0, ny)
    end
end)
bind(UserInputService.InputEnded, function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        fd=false
        if touchId==i then touchId=nil end
    end
end)
bind(Float.MouseButton1Click, function()
    if fmoved then return end
    toggleUI()
end)
bind(Float.MouseEnter, function() Float.BackgroundColor3 = Color3.new(math.min(1,T().Accent.R*1.2), math.min(1,T().Accent.G*1.2), math.min(1,T().Accent.B*1.2)) end)
bind(Float.MouseLeave, function() Float.BackgroundColor3 = T().Accent end)

-- Components
local function addBtn(parent, text, cb)
    local b = new("TextButton", {Size=UDim2.new(1,-24,0,36), Text=text, Font=Enum.Font.Gotham, TextSize=14, AutoButtonColor=false, Active=true, Theme={TextColor3="Text", BackgroundColor3="ComponentBg"}}, parent)
    new("UICorner", {CornerRadius=UDim.new(0,6)}, b)
    bind(b.MouseEnter, function() b.BackgroundColor3 = T().Hover end)
    bind(b.MouseLeave, function() b.BackgroundColor3 = T().ComponentBg end)
    bind(b.MouseButton1Click, function() if cb then cb() end end)
    return b
end

local function addToggle(parent, label, default, cb)
    local f = new("Frame", {Size=UDim2.new(1,-24,0,36), Theme={BackgroundColor3="ComponentBg"}}, parent)
    new("UICorner", {CornerRadius=UDim.new(0,6)}, f)
    local lbl = new("TextLabel", {Text=label, Size=UDim2.new(1,-60,1,0), Position=UDim2.new(0,12,0,0), Font=Enum.Font.Gotham, TextSize=14, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="Text"}}, f)
    local track = new("Frame", {Size=UDim2.fromOffset(40,20), Position=UDim2.new(1,-52,0.5,-10), Theme={BackgroundColor3="Surface"}}, f)
    new("UICorner", {CornerRadius=UDim.new(1,0)}, track)
    local knob = new("Frame", {Size=UDim2.fromOffset(16,16), Position=UDim2.new(0,2,0.5,-8), BackgroundColor3=Color3.new(1,1,1)}, track)
    new("UICorner", {CornerRadius=UDim.new(1,0)}, knob)
    local val = (default==true)
    local knobTween, trackTween
    local render = function(instant)
        if knobTween then knobTween:Cancel() end
        if trackTween then trackTween:Cancel() end
        local info = instant and TweenInfo.new(0) or TweenInfo.new(0.15)
        knobTween = TweenService:Create(knob, info, {Position = val and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)})
        trackTween = TweenService:Create(track, info, {BackgroundColor3 = val and T().Accent or T().Surface})
        knobTween:Play()
        trackTween:Play()
    end
    local refreshTheme = function() if f.Parent then render(true) end end
    table.insert(themeRefreshers, refreshTheme)
    table.insert(cleanupFns, function()
        if knobTween then knobTween:Cancel() end
        if trackTween then trackTween:Cancel() end
    end)
    render(true)
    local function toggle() val = not val; render(false); if cb then cb(val) end end
    local btnArea = new("TextButton", {Size=UDim2.fromOffset(44,24), Position=UDim2.new(1,-54,0.5,-12), BackgroundTransparency=1, Text=""}, f)
    bind(btnArea.MouseButton1Click, toggle)
    local api = {Frame=f, Value=val, Get=function() return val end, Set=function(v) val=(v==true); render(false); if cb then cb(val) end end, SetText=function(t) lbl.Text=t end, RefreshTheme=refreshTheme, Destroy=function() f:Destroy() end}
    return api
end

local function addSlider(parent, opts)
    opts = opts or {}
    local min = opts.Min or 0
    local max = opts.Max or 1
    if not (max > min) then max = min + 1 end
    local step = opts.Step or 0.01
    if step <= 0 then step = 0.01 end
    local default = opts.Default or min
    if default < min then default = min end
    if default > max then default = max end
    local suffix = opts.Suffix or ""
    local cb = opts.Callback
    local name = opts.Name or "Slider"
    local f = new("Frame", {Size=UDim2.new(1,-24,0,56), Theme={BackgroundColor3="ComponentBg"}}, parent)
    new("UICorner", {CornerRadius=UDim.new(0,6)}, f)
    local titleLbl = new("TextLabel", {Text=name, Size=UDim2.new(1,-70,0,20), Position=UDim2.new(0,12,0,4), Font=Enum.Font.Gotham, TextSize=13, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Theme={TextColor3="Text"}}, f)
    local valLabel = new("TextLabel", {Size=UDim2.new(0,60,0,20), Position=UDim2.new(1,-72,0,4), Font=Enum.Font.Gotham, TextSize=13, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Right, Theme={TextColor3="TextMuted"}}, f)
    local hit = new("Frame", {Size=UDim2.new(1,-24,0,28), Position=UDim2.new(0,12,0,24), BackgroundTransparency=1, Active=true}, f)
    local bar = new("Frame", {Size=UDim2.new(1,0,0,8), Position=UDim2.new(0,0,0.5,-4), Theme={BackgroundColor3="Surface"}}, hit)
    new("UICorner", {CornerRadius=UDim.new(1,0)}, bar)
    local fill = new("Frame", {Size=UDim2.new(0,0,1,0), Theme={BackgroundColor3="Accent"}}, bar)
    new("UICorner", {CornerRadius=UDim.new(1,0)}, fill)
    local knob = new("Frame", {Size=UDim2.fromOffset(16,16), AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0,0,0.5,0), BackgroundColor3=Color3.new(1,1,1)}, bar)
    new("UICorner", {CornerRadius=UDim.new(1,0)}, knob)

    local value = default
    local function snap(v)
        local steps = (v - min) / step
        local snapped = math.floor(steps + 0.5) * step + min
        return math.clamp(snapped, min, max)
    end
    local function render()
        local p = (value - min)/(max - min)
        fill.Size = UDim2.new(p,0,1,0)
        knob.Position = UDim2.new(p,0,0.5,0)
        valLabel.Text = tostring(value) .. suffix
    end
    local function setValue(v)
        value = snap(v)
        render()
        if cb then cb(value) end
    end
    local function setFromX(x)
        local sizeX = bar.AbsoluteSize.X
        local absX = bar.AbsolutePosition.X
        if sizeX <= 0 then return end
        local frac = (x - absX)/sizeX
        frac = math.clamp(frac,0,1)
        setValue(min + (max-min)*frac)
    end
    local dragging = false
    bind(hit.InputBegan, function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging = true
            setFromX(i.Position.X)
        end
    end)
    bind(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end)
    bind(UserInputService.InputEnded, function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    trackTask(task.defer(function() if not destroyed and f.Parent then setValue(default) end end))
    local api = {Frame=f, Get=function() return value end, Set=setValue, SetValue=setValue, SetText=function(t) titleLbl.Text=t end, Destroy=function() f:Destroy() end}
    return api
end

-- Simple
local function addLabel(parent, text)
    return new("TextLabel", {Size=UDim2.new(1,-24,0,0), AutomaticSize=Enum.AutomaticSize.Y, Text=text, Font=Enum.Font.Gotham, TextSize=13, BackgroundTransparency=1, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="Text"}}, parent)
end
local function addSection(parent, title, collapsible)
    local f = new("Frame", {Size=UDim2.new(1,-24,0,28), BackgroundTransparency=1}, parent)
    new("TextLabel", {Text=title:upper(), Size=UDim2.new(1,0,0,16), Font=Enum.Font.GothamBold, TextSize=11, BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="TextMuted"}}, f)
    new("Frame", {Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,0,20), Theme={BackgroundColor3="Border"}}, f)
    return f
end
local function addTextbox(parent, opts)
    opts = opts or {}
    local f = new("Frame", {Size=UDim2.new(1,-24,0,36), Theme={BackgroundColor3="ComponentBg"}}, parent)
    new("UICorner", {CornerRadius=UDim.new(0,6)}, f)
    local box = new("TextBox", {Size=UDim2.new(1,-16,1,0), Position=UDim2.new(0,8,0,0), BackgroundTransparency=1, PlaceholderText=opts.Placeholder or "Type...", Text="", Font=Enum.Font.Gotham, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, Theme={TextColor3="Text", PlaceholderColor3="TextMuted"}}, f)
    local cb = opts.Callback
    bind(box.FocusLost, function(enter) if enter and cb then cb(box.Text) end end)
    return {Frame=f, Get=function() return box.Text end, Set=function(t) box.Text=t end, Destroy=function() f:Destroy() end}
end

-- Home kept simple; demos moved to Settings
-- Examples
addBtn(Settings, "Theme: Midnight", function() activeTheme="Midnight"; applyTheme({}); Float.BackgroundColor3=T().Accent end)
addBtn(Settings, "Theme: Dark", function() activeTheme="Dark"; applyTheme({}); Float.BackgroundColor3=T().Accent end)
addBtn(Settings, "Theme: Light", function() activeTheme="Light"; applyTheme({}); Float.BackgroundColor3=T().Accent end)

local demoToggle = addToggle(Settings, "Ativar toggle", false, function(v) print("Toggle:", v) end)
addSlider(Settings, {Name="Velocidade", Min=0, Max=100, Default=50, Step=1, Callback=function(v) print("Slider:", v) end})
-- DEMO ONLY: does not change Humanoid
addSlider(PlayerT, {Name="Velocidade Jogador (DEMO, não altera Humanoid)", Min=16, Max=100, Default=16, Step=1, Callback=function(v) print("Velocidade (demo):", v) end})
addTextbox(Settings, {Placeholder="Nome...", Callback=function(t) print("Textbox:", t) end})
addSection(Settings, "Exemplos")
addLabel(Settings, "Numericos e componentes de exemplo abaixo.")
addBtn(Settings, "Mostrar notificação", function()
    notify({Title="Carregado!", Text="Interface carregada com sucesso.", Duration=3, Type="info"})
end)


-- Visual/Settings informational tabs
addLabel(Visual, "Aba Visual: demonstração/informativa. Componentes de visual ainda não implementados.")
addLabel(Settings, "Aba Settings: demonstração/informativa. Configurações persistentes não implementadas.")


-- === Inlined FastAttack module (Matsune) ===
local function initFastAttack()
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

-- (inlined)

return FastAttack
end
local fastAttackApi = initFastAttack()
_G.MatsuneFastAttack = fastAttackApi
table.insert(cleanupFns, function() fastAttackApi:Stop() end)

-- === Inlined ESP module (Matsune) ===
local function initESP()
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
end
local ownedESP = initESP()
_G.MatsuneESP = ownedESP
table.insert(cleanupFns, function()
    ownedESP:StopLoop()
    for _, key in ipairs({"Island", "Player", "Chest", "DevilFruit", "Flower", "RealFruit"}) do
        ownedESP:Set(key, false)
    end
    for _, method in ipairs({"UpdateIsland", "UpdatePlayers", "UpdateChest", "UpdateDevilFruit", "UpdateFlower", "UpdateRealFruit"}) do
        pcall(function() ownedESP[method](ownedESP) end)
    end
end)


-- Farm tab
addSection(Farm, "Farm")
local fastToggle = addToggle(Farm, "Fast Attack (Matsune, server hits)", false, function(v)
    if v then
        if _G.MatsuneFastAttack and _G.MatsuneFastAttack.Start then
            _G.MatsuneFastAttack:Start()
        end
    else
        if _G.MatsuneFastAttack and _G.MatsuneFastAttack.Stop then
            _G.MatsuneFastAttack:Stop()
        end
    end
end)

-- ESP tab
addSection(ESPtab, "ESP")
local espApi = _G.MatsuneESP
local function mkEspToggle(label, key)
    return addToggle(ESPtab, label, false, function(v)
        if espApi and espApi.Set then espApi:Set(key, v) end
    end)
end
mkEspToggle("Island ESP", "Island")
mkEspToggle("Player ESP", "Player")
mkEspToggle("Chest ESP", "Chest")
mkEspToggle("Devil Fruit ESP", "DevilFruit")
mkEspToggle("Flower ESP", "Flower")
mkEspToggle("Real Fruit (Apple) ESP", "RealFruit")

-- Fruit requests have one shared gate, including across UI reloads.
-- 120 seconds is a conservative client spacing, NOT a server cooldown.
-- No server response schema is available: all responses remain diagnostics.
local FRUIT_SPACING = 120
local fruitGate = shared._UILibFruitGate
if type(fruitGate) ~= "table" then
    fruitGate = {busy = nil, nextAllowed = 0}
    shared._UILibFruitGate = fruitGate
end
local fruitEnabled = false
local fruitSession = 0
local fruitTimer
local fruitWake
local armFruit

local function cancelFruitTimer()
    if fruitTimer then pcall(task.cancel, fruitTimer); fruitTimer = nil end
end

local function requestFruit(manual)
    if destroyed then return end
    if fruitGate.busy or os.clock() < fruitGate.nextAllowed then
        if manual then
            notify({Title="Fruit", Text="Solicitação pendente ou intervalo local de segurança ativo."})
        end
        return
    end
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        if manual then notify({Title="Fruit", Text="RemoteFunction Remotes.CommF_ indisponível."}) end
        warn("[Fruit] RemoteFunction ReplicatedStorage.Remotes.CommF_ indisponível.")
        fruitGate.nextAllowed = os.clock() + FRUIT_SPACING
        return
    end
    local owner = {}
    fruitGate.busy = owner
    fruitGate.nextAllowed = os.clock() + FRUIT_SPACING
    -- Intentionally not in tasksPending: canceling a yielding InvokeServer cannot
    -- cancel the server operation. Keep the gate until the call actually returns.
    task.defer(function()
        local ok, response = pcall(function()
            return remote:InvokeServer("Cousin", "Buy")
        end)
        if fruitGate.busy == owner then fruitGate.busy = nil end
        warn("[Fruit] Diagnóstico (pcall=" .. tostring(ok) .. ", tipo="
            .. typeof(response) .. "): " .. tostring(response))
        -- Resume scheduling before optional UI diagnostics.
        local wake = fruitGate.wake
        if wake then wake() end
        if not destroyed then
            notify({Title="Fruit", Text=ok
                and "Resposta recebida; compra não confirmada. Veja o diagnóstico no Output."
                or "Falha na solicitação. Veja o diagnóstico no Output."})
        end
    end)
end

armFruit = function(session)
    if destroyed or not fruitEnabled or fruitSession ~= session or fruitTimer then return end
    -- No polling while waiting for a request; completion wakes the active session.
    if fruitGate.busy then return end
    fruitTimer = task.delay(math.max(0, fruitGate.nextAllowed - os.clock()), function()
        if destroyed or not fruitEnabled or fruitSession ~= session then return end
        fruitTimer = nil
        requestFruit(false)
        armFruit(session)
    end)
end

local function setFruitEnabled(enabled)
    fruitSession = fruitSession + 1
    fruitEnabled = enabled == true
    cancelFruitTimer()
    if fruitGate.wake == fruitWake then fruitGate.wake = nil end
    local session = fruitSession
    fruitWake = function()
        if not destroyed and fruitEnabled and fruitSession == session then armFruit(session) end
    end
    if fruitEnabled then
        fruitGate.wake = fruitWake
        armFruit(session)
    end
end
table.insert(cleanupFns, function()
    setFruitEnabled(false)
end)

addSection(Fruit, "Fruit")
addLabel(Fruit, "Auto: intervalo local de 120 s, sem cooldown do servidor confirmado. Respostas são diagnósticos; o servidor decide a compra.")
addBtn(Fruit, "Random Fruit", function() requestFruit(true) end)
addToggle(Fruit, "Auto Random Fruit", false, setFruitEnabled)

-- hotkey
bind(UserInputService.InputBegan, function(i, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then return end
    if i.KeyCode == Enum.KeyCode.RightShift then toggleUI() end
end)

-- viewport resize recalc
bind(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
    setState(state)
end)

local UILib = {
    Destroy = function() unload() end,
    SetTheme = function(name) if THEMES[name] then activeTheme=name; applyTheme({}); Float.BackgroundColor3=T().Accent end end,
    Notify = notify,
    Toggle = toggleUI,
}
_G.XerecaUILib = UILib
shared._UILibUnload = unload

print("[UILib] XERECA HUB loaded successfully.")
