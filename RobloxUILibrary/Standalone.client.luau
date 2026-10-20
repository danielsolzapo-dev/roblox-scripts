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
local function unload()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(tasksPending) do pcall(function() if typeof(t)=="thread" then task.cancel(t) end end) end
    if shared._uilibGui then pcall(function() shared._uilibGui:Destroy() end) end
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

-- state
local isUIOpen = false
local state = "normal" -- normal/min/max
local previousState = "normal"
local curTweens = {}
local function cancelTweens()
    for _,tw in ipairs(curTweens) do pcall(function() tw:Cancel() end) end
    curTweens = {}
end
local function sizeFor(s)
    local bw,bh,mw,mh = baseW, baseH, maxW, maxH
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
    isUIOpen = v
    if v then
        Main.Visible = true
        cancelTweens()
        UIScale.Scale = 0.92
        local tw = TweenService:Create(UIScale, TweenInfo.new(0.2), {Scale=1}); curTweens[#curTweens+1]=tw; tw:Play()
    else
        cancelTweens()
        local myToken = math.random(1, 1e9)
        _G._closeToken = myToken
        local tw = TweenService:Create(UIScale, TweenInfo.new(0.15), {Scale=0.92}); curTweens[#curTweens+1]=tw; tw:Play()
        local t = task.delay(0.15, function()
            if _G._closeToken == myToken then Main.Visible = false end
        end)
        trackTask(t)
    end
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
    previousState = state
    state = s
    cancelTweens()
    local tw = TweenService:Create(Main, TweenInfo.new(0.2), {Size = sizeFor(state)}); curTweens[#curTweens+1]=tw; tw:Play()
end
bind(MinBtn.MouseButton1Click, function() if state=="min" then setState(previousState or "normal") else setState("min") end end)
bind(MaxBtn.MouseButton1Click, function() setState(state=="max" and "normal" or "max") end)
bind(CloseBtn.MouseButton1Click, function() setOpen(false) end)

-- drag
local draggingHeader=false
local hdStart, hmStart
bind(Header.InputBegan, function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingHeader=true; hdStart=i.Position
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
        local d = i.Position - hdStart
        local sz = Main.AbsoluteSize
        local vp = viewport()
        -- account anchorpoint
        local ap = Main.AnchorPoint
        local left = hmStart.X + d.X - sz.X*ap.X
        local top = hmStart.Y + d.Y - sz.Y*ap.Y
        local maxX = vp.X - sz.X*(1-ap.X)
        local maxY = vp.Y - sz.Y*(1-ap.Y)
        left = math.clamp(left, -sz.X*ap.X, maxX)
        top = math.clamp(top, -sz.Y*ap.Y, maxY)
        Main.Position = UDim2.new(0, left + sz.X*ap.X, 0, top + sz.Y*ap.Y)
    end
end)
bind(UserInputService.InputEnded, function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then draggingHeader=false end
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
        if tab.Btn and not tab.Selected then tab.Btn.BackgroundColor3 = T().ComponentBg end
    end
    table.insert(updateFns, tab.RefreshTheme)
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
    local render = function(instant)
        local info = instant and TweenInfo.new(0) or TweenInfo.new(0.15)
        TweenService:Create(knob, info, {Position = val and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}):Play()
        TweenService:Create(track, info, {BackgroundColor3 = val and T().Accent or T().Surface}):Play()
    end
    local refreshTheme = function() render(true) end
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
    task.defer(function() setValue(default) end)
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

-- hotkey
bind(UserInputService.InputBegan, function(i, gameProcessed)
    if gameProcessed then return end
    if i.KeyCode == Enum.KeyCode.RightShift then toggleUI() end
end)

-- viewport resize recalc
bind(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
    baseW,baseH,maxW,maxH = computeSizes()
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
