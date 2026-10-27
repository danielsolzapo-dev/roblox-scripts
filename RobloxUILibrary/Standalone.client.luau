-- Standalone Roblox UI Library (XERECA HUB) - corrected
-- Pure Luau; no Markdown artifacts.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Optional diagnostics. No polling, external requests or global error hooks.
local DEBUG_DEFAULT = false
local debugEnabled = DEBUG_DEFAULT
local debugControl, debugPanelControl, debugVisibility
local debugHistory = {}
local DEBUG_LIMIT = 100
local function debugLog(level, event, detail)
    if not debugEnabled then return end
    local entry = {Time=os.clock(), Level=level, Event=event, Detail=tostring(detail or "")}
    if #debugHistory >= DEBUG_LIMIT then table.remove(debugHistory, 1) end
    debugHistory[#debugHistory + 1] = entry
    local message = "[UILib DEBUG][" .. level .. "][" .. event .. "] " .. entry.Detail
    if level == "ERROR" or level == "WARN" then warn(message) else print(message) end
end
local function setDebug(enabled)
    local nextValue=enabled==true
    local previous=debugEnabled
    if previous and not nextValue then debugLog("INFO","debug","disabled") end
    debugEnabled=nextValue
    if not previous and nextValue then debugLog("INFO","debug","enabled") end
    if debugControl and debugControl.Get()~=nextValue then debugControl.Set(nextValue) end
    if debugPanelControl and debugPanelControl.Get()~=nextValue then debugPanelControl.Set(nextValue) end
    if debugVisibility then debugVisibility(nextValue) end
    return nextValue
end

-- Maid / connections
local conns = {}
local tasksPending = {}
local function bind(sig, fn, label)
    local c = sig:Connect(function(...)
        local args = table.pack(...)
        local ok, failure = xpcall(function()
            fn(table.unpack(args, 1, args.n))
        end, function(err) return debug.traceback(tostring(err), 2) end)
        if not ok then
            debugLog("ERROR", label or "callback", failure)
            -- Preserve the original error in Output even when diagnostics are off.
            error(failure, 0)
        end
    end)
    conns[#conns + 1] = c
    return c
end
local function trackTask(t)
    for pending in pairs(tasksPending) do if coroutine.status(pending)=="dead" then tasksPending[pending]=nil end end
    tasksPending[t]=true
end
local destroyed = false
local cleanupFns = {}
local ownedGui
local function unload()
    if destroyed then return end
    debugLog("INFO", "unload", "cleaning up owned resources")
    destroyed = true
    for i = #cleanupFns, 1, -1 do pcall(cleanupFns[i]) end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for t in pairs(tasksPending) do pcall(function() if typeof(t)=="thread" then task.cancel(t) end end) end
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
    local baseW = math.max(1, math.min(600, vp.X - 24))
    local baseH = math.max(52, math.min(450, vp.Y - 24))
    local maxW = math.max(1, math.min(900, vp.X - 24))
    local maxH = math.max(52, math.min(600, vp.Y - 24))
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

local cancelDrag
local function setOpen(v)
    if destroyed then return end
    if cancelDrag then cancelDrag() end
    debugLog("INFO", "visibility", tostring(isUIOpen) .. " -> " .. tostring(v))
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
                debugLog("INFO", "visibility.completed", "hidden")
            end
        end)
    end
    openTween:Play()
end
local function toggleUI()
    if isUIOpen then setOpen(false) else setOpen(true) end
end

-- Header
local Header = new("Frame", {Active=true, Size=UDim2.new(1,0,0,HDR), Theme={BackgroundColor3="Sidebar"}}, Main)
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

-- Clamp against the target geometry, not the size of an interrupted tween.
local function clampMain(size)
    local vp = viewport()
    local pos = Main.Position
    local w, h = size.X.Offset, size.Y.Offset
    local x = pos.X.Scale * vp.X + pos.X.Offset
    local y = pos.Y.Scale * vp.Y + pos.Y.Offset
    Main.Position = UDim2.fromOffset(
        math.clamp(x, w / 2, math.max(w / 2, vp.X - w / 2)),
        math.clamp(y, h / 2, math.max(h / 2, vp.Y - h / 2)))
end

-- setState with prev save
local function setState(s)
    if destroyed then return end
    if cancelDrag then cancelDrag() end
    if s == "min" and state ~= "min" then previousState = state end
    debugLog("INFO", "window.state", state .. " -> " .. tostring(s))
    state = s
    if sizeTween then sizeTween:Cancel() end
    local target = sizeFor(state)
    clampMain(target)
    sizeTween = TweenService:Create(Main, TweenInfo.new(0.2), {Size = target})
    local expectedState = state
    sizeTween.Completed:Once(function(playback)
        if destroyed or playback ~= Enum.PlaybackState.Completed or state ~= expectedState then return end
        debugLog("INFO", "window.geometry", "state=" .. state .. " size=" .. tostring(Main.Size)
            .. " absolute=" .. tostring(Main.AbsoluteSize) .. " position=" .. tostring(Main.Position))
    end)
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
        if draggingHeader or not isUIOpen then return end
        -- Header buttons must never start a window drag.
        for _, button in ipairs({CloseBtn, MaxBtn, MinBtn}) do
            local pos, size = button.AbsolutePosition, button.AbsoluteSize
            if i.Position.X >= pos.X and i.Position.X <= pos.X + size.X
                and i.Position.Y >= pos.Y and i.Position.Y <= pos.Y + size.Y then return end
        end
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
    if draggingHeader and isUIOpen and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
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
    if destroyed then return end
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
        if fd then return end
        fd=true; fmoved=false; fs=i.Position; fstart=Float.Position
        touchId=nil
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
        nx = math.clamp(nx, 0, math.max(0, vp.X - 64))
        ny = math.clamp(ny, 0, math.max(0, vp.Y - 64))
        Float.Position = UDim2.new(0, nx, 0, ny)
    end
end)
bind(UserInputService.InputEnded, function(i)
    if (touchId and i == touchId) or (not touchId and i.UserInputType==Enum.UserInputType.MouseButton1) then
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
    local api
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
    local function toggle() val = not val; if api then api.Value=val end; render(false); if cb then cb(val) end end
    local btnArea = new("TextButton", {Size=UDim2.fromOffset(44,24), Position=UDim2.new(1,-54,0.5,-12), BackgroundTransparency=1, Text=""}, f)
    bind(btnArea.MouseButton1Click, toggle)
    api = {Frame=f, Value=val, Get=function() return val end, Set=function(v) val=(v==true); api.Value=val; render(false); if cb then cb(val) end end, SetText=function(t) lbl.Text=t end, RefreshTheme=refreshTheme, Destroy=function() f:Destroy() end}
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
    local sliderTouch
    local sliderConnections = {}
    local function sliderBind(signal, fn) sliderConnections[#sliderConnections+1]=bind(signal,fn,"slider.input") end
    local function cancelSlider() dragging=false;sliderTouch=nil end
    sliderBind(hit.InputBegan, function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            if dragging or not isUIOpen then return end
            dragging = true
            sliderTouch=i.UserInputType==Enum.UserInputType.Touch and i or nil
            setFromX(i.Position.X)
        end
    end)
    sliderBind(UserInputService.InputChanged, function(i)
        if not isUIOpen or state=="min" or not f.Parent then cancelSlider();return end
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            if sliderTouch and i~=sliderTouch then return end
            if not sliderTouch and i.UserInputType~=Enum.UserInputType.MouseMovement then return end
            setFromX(i.Position.X)
        end
    end)
    sliderBind(UserInputService.InputEnded, function(i)
        if (sliderTouch and i==sliderTouch) or (not sliderTouch and i.UserInputType==Enum.UserInputType.MouseButton1) then cancelSlider() end
    end)
    sliderBind(UserInputService.WindowFocusReleased,cancelSlider)
    sliderBind(Main:GetPropertyChangedSignal("Visible"),cancelSlider)
    bind(f.Destroying,function()
        cancelSlider()
        for _,connection in ipairs(sliderConnections) do connection:Disconnect() end
    end,"slider.destroy")
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
    local api={Distance=100,attackMobs=true,attackPlayers=true,Running=false,Delay=0.15}
    local RS=game:GetService("ReplicatedStorage")
    local worker
    local function remote(name)
        for _,nameOfContainer in ipairs({"Packages","Modules",""}) do
            local container=nameOfContainer=="" and RS or RS:FindFirstChild(nameOfContainer)
            local net=container and (container:FindFirstChild("Net") or container.Name=="Net" and container)
            local value=net and net:FindFirstChild(name)
            if value and value:IsA("RemoteEvent") then return value end
        end
    end
    local lastDispatch=-math.huge
    function api:AttackTarget(enemy)
        if destroyed then return false,"unloaded" end
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local root=c and c:FindFirstChild("HumanoidRootPart")
        local tool=c and c:FindFirstChildOfClass("Tool")
        local targetHumanoid=enemy and enemy:FindFirstChildOfClass("Humanoid")
        local head=enemy and (enemy:FindFirstChild("Head") or enemy:FindFirstChild("HumanoidRootPart"))
        if not root or not h or h.Health<=0 or not tool then return false,"missing_character_or_tool" end
        if tool.ToolTip=="Gun" then return false,"skill_weapon" end
        if not targetHumanoid or targetHumanoid.Health<=0 or not head or not head:IsA("BasePart") then return false,"invalid_target" end
        if (head.Position-root.Position).Magnitude>self.Distance then return false,"out_of_range" end
        local leftClick=tool:FindFirstChild("LeftClickRemote")
        local attack,hit=remote("RE/RegisterAttack"),remote("RE/RegisterHit")
        if not (leftClick and leftClick:IsA("RemoteEvent")) and (not attack or not hit) then return false,"remotes_unavailable" end
        if os.clock()-lastDispatch<self.Delay then return true,"cooldown" end
        lastDispatch=os.clock()
        local ok,err=pcall(function()
            -- Matsune prioritizes the equipped weapon's own M1 remote.
            if leftClick and leftClick:IsA("RemoteEvent") then
                local delta=head.Position-root.Position
                if delta.Magnitude<=0.001 then error("target direction unavailable") end
                leftClick:FireServer(delta.Unit,1)
            else
                attack:FireServer(0)
                hit:FireServer(head,{{enemy,head}})
            end
        end)
        if not ok then debugLog("WARN","combat.remote",err);return false,"remote_failed" end
        return true,leftClick and leftClick:IsA("RemoteEvent") and "left_click_remote_sent" or "remote_sent"
    end
    function api:AttackNearest()
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local root=c and c:FindFirstChild("HumanoidRootPart")
        local tool=c and c:FindFirstChildOfClass("Tool")
        if not root or not h or h.Health<=0 or not tool or tool.ToolTip=="Gun" then return end
        local best,bestDistance=nil,math.huge
        local function gather(folder)
            if folder then for _,enemy in ipairs(folder:GetDescendants()) do
                local enemyHumanoid=enemy:FindFirstChildOfClass("Humanoid")
                local head=enemy:FindFirstChild("Head") or enemy:FindFirstChild("HumanoidRootPart")
                if enemy~=c and enemyHumanoid and enemyHumanoid.Health>0 and head and head:IsA("BasePart") then
                    local d=(head.Position-root.Position).Magnitude
                    if d<=self.Distance and d<bestDistance then best=enemy;bestDistance=d end
                end
            end end
        end
        if self.attackMobs then gather(workspace:FindFirstChild("Enemies") or workspace:FindFirstChild("Hostiles")) end
        if self.attackPlayers then gather(workspace:FindFirstChild("Characters")) end
        if best then return self:AttackTarget(best) end
    end
    function api:Start()
        if destroyed or self.Running then return end
        self.Running=true
        worker=task.defer(function()
            local failures=0
            while self.Running and not destroyed do
                local ok,err=pcall(function() self:AttackNearest() end)
                if not ok then
                    failures=failures+1;debugLog("ERROR","FastAttack",err)
                    if failures>=3 then self.Running=false;notify({Title="FastAttack",Text=tostring(err)});break end
                else failures=0 end
                task.wait(self.Delay)
            end
            worker=nil
        end)
    end
    function api:Stop()
        self.Running=false
        if worker and worker~=coroutine.running() then pcall(task.cancel,worker) end
        worker=nil
    end
    function api:SetDelay(value)
        if type(value)=="number" and value==value then self.Delay=math.clamp(value,0.1,5) end
    end
    function api:SetDistance(value)
        if type(value)=="number" and value==value then self.Distance=math.clamp(value,1,150) end
    end
    api.BladeHits=api.AttackNearest
    return api
end

debugLog("INFO", "initFastAttack", "starting")
local fastAttackApi = initFastAttack()
debugLog("INFO", "initFastAttack", "ready")
_G.MatsuneFastAttack = fastAttackApi
table.insert(cleanupFns, function() fastAttackApi:Stop(); if _G.MatsuneFastAttack==fastAttackApi then _G.MatsuneFastAttack=nil end end)

-- === Inlined ESP module (Matsune) ===
local function initESP()
    return {Set=function() end, StartLoop=function() end, StopLoop=function() end,
        UpdateIsland=function() end, UpdatePlayers=function() end, UpdateChest=function() end,
        UpdateDevilFruit=function() end, UpdateFlower=function() end, UpdateRealFruit=function() end}
end
debugLog("INFO", "initESP", "starting")
local ownedESP = initESP()
debugLog("INFO", "initESP", "ready")
_G.MatsuneESP = ownedESP
table.insert(cleanupFns, function()
    ownedESP:StopLoop()
    if _G.MatsuneESP==ownedESP then _G.MatsuneESP=nil end
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
local espControls = {}
local function mkEspToggle(label, key)
    local control = addToggle(ESPtab, label, false, function(v)
        if espApi and espApi.Set then espApi:Set(key, v) end
    end)
    espControls[key]=control
    return control
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

-- Camera can be absent at startup or replaced later.
local cameraConnection
local function refreshViewport()
    if destroyed then return end
    setState(state)
    local vp = viewport()
    Float.Position = UDim2.fromOffset(
        math.clamp(Float.Position.X.Offset, 0, math.max(0, vp.X - 64)),
        math.clamp(Float.Position.Y.Offset, 0, math.max(0, vp.Y - 64)))
end
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
    local camera = workspace.CurrentCamera
    debugLog(camera and "INFO" or "WARN", "camera", camera and "watching viewport" or "not available; using fallback")
    if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshViewport) end
    refreshViewport()
end
bind(workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
table.insert(cleanupFns, function()
    if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
end)
watchCamera()
cancelDrag = function()
    draggingHeader = false
    headerTouch = nil
    fd = false
    touchId = nil
end
bind(UserInputService.WindowFocusReleased, cancelDrag)

-- Gameplay ports from supplied Cokka/Matsune sources; UI stays owned by XERECA.
-- Source command names/coordinates are historical data, not verified game contracts.
local function initImportedFeatures()
    local RS = game:GetService("ReplicatedStorage")
    local Lighting = game:GetService("Lighting")
    local RunService = game:GetService("RunService")
    local TeleportService = game:GetService("TeleportService")
    local jobs, generations, flags, controls = {}, {}, {}, {}
    local buttonBusy = {}
    local onJobStop = {}
    local gates = shared._XerecaCommandGates
    if type(gates) ~= "table" then gates = {}; shared._XerecaCommandGates = gates end
    local active = true
    local requestSession=0
    local requestOwners=setmetatable({}, {__mode="k"})
    local movementJobs={Farm=true,SeaCombat=true,FruitCollect=true,RaidNext=true,Boat=true,Trials=true,TrialPath=true,Azure=true,BoneCollect=true,EggCollect=true,Berries=true,Chests=true}
    local function requestToken()
        local owner=requestOwners[coroutine.running()]
        return {Session=requestSession,Owner=owner}
    end
    local function validRequest(token)
        return active and not destroyed and token.Session==requestSession
            and (not token.Owner or generations[token.Owner.Name]==token.Owner.Generation)
    end
    local moveTween, moveRoot, moveTarget, moveOwner
    local heldKeys = {}
    local motionState
    local fixedCombatTarget, fixedCombatPoint, fixedCombatOffset
    local collisionState = {}
    local moveVersion=0
    local function restoreCollisions()
        for object,value in pairs(collisionState) do if object.Parent then object.CanCollide=value end end
        table.clear(collisionState)
    end
    local options = {Weapon="Melee", Mastery="Off", MasteryHealth=30, Speed=100, Offset=20, FixedFarm=true,
        Boss="The Gorilla King", Mode="Off", Chip="Flame", Player="", SkillZ=true, SkillX=true, SkillC=true, SkillV=false, SkillF=false}
    local supported = game.PlaceId == 2753915549 or game.PlaceId == 4442272183 or game.PlaceId == 7449423635
    local speedSliders = {}
    local syncingSpeed = false
    local function report(event, detail)
        debugLog("INFO", "features." .. event, detail)
    end
    local function fail(message) error(message, 0) end
    local function path(root, ...)
        for _, name in ipairs({...}) do root = root and root:FindFirstChild(name) end
        return root
    end
    local function character()
        local c = LocalPlayer.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and r:IsA("BasePart") and h.Health > 0 then return c,h,r end
    end
    local function part(object)
        if not object then return nil end
        if object:IsA("BasePart") then return object end
        local handle = object:FindFirstChild("HumanoidRootPart") or object:FindFirstChild("Handle") or object:FindFirstChild("Engine")
        if handle and handle:IsA("BasePart") then return handle end
        if object:IsA("Model") then return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true) end
    end
    local function distance(object)
        local _,_,root = character()
        local p = part(object)
        return root and p and (root.Position - p.Position).Magnitude or math.huge
    end
    local function command(key, spacing, remote, ...)
        if not active or destroyed then return false, "unloaded" end
        if not supported then fail("Este comando depende de um dos três mares de Blox Fruits.") end
        if not remote or not remote:IsA("RemoteFunction") then fail("RemoteFunction indisponível: " .. key) end
        local gate = gates[key]
        if not gate then gate={Busy=false, Next=0}; gates[key]=gate end
        if gate.Busy or os.clock() < gate.Next then return false, "interval" end
        gate.Busy=true; gate.Next=os.clock()+spacing
        local args=table.pack(...)
        local token=requestToken()
        -- Keep in-flight calls outside cancelable jobs; disabling cannot undo server work.
        task.defer(function()
            if not validRequest(token) then gate.Busy=false; return end
            local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args,1,args.n)) end)
            gate.Busy=false
            gate.Next=math.max(gate.Next, os.clock()+0.25)
            if active and not destroyed then
                debugLog(ok and "INFO" or "ERROR", "remote." .. key, tostring(result))
            end
        end)
        return true, "requested"
    end
    local function comm(key, spacing, ...)
        return command(key, spacing, path(RS,"Remotes","CommF_"), ...)
    end
    local function commSequence(key, spacing, calls)
        if not active or destroyed then return end
        local remote=path(RS,"Remotes","CommF_")
        if not supported or not remote or not remote:IsA("RemoteFunction") then fail("RemoteFunction de compra indisponível.") end
        local gate=gates[key]
        if not gate then gate={Busy=false,Next=0};gates[key]=gate end
        if gate.Busy or os.clock()<gate.Next then return end
        gate.Busy=true;gate.Next=os.clock()+spacing
        local token=requestToken()
        task.defer(function()
            local ok,err=pcall(function()
                for _,args in ipairs(calls) do
                    if not validRequest(token) then return end
                    local result=remote:InvokeServer(table.unpack(args))
                    debugLog("INFO","remote."..key,tostring(result))
                end
            end)
            gate.Busy=false
            if not ok and active and not destroyed then debugLog("ERROR","remote."..key,err) end
        end)
    end
    local function net(key, spacing, name, ...)
        return command(key, spacing, path(RS,"Modules","Net",name) or path(RS,"Packages","Net",name), ...)
    end
    local function releaseMotion()
        local previous=motionState
        motionState=nil
        if not previous then return end
        if previous.Died then previous.Died:Disconnect() end
        if previous.Root.Parent then
            previous.Root.Anchored=previous.Anchored
            previous.Root.AssemblyLinearVelocity=Vector3.new(0,0,0)
            previous.Root.AssemblyAngularVelocity=Vector3.new(0,0,0)
        end
        if previous.Humanoid.Parent then previous.Humanoid.AutoRotate=previous.AutoRotate end
    end
    local function stopMove(owner)
        if owner and moveOwner ~= owner then return end
        moveVersion=moveVersion+1
        if moveTween then moveTween:Cancel() end
        restoreCollisions()
        releaseMotion()
        moveTween,moveRoot,moveTarget,moveOwner=nil,nil,nil,nil
    end
    local function suspendMotion(root,humanoid)
        motionState={Root=root,Humanoid=humanoid,Anchored=root.Anchored,AutoRotate=humanoid.AutoRotate}
        motionState.Died=humanoid.Died:Connect(function()
            stopMove();fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil
        end)
        humanoid.Sit=false
        humanoid.AutoRotate=false
        root.Anchored=true
        root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    end
    local function move(target, owner)
        if owner=="Manual" then
            for name in pairs(movementJobs) do if flags[name] and controls[name] then controls[name].Set(false) end end
        end
        local _,h,root=character()
        if not root or typeof(target) ~= "CFrame" then return end
        if moveRoot==root and moveOwner==owner and moveTarget and motionState
            and (moveTarget.Position-target.Position).Magnitude<0.5 then
            -- A completed farm Tween retains its world-space anchor; do not
            -- release/reacquire it every farm tick or gravity wins between ticks.
            if owner=="Farm" or (moveTween and moveTween.PlaybackState==Enum.PlaybackState.Playing) then return end
        end
        stopMove()
        moveOwner,moveRoot,moveTarget=owner,root,target
        suspendMotion(root,h)
        local delta=(root.Position-target.Position).Magnitude
        if delta<0.1 then
            if owner~="Farm" then releaseMotion() end
            return
        end
        moveTween=TweenService:Create(root,TweenInfo.new(math.max(0.1,delta/options.Speed),Enum.EasingStyle.Linear),{CFrame=target})
        local version=moveVersion
        moveTween.Completed:Once(function(playback)
            if moveVersion~=version then return end
            if playback==Enum.PlaybackState.Completed and owner=="Farm" then
                -- Farm suspension continues until the owner explicitly stops.
                root.CFrame=target
            else
                restoreCollisions()
                releaseMotion()
            end
        end)
        moveTween:Play()
    end
    local function setTweenSpeed(value)
        if syncingSpeed or not active or destroyed then return end
        if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return end
        local speed=math.clamp(math.floor(value/5+0.5)*5,10,500)
        local changed=options.Speed~=speed
        options.Speed=speed
        syncingSpeed=true
        for _,slider in ipairs(speedSliders) do
            if slider.Get()~=speed then slider.Set(speed) end
        end
        syncingSpeed=false
        if changed then
            debugLog("INFO","tween.speed",tostring(speed).." studs/s")
            if moveTween and moveTween.PlaybackState==Enum.PlaybackState.Playing then
                local destination,owner,previousRoot=moveTarget,moveOwner,moveRoot
                stopMove()
                local _,_,root=character()
                if root==previousRoot and destination then move(destination,owner) end
            end
        end
    end
    local function speedSlider(page)
        local slider=addSlider(page,{Name="Velocidade do Tween",Min=10,Max=500,Step=5,Default=options.Speed,
            Suffix=" studs/s",Callback=setTweenSpeed})
        speedSliders[#speedSliders+1]=slider
        return slider
    end
    bind(RunService.Stepped,function()
        if not motionState then return end
        local c,h,root=character()
        if not active or destroyed or root~=motionState.Root or h~=motionState.Humanoid then stopMove();return end
        root.Anchored=true
        root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        root.AssemblyAngularVelocity=Vector3.new(0,0,0)
        if moveOwner=="Farm" and moveTarget
            and (not moveTween or moveTween.PlaybackState~=Enum.PlaybackState.Playing) then
            root.CFrame=moveTarget
        end
        for _,object in ipairs(c:GetDescendants()) do
            if object:IsA("BasePart") then
                if collisionState[object]==nil then collisionState[object]=object.CanCollide end
                object.CanCollide=false
            end
        end
    end,"features.movement.physics")
    local function stopJob(name)
        generations[name]=(generations[name] or 0)+1
        local thread=jobs[name]; jobs[name]=nil
        if thread and thread ~= coroutine.running() then pcall(task.cancel, thread) end
        stopMove(name)
        buttonBusy[name]=nil
        if onJobStop[name] then onJobStop[name]() end
    end
    local function startJob(name, interval, fn)
        stopJob(name)
        if movementJobs[name] then
            for other in pairs(movementJobs) do if other~=name and flags[other] and controls[other] then controls[other].Set(false) end end
        end
        if not active or destroyed then return end
        local generation=generations[name]
        jobs[name]=task.defer(function()
            if name:sub(1,7)~="button." then requestOwners[coroutine.running()]={Name=name,Generation=generation} end
            local errors=0
            while active and not destroyed and generations[name]==generation do
                local ok,err=xpcall(fn,function(e) return debug.traceback(tostring(e),2) end)
                if not ok then
                    errors=errors+1
                    debugLog("ERROR","job."..name,err)
                    if errors==1 then notify({Title=name,Text=tostring(err):sub(1,160)}) end
                    -- Exit after repeated failures instead of silently spinning forever.
                    if errors>=3 then
                        if controls[name] then controls[name].Set(false) end
                        break
                    end
                else errors=0 end
                if not active or destroyed or generations[name]~=generation then break end
                task.wait(interval)
            end
            if generations[name]==generation then jobs[name]=nil; stopMove(name) end
        end)
    end
    local function toggleJob(page, label, key, interval, fn)
        local control=addToggle(page,label,false,function(on)
            flags[key]=on
            if on then startJob(key,interval,fn) else stopJob(key) end
            report(key,on and "enabled" or "disabled")
        end)
        controls[key]=control
        return control
    end
    local function button(page, label, fn)
        local key="button."..label
        return addBtn(page,label,function()
            if buttonBusy[key] or not active or destroyed then return end
            startJob(key,1,function()
                local ok,err=xpcall(fn,function(e) return debug.traceback(tostring(e),2) end)
                buttonBusy[key]=nil
                stopJob(key)
                if not ok then
                    debugLog("ERROR",key,err)
                    notify({Title=label,Text=tostring(err):sub(1,160)})
                end
            end)
            buttonBusy[key]=true
        end)
    end
    local function dropdown(page,label,values,default,callback)
        local frame=new("Frame",{Size=UDim2.new(1,-24,0,36),ClipsDescendants=true,Theme={BackgroundColor3="ComponentBg"}},page)
        new("UICorner",{CornerRadius=UDim.new(0,6)},frame)
        local selected=default
        local head=new("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,Text="",Font=Enum.Font.Gotham,TextSize=13,TextTruncate=Enum.TextTruncate.AtEnd,Theme={TextColor3="Text"}},frame)
        local list=new("ScrollingFrame",{Size=UDim2.new(1,0,0,144),Position=UDim2.fromOffset(0,36),BackgroundTransparency=1,ScrollBarThickness=4,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},frame)
        new("UIListLayout",{Padding=UDim.new(0,2)},list)
        local choices={}
        local function show() head.Text=label..": "..tostring(selected or "—").." ▾" end
        local function set(value,quiet)
            selected=value; show(); frame.Size=UDim2.new(1,-24,0,36)
            if callback and not quiet then callback(value) end
        end
        local function refresh(items)
            for _,c in ipairs(choices) do c:Disconnect() end
            table.clear(choices)
            for _,child in ipairs(list:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
            for _,value in ipairs(items) do
                local b=new("TextButton",{Size=UDim2.new(1,0,0,28),Text=tostring(value),Font=Enum.Font.Gotham,TextSize=13,Theme={BackgroundColor3="ComponentBg",TextColor3="Text"}},list)
                choices[#choices+1]=b.Activated:Connect(function() if active and not destroyed then set(value) end end)
            end
        end
        bind(head.Activated,function() frame.Size=UDim2.new(1,-24,0,frame.Size.Y.Offset==36 and 180 or 36) end,"dropdown."..label)
        refresh(values);show()
        table.insert(cleanupFns,function() for _,c in ipairs(choices) do c:Disconnect() end end)
        return {Set=set,Refresh=refresh,Get=function() return selected end}
    end
    local function equip(kind)
        local c,h=character()
        if not c then return nil end
        local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
        for _,container in ipairs({c,backpack}) do
            if container then for _,tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.ToolTip==kind or tool.Name==kind) then
                    if tool.Parent~=c then h:EquipTool(tool) end
                    return tool
                end
            end end
        end
    end
    local function press(key)
        if UserInputService:GetFocusedTextBox() then return end
        local vim=game:GetService("VirtualInputManager")
        local code=Enum.KeyCode[key]
        if not code then return end
        heldKeys[code]=true
        local ok,err=pcall(function() vim:SendKeyEvent(true,code,false,game) end)
        local released,releaseErr=pcall(function() vim:SendKeyEvent(false,code,false,game) end)
        if released then heldKeys[code]=nil end
        if not ok or not released then fail(tostring(err or releaseErr)) end
    end
    local function health(object)
        local h=object and object:FindFirstChildOfClass("Humanoid")
        if h then return h.Health,h.MaxHealth end
        local value=object and object:FindFirstChild("Health")
        if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
            return value.Value,object:GetAttribute("MaxHealth") or value.Value
        end
        local label=path(object,"HealthBBG","Frame","TextLabel")
        if label and label:IsA("TextLabel") then
            local current,max=label.Text:gsub(",", ""):match("([%d%.]+)%s*/%s*([%d%.]+)")
            return tonumber(current) or 0,tonumber(max) or 1
        end
        return 0,1
    end
    local function nearest(folder, predicate)
        local best,metric=nil,math.huge
        if folder then for _,object in ipairs(folder:GetDescendants()) do
            local hp=health(object)
            if part(object) and hp>0 and (not predicate or predicate(object)) then
                local d=distance(object)
                if d<metric then best,metric=object,d end
            end
        end end
        return best
    end
    local function cleanName(name)
        local result=tostring(name):gsub("<[^>]*>",""):gsub("%s*%[.-%]","")
        result=result:gsub("\194\160"," "):lower():gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
        return (result:gsub("posessed", "possessed"))
    end
    local function named(folder,names)
        return nearest(folder,function(o)
            for _,name in ipairs(names) do if cleanName(o.Name)==cleanName(name) then return true end end
            return false
        end)
    end
    local function retainedFarmTarget(folder,names)
        local target=fixedCombatTarget
        if not options.FixedFarm or not target or not folder or not target:IsDescendantOf(folder) or health(target)<=0 or not part(target) then return nil end
        if names then
            for _,name in ipairs(names) do if cleanName(target.Name)==cleanName(name) then return target end end
            return nil
        end
        return target
    end
    local function farmNamed(folder,names)
        return retainedFarmTarget(folder,names) or named(folder,names)
    end
    local function skillAttack()
        for _,key in ipairs({"Z","X","C","V","F"}) do if options["Skill"..key] then press(key) end end
    end
    local lastInputClick=-math.huge
    local function inputClick(method)
        if destroyed or not active then return false,"unloaded" end
        if UserInputService:GetFocusedTextBox() then return false,"typing" end
        if os.clock()-lastInputClick<0.15 then return false,"cooldown" end
        lastInputClick=os.clock()
        local camera=workspace.CurrentCamera
        local function r2()
            -- Reference: Hoho's ScriptLoad.lua contains this in a commented AutoM1 example.
            local vim=game:GetService("VirtualInputManager")
            local ok,err=pcall(function() vim:SendKeyEvent(true,Enum.KeyCode.ButtonR2,false,game) end)
            local released,releaseErr=pcall(function() vim:SendKeyEvent(false,Enum.KeyCode.ButtonR2,false,game) end)
            if not ok or not released then return false,tostring(err or releaseErr) end
            return true,"button_r2_sent"
        end
        if method=="Hoho R2" then return r2() end
        -- Matsune's farm uses VirtualUser:CaptureController()/Button1Down().
        -- Pair it with Button1Up even if the down event errors; never leave a held click.
        local vu
        local point=camera and Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y/2) or Vector2.new(1,1)
        local ok,err=pcall(function()
            vu=game:GetService("VirtualUser")
            vu:CaptureController()
            if not camera then error("camera unavailable") end
            vu:Button1Down(point,camera.CFrame)
        end)
        local released,releaseErr=pcall(function() if vu then vu:Button1Up(point,camera and camera.CFrame or CFrame.new()) end end)
        if ok and released then return true,"virtual_user_sent" end
        local fallback,reason=r2()
        if fallback then return true,reason end
        return false,"input_unavailable: "..tostring(err or releaseErr).." / "..tostring(reason)
    end
    local attackState={Phase="idle",Method="Auto",Attempts=0}
    local lastAttackTarget,lastAttackHealth,lastDamageAt
    local function fight(target,owner)
        local root=part(target)
        local hp,maxHP=health(target)
        if not root or hp<=0 then return end
        local destination=root.CFrame*CFrame.new(0,options.Offset,4)
        if owner=="Farm" and options.FixedFarm then
            if fixedCombatTarget~=target or fixedCombatOffset~=options.Offset then
                fixedCombatTarget=target
                fixedCombatPoint=destination
                fixedCombatOffset=options.Offset
            end
            destination=fixedCombatPoint
        end
        move(destination,owner)
        local mastery=options.Mastery~="Off" and hp/math.max(1,maxHP)*100 <= options.MasteryHealth
        local tool=equip(mastery and options.Mastery or options.Weapon)
        attackState.Target=target.Name
        attackState.Tool=tool and tool.Name or nil
        attackState.Distance=distance(target)
        if lastAttackTarget~=target then lastAttackTarget=target;lastAttackHealth=hp;lastDamageAt=nil end
        if hp<lastAttackHealth then lastDamageAt=os.clock() end
        lastAttackHealth=hp
        attackState.LastDamageAt=lastDamageAt
        if not tool then
            attackState.Phase="missing_weapon"
        elseif attackState.Distance>100 then
            attackState.Phase="approaching"
        elseif mastery or flags.SkillSpam or owner=="SeaCombat" then
            skillAttack();attackState.Phase="skills_sent"
        else
            -- Tool activation alone does not reach the game's newer combat remotes.
            -- Always preserve the normal tool path, then target only this farm enemy.
            local activated,activateErr=pcall(function() tool:Activate() end)
            local clicked,inputReason=false,"tool_only"
            if attackState.Method~="Tool" then clicked,inputReason=inputClick(attackState.Method) end
            attackState.Input=inputReason
            local sent,reason=false,"tool_only"
            if attackState.Method=="Auto" then sent,reason=fastAttackApi:AttackTarget(target) end
            if not activated then debugLog("WARN","combat.tool",activateErr) end
            if not activated and not clicked and not sent then debugLog("WARN","combat.input",inputReason) end
            attackState.Attempts=attackState.Attempts+1
            attackState.Phase=sent and "attack_sent" or clicked and "input_sent" or activated and "tool_activated" or "attack_unavailable"
            attackState.Transport=reason
        end
        debugLog("INFO","combat",attackState.Phase.." target="..tostring(target.Name).." tool="..tostring(attackState.Tool).." transport="..tostring(attackState.Transport).." hp="..tostring(hp))
    end
    -- Adapted static quest/boss/island/shop data from the two supplied sources.
    local function questForLevel()
        local MyLevel, CFrameQuest, CFrameMon, Mon, NameMon, NameQuest, LevelQuest, Entrance
        local data = LocalPlayer:FindFirstChild("Data")
        local level = data and data:FindFirstChild("Level")
        if not level or level.Value > 2600 then return nil end
        local L_23_, L_24_, L_25_ = game.PlaceId == 2753915549, game.PlaceId == 4442272183, game.PlaceId == 7449423635
    	MyLevel = game:GetService('Players').LocalPlayer.Data.Level.Value;
    	if L_23_ then
    		if MyLevel == 1 or MyLevel <= 9 then
    			Mon, NameMon, NameQuest, LevelQuest = "Bandit", "Bandit", "BanditQuest1", 1;
    			CFrameQuest = CFrame.new(1059.37195, 15.4495068, 1550.4231, 0.939700544, - 0, - 0.341998369, 0, 1, - 0, 0.341998369, 0, 0.939700544)
    			CFrameMon = CFrame.new(1045.962646484375, 27.00250816345215, 1560.8203125)
    		elseif MyLevel == 10 or MyLevel <= 14 then
    			Mon, NameMon, NameQuest, LevelQuest = "Monkey", "Monkey", "JungleQuest", 1;
    			CFrameQuest = CFrame.new(- 1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, - 0, - 1, 0, 0)
    			CFrameMon = CFrame.new(- 1448.51806640625, 67.85301208496094, 11.46579647064209)
    		elseif MyLevel == 15 or MyLevel <= 29 then
    			Mon, NameMon, NameQuest, LevelQuest = "Gorilla", "Gorilla", "JungleQuest", 2;
    			CFrameQuest = CFrame.new(- 1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, - 0, - 1, 0, 0)
    			CFrameMon = CFrame.new(- 1129.8836669921875, 40.46354675292969, - 525.4237060546875)
    		elseif MyLevel == 30 or MyLevel <= 39 then
    			Mon, NameMon, NameQuest, LevelQuest = "Pirate", "Pirate", "BuggyQuest1", 1;
    			CFrameQuest = CFrame.new(- 1141.07483, 4.10001802, 3831.5498, 0.965929627, - 0, - 0.258804798, 0, 1, - 0, 0.258804798, 0, 0.965929627)
    			CFrameMon = CFrame.new(- 1103.513427734375, 13.752052307128906, 3896.091064453125)
    		elseif MyLevel == 40 or MyLevel <= 59 then
    			Mon, NameMon, NameQuest, LevelQuest = "Brute", "Brute", "BuggyQuest1", 2;
    			CFrameQuest = CFrame.new(- 1141.07483, 4.10001802, 3831.5498, 0.965929627, - 0, - 0.258804798, 0, 1, - 0, 0.258804798, 0, 0.965929627)
    			CFrameMon = CFrame.new(- 1140.083740234375, 14.809885025024414, 4322.92138671875)
    		elseif MyLevel == 60 or MyLevel <= 74 then
    			Mon, NameMon, NameQuest, LevelQuest = "Desert Bandit", "Desert Bandit", "DesertQuest", 1;
    			CFrameQuest = CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, - 0, - 0.573571265, 0, 1, - 0, 0.573571265, 0, 0.819155693)
    			CFrameMon = CFrame.new(924.7998046875, 6.44867467880249, 4481.5859375)
    		elseif MyLevel == 75 or MyLevel <= 89 then
    			NameMon, NameQuest, LevelQuest = "Desert Officer", "DesertQuest", 2;
    			CFrameQuest = CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, - 0, - 0.573571265, 0, 1, - 0, 0.573571265, 0, 0.819155693)
    			CFrameMon = CFrame.new(1608.2822265625, 8.614224433898926, 4371.00732421875)
    		elseif MyLevel == 90 or MyLevel <= 99 then
    			NameMon, NameQuest, LevelQuest = "Snow Bandit", "SnowQuest", 1;
    			CFrameQuest = CFrame.new(1389.74451, 88.1519318, - 1298.90796, - 0.342042685, 0, 0.939684391, 0, 1, 0, - 0.939684391, 0, - 0.342042685)
    			CFrameMon = CFrame.new(1354.347900390625, 87.27277374267578, - 1393.946533203125)
    		elseif MyLevel == 100 or MyLevel <= 119 then
    			NameMon, NameQuest, LevelQuest = "Snowman", "SnowQuest", 2;
    			CFrameQuest = CFrame.new(1389.74451, 88.1519318, - 1298.90796, - 0.342042685, 0, 0.939684391, 0, 1, 0, - 0.939684391, 0, - 0.342042685)
    			CFrameMon = CFrame.new(1201.6412353515625, 144.57958984375, - 1550.0670166015625)
    		elseif MyLevel == 120 or MyLevel <= 149 then
    			NameMon, NameQuest, LevelQuest = "Chief Petty Officer", "MarineQuest2", 1;
    			CFrameQuest = CFrame.new(- 5039.58643, 27.3500385, 4324.68018, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 4881.23095703125, 22.65204429626465, 4273.75244140625)
    		elseif MyLevel == 150 or MyLevel <= 174 then
    			NameMon, NameQuest, LevelQuest = "Sky Bandit", "SkyQuest", 1;
    			CFrameQuest = CFrame.new(- 4839.53027, 716.368591, - 2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, - 0.500031412, 0, 0.866007268)
    			CFrameMon = CFrame.new(- 4953.20703125, 295.74420166015625, - 2899.22900390625)
    		elseif MyLevel == 175 or MyLevel <= 189 then
    			NameMon, NameQuest, LevelQuest = "Dark Master", "SkyQuest", 2;
    			CFrameQuest = CFrame.new(- 4839.53027, 716.368591, - 2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, - 0.500031412, 0, 0.866007268)
    			CFrameMon = CFrame.new(- 5259.8447265625, 391.3976745605469, - 2229.035400390625)
    		elseif MyLevel == 190 or MyLevel <= 209 then
    			NameMon, NameQuest, LevelQuest = "Prisoner", "PrisonerQuest", 1;
    			CFrameQuest = CFrame.new(5308.93115, 1.65517521, 475.120514, - 0.0894274712, - 5.00292918e-09, - 0.995993316, 1.60817859e-09, 1, - 5.16744869e-09, 0.995993316, - 2.06384709e-09, - 0.0894274712)
    			CFrameMon = CFrame.new(5098.9736328125, - 0.3204058110713959, 474.2373352050781)
    		elseif MyLevel == 210 or MyLevel <= 249 then
    			NameMon, NameQuest, LevelQuest = "Dangerous Prisoner", "PrisonerQuest", 2;
    			CFrameQuest = CFrame.new(5308.93115, 1.65517521, 475.120514, - 0.0894274712, - 5.00292918e-09, - 0.995993316, 1.60817859e-09, 1, - 5.16744869e-09, 0.995993316, - 2.06384709e-09, - 0.0894274712)
    			CFrameMon = CFrame.new(5654.5634765625, 15.633401870727539, 866.2991943359375)
    		elseif MyLevel == 250 or MyLevel <= 274 then
    			NameMon, NameQuest, LevelQuest = "Toga Warrior", "ColosseumQuest", 1;
    			CFrameQuest = CFrame.new(- 1580.04663, 6.35000277, - 2986.47534, - 0.515037298, 0, - 0.857167721, 0, 1, 0, 0.857167721, 0, - 0.515037298)
    			CFrameMon = CFrame.new(- 1820.21484375, 51.68385696411133, - 2740.6650390625)
    		elseif MyLevel == 275 or MyLevel <= 299 then
    			NameMon, NameQuest, LevelQuest = "Gladiator", "ColosseumQuest", 2;
    			CFrameQuest = CFrame.new(- 1580.04663, 6.35000277, - 2986.47534, - 0.515037298, 0, - 0.857167721, 0, 1, 0, 0.857167721, 0, - 0.515037298)
    			CFrameMon = CFrame.new(- 1292.838134765625, 56.380882263183594, - 3339.031494140625)
    		elseif MyLevel == 300 or MyLevel <= 324 then
    			NameMon, NameQuest, LevelQuest = "Military Soldier", "MagmaQuest", 1;
    			CFrameQuest = CFrame.new(- 5313.37012, 10.9500084, 8515.29395, - 0.499959469, 0, 0.866048813, 0, 1, 0, - 0.866048813, 0, - 0.499959469)
    			CFrameMon = CFrame.new(- 5411.16455078125, 11.081554412841797, 8454.29296875)
    		elseif MyLevel == 325 or MyLevel <= 374 then
    			NameMon, NameQuest, LevelQuest = "Military Spy", "MagmaQuest", 2;
    			CFrameQuest = CFrame.new(- 5313.37012, 10.9500084, 8515.29395, - 0.499959469, 0, 0.866048813, 0, 1, 0, - 0.866048813, 0, - 0.499959469)
    			CFrameMon = CFrame.new(- 5802.8681640625, 86.26241302490234, 8828.859375)
    		elseif MyLevel == 375 or MyLevel <= 399 then
    			NameMon, NameQuest, LevelQuest = "Fishman Warrior", "FishmanQuest", 1;
    			CFrameQuest = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
    			CFrameMon = CFrame.new(60878.30078125, 18.482830047607422, 1543.7574462890625)
    			Entrance=Vector3.new(61163.8515625, 11.6796875, 1819.7841796875)
    		elseif MyLevel == 400 or MyLevel <= 449 then
    			NameMon, NameQuest, LevelQuest = "Fishman Commando", "FishmanQuest", 2;
    			CFrameQuest = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
    			CFrameMon = CFrame.new(61922.6328125, 18.482830047607422, 1493.934326171875)
    			Entrance=Vector3.new(61163.8515625, 11.6796875, 1819.7841796875)
    		elseif MyLevel == 450 or MyLevel <= 474 then
    			NameMon, NameQuest, LevelQuest = "God's Guard", "SkyExp1Quest", 1;
    			CFrameQuest = CFrame.new(- 4721.88867, 843.874695, - 1949.96643, 0.996191859, - 0, - 0.0871884301, 0, 1, - 0, 0.0871884301, 0, 0.996191859)
    			CFrameMon = CFrame.new(- 4710.04296875, 845.2769775390625, - 1927.3079833984375)
    			Entrance=Vector3.new(- 4607.82275, 872.54248, - 1667.55688)
    		elseif MyLevel == 475 or MyLevel <= 524 then
    			NameMon, NameQuest, LevelQuest = "Shanda", "SkyExp1Quest", 2;
    			CFrameQuest = CFrame.new(- 7859.09814, 5544.19043, - 381.476196, - 0.422592998, 0, 0.906319618, 0, 1, 0, - 0.906319618, 0, - 0.422592998)
    			CFrameMon = CFrame.new(- 7678.48974609375, 5566.40380859375, - 497.2156066894531)
    			Entrance=Vector3.new(- 7894.6176757813, 5547.1416015625, - 380.29119873047)
    		elseif MyLevel == 525 or MyLevel <= 549 then
    			NameMon, NameQuest, LevelQuest = "Royal Squad", "SkyExp2Quest", 1;
    			CFrameQuest = CFrame.new(- 7906.81592, 5634.6626, - 1411.99194, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 7624.25244140625, 5658.13330078125, - 1467.354248046875)
    		elseif MyLevel == 550 or MyLevel <= 624 then
    			NameMon, NameQuest, LevelQuest = "Royal Soldier", "SkyExp2Quest", 2;
    			CFrameQuest = CFrame.new(- 7906.81592, 5634.6626, - 1411.99194, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 7836.75341796875, 5645.6640625, - 1790.6236572265625)
    		elseif MyLevel == 625 or MyLevel <= 649 then
    			NameMon, NameQuest, LevelQuest = "Galley Pirate", "FountainQuest", 1;
    			CFrameQuest = CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, - 0.996196866, 0, 0.087131381)
    			CFrameMon = CFrame.new(5551.02197265625, 78.90135192871094, 3930.412841796875)
    		elseif MyLevel >= 650 then
    			NameMon, NameQuest, LevelQuest = "Galley Captain", "FountainQuest", 2;
    			CFrameQuest = CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, - 0.996196866, 0, 0.087131381)
    			CFrameMon = CFrame.new(5441.95166015625, 42.50205993652344, 4950.09375)
    		end
    	elseif L_24_ then
    		if MyLevel == 700 or MyLevel <= 724 then
    			NameMon, NameQuest, LevelQuest = "Raider", "Area1Quest", 1;
    			CFrameQuest = CFrame.new(- 429.543518, 71.7699966, 1836.18188, - 0.22495985, 0, - 0.974368095, 0, 1, 0, 0.974368095, 0, - 0.22495985)
    			CFrameMon = CFrame.new(- 728.3267211914062, 52.779319763183594, 2345.7705078125)
    		elseif MyLevel == 725 or MyLevel <= 774 then
    			NameMon, NameQuest, LevelQuest = "Mercenary", "Area1Quest", 2;
    			CFrameQuest = CFrame.new(- 429.543518, 71.7699966, 1836.18188, - 0.22495985, 0, - 0.974368095, 0, 1, 0, 0.974368095, 0, - 0.22495985)
    			CFrameMon = CFrame.new(- 1004.3244018554688, 80.15886688232422, 1424.619384765625)
    		elseif MyLevel == 775 or MyLevel <= 799 then
    			NameMon, NameQuest, LevelQuest = "Swan Pirate", "Area2Quest", 1;
    			CFrameQuest = CFrame.new(638.43811, 71.769989, 918.282898, 0.139203906, 0, 0.99026376, 0, 1, 0, - 0.99026376, 0, 0.139203906)
    			CFrameMon = CFrame.new(1068.664306640625, 137.61428833007812, 1322.1060791015625)
    		elseif MyLevel == 800 or MyLevel <= 874 then
    			NameMon, NameQuest, LevelQuest = "Factory Staff", "Area2Quest", 2;
    			CFrameQuest = CFrame.new(632.698608, 73.1055908, 918.666321, - 0.0319722369, 8.96074881e-10, - 0.999488771, 1.36326533e-10, 1, 8.92172336e-10, 0.999488771, - 1.07732087e-10, - 0.0319722369)
    			CFrameMon = CFrame.new(73.07867431640625, 81.86344146728516, - 27.470672607421875)
    		elseif MyLevel == 875 or MyLevel <= 899 then
    			NameMon, NameQuest, LevelQuest = "Marine Lieutenant", "MarineQuest3", 1;
    			CFrameQuest = CFrame.new(- 2440.79639, 71.7140732, - 3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, - 0.500031412, 0, 0.866007268)
    			CFrameMon = CFrame.new(- 2821.372314453125, 75.89727783203125, - 3070.089111328125)
    		elseif MyLevel == 900 or MyLevel <= 949 then
    			NameMon, NameQuest, LevelQuest = "Marine Captain", "MarineQuest3", 2;
    			CFrameQuest = CFrame.new(- 2440.79639, 71.7140732, - 3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, - 0.500031412, 0, 0.866007268)
    			CFrameMon = CFrame.new(- 1861.2310791015625, 80.17658233642578, - 3254.697509765625)
    		elseif MyLevel == 950 or MyLevel <= 974 then
    			NameMon, NameQuest, LevelQuest = "Zombie", "ZombieQuest", 1;
    			CFrameQuest = CFrame.new(- 5497.06152, 47.5923004, - 795.237061, - 0.29242146, 0, - 0.95628953, 0, 1, 0, 0.95628953, 0, - 0.29242146)
    			CFrameMon = CFrame.new(- 5657.77685546875, 78.96973419189453, - 928.68701171875)
    		elseif MyLevel == 975 or MyLevel <= 999 then
    			NameMon, NameQuest, LevelQuest = "Vampire", "ZombieQuest", 2;
    			CFrameQuest = CFrame.new(- 5497.06152, 47.5923004, - 795.237061, - 0.29242146, 0, - 0.95628953, 0, 1, 0, 0.95628953, 0, - 0.29242146)
    			CFrameMon = CFrame.new(- 6037.66796875, 32.18463897705078, - 1340.6597900390625)
    		elseif MyLevel == 1000 or MyLevel <= 1049 then
    			NameMon, NameQuest, LevelQuest = "Snow Trooper", "SnowMountainQuest", 1;
    			CFrameQuest = CFrame.new(609.858826, 400.119904, - 5372.25928, - 0.374604106, 0, 0.92718488, 0, 1, 0, - 0.92718488, 0, - 0.374604106)
    			CFrameMon = CFrame.new(549.1473388671875, 427.3870544433594, - 5563.69873046875)
    		elseif MyLevel == 1050 or MyLevel <= 1099 then
    			NameMon, NameQuest, LevelQuest = "Winter Warrior", "SnowMountainQuest", 2;
    			CFrameQuest = CFrame.new(609.858826, 400.119904, - 5372.25928, - 0.374604106, 0, 0.92718488, 0, 1, 0, - 0.92718488, 0, - 0.374604106)
    			CFrameMon = CFrame.new(1142.7451171875, 475.6398010253906, - 5199.41650390625)
    		elseif MyLevel == 1100 or MyLevel <= 1124 then
    			NameMon, NameQuest, LevelQuest = "Lab Subordinate", "IceSideQuest", 1;
    			CFrameQuest = CFrame.new(- 6064.06885, 15.2422857, - 4902.97852, 0.453972578, - 0, - 0.891015649, 0, 1, - 0, 0.891015649, 0, 0.453972578)
    			CFrameMon = CFrame.new(- 5707.4716796875, 15.951709747314453, - 4513.39208984375)
    		elseif MyLevel == 1125 or MyLevel <= 1174 then
    			NameMon, NameQuest, LevelQuest = "Horned Warrior", "IceSideQuest", 2;
    			CFrameQuest = CFrame.new(- 6064.06885, 15.2422857, - 4902.97852, 0.453972578, - 0, - 0.891015649, 0, 1, - 0, 0.891015649, 0, 0.453972578)
    			CFrameMon = CFrame.new(- 6341.36669921875, 15.951770782470703, - 5723.162109375)
    		elseif MyLevel == 1175 or MyLevel <= 1199 then
    			NameMon, NameQuest, LevelQuest = "Magma Ninja", "FireSideQuest", 1;
    			CFrameQuest = CFrame.new(- 5428.03174, 15.0622921, - 5299.43457, - 0.882952213, 0, 0.469463557, 0, 1, 0, - 0.469463557, 0, - 0.882952213)
    			CFrameMon = CFrame.new(- 5449.6728515625, 76.65874481201172, - 5808.20068359375)
    		elseif MyLevel == 1200 or MyLevel <= 1249 then
    			NameMon, NameQuest, LevelQuest = "Lava Pirate", "FireSideQuest", 2;
    			CFrameQuest = CFrame.new(- 5428.03174, 15.0622921, - 5299.43457, - 0.882952213, 0, 0.469463557, 0, 1, 0, - 0.469463557, 0, - 0.882952213)
    			CFrameMon = CFrame.new(- 5213.33154296875, 49.73788070678711, - 4701.451171875)
    		elseif MyLevel == 1250 or MyLevel <= 1274 then
    			NameMon, NameQuest, LevelQuest = "Ship Deckhand", "ShipQuest1", 1;
    			CFrameQuest = CFrame.new(1037.80127, 125.092171, 32911.6016)
    			CFrameMon = CFrame.new(1212.0111083984375, 150.79205322265625, 33059.24609375)
    			Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125)
    		elseif MyLevel == 1275 or MyLevel <= 1299 then
    			NameMon, NameQuest, LevelQuest = "Ship Engineer", "ShipQuest1", 2;
    			CFrameQuest = CFrame.new(1037.80127, 125.092171, 32911.6016)
    			CFrameMon = CFrame.new(919.4786376953125, 43.54401397705078, 32779.96875)
    			Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125)
    		elseif MyLevel == 1300 or MyLevel <= 1324 then
    			NameMon, NameQuest, LevelQuest = "Ship Steward", "ShipQuest2", 1;
    			CFrameQuest = CFrame.new(968.80957, 125.092171, 33244.125)
    			CFrameMon = CFrame.new(919.4385375976562, 129.55599975585938, 33436.03515625)
    			Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125)
    		elseif MyLevel == 1325 or MyLevel <= 1349 then
    			NameMon, NameQuest, LevelQuest = "Ship Officer", "ShipQuest2", 2;
    			CFrameQuest = CFrame.new(968.80957, 125.092171, 33244.125)
    			CFrameMon = CFrame.new(1036.0179443359375, 181.4390411376953, 33315.7265625)
    			Entrance=Vector3.new(923.21252441406, 126.9760055542, 32852.83203125)
    		elseif MyLevel == 1350 or MyLevel <= 1374 then
    			NameMon, NameQuest, LevelQuest = "Arctic Warrior", "FrostQuest", 1;
    			CFrameQuest = CFrame.new(5667.6582, 26.7997818, - 6486.08984, - 0.933587909, 0, - 0.358349502, 0, 1, 0, 0.358349502, 0, - 0.933587909)
    			CFrameMon = CFrame.new(5966.24609375, 62.97002029418945, - 6179.3828125)
    			Entrance=Vector3.new(- 6508.5581054688, 5000.034996032715, - 132.83953857422)
    		elseif MyLevel == 1375 or MyLevel <= 1424 then
    			NameMon, NameQuest, LevelQuest = "Snow Lurker", "FrostQuest", 2;
    			CFrameQuest = CFrame.new(5667.6582, 26.7997818, - 6486.08984, - 0.933587909, 0, - 0.358349502, 0, 1, 0, 0.358349502, 0, - 0.933587909)
    			CFrameMon = CFrame.new(5407.07373046875, 69.19437408447266, - 6880.88037109375)
    		elseif MyLevel == 1425 or MyLevel <= 1449 then
    			NameMon, NameQuest, LevelQuest = "Sea Soldier", "ForgottenQuest", 1;
    			CFrameQuest = CFrame.new(- 3054.44458, 235.544281, - 10142.8193, 0.990270376, - 0, - 0.13915664, 0, 1, - 0, 0.13915664, 0, 0.990270376)
    			CFrameMon = CFrame.new(- 3028.2236328125, 64.67451477050781, - 9775.4267578125)
    		elseif MyLevel >= 1450 then
    			NameMon, NameQuest, LevelQuest = "Water Fighter", "ForgottenQuest", 2;
    			CFrameQuest = CFrame.new(- 3054.44458, 235.544281, - 10142.8193, 0.990270376, - 0, - 0.13915664, 0, 1, - 0, 0.13915664, 0, 0.990270376)
    			CFrameMon = CFrame.new(- 3352.9013671875, 285.01556396484375, - 10534.841796875)
    		end
    	elseif L_25_ then
    		if MyLevel == 1500 or MyLevel <= 1524 then
    			NameMon, NameQuest, LevelQuest = "Pistol Millionaire", "PiratePortQuest", 1;
    			CFrameQuest = CFrame.new(- 290.074677, 42.9034653, 5581.58984, 0.965929627, - 0, - 0.258804798, 0, 1, - 0, 0.258804798, 0, 0.965929627)
    			CFrameMon = CFrame.new(- 245.9963836669922, 47.30615234375, 5584.1005859375)
    		elseif MyLevel == 1525 or MyLevel <= 1574 then
    			NameMon, NameQuest, LevelQuest = "Pistol Billionaire", "PiratePortQuest", 2;
    			CFrameQuest = CFrame.new(- 290.074677, 42.9034653, 5581.58984, 0.965929627, - 0, - 0.258804798, 0, 1, - 0, 0.258804798, 0, 0.965929627)
    			CFrameMon = CFrame.new(- 187.3301544189453, 86.23987579345703, 6013.513671875)
    		elseif MyLevel == 1575 or MyLevel <= 1599 then
    			NameMon, NameQuest, LevelQuest = "Dragon Crew Warrior", "AmazonQuest", 1;
    			CFrameQuest = CFrame.new(6736.32958984375, 127.4482192993164, - 712.3320922851562)
    			CFrameMon = CFrame.new(7014.84765625, 196.3662567138672, - 1024.2913818359375)
    		elseif MyLevel == 1600 or MyLevel <= 1624 then
    			NameMon, NameQuest, LevelQuest = "Dragon Crew Archer", "AmazonQuest", 2;
    			CFrameQuest = CFrame.new(6736.32958984375, 127.4482192993164, - 712.3320922851562)
    			CFrameMon = CFrame.new(6792.60302734375, 535.4273681640625, 454.4717102050781)
    		elseif MyLevel == 1625 or MyLevel <= 1649 then
    			NameMon, NameQuest, LevelQuest = "Hydra Enforcer", "AmazonQuest2", 1;
    			CFrameQuest = CFrame.new(5210.87353515625, 1004.1356811523438, 755.8411254882812)
    			CFrameMon = CFrame.new(4704.02099609375, 1043.867431640625, 679.615966796875)
    		elseif MyLevel == 1650 or MyLevel <= 1699 then
    			NameMon, NameQuest, LevelQuest = "Venomous Assailant", "AmazonQuest2", 2;
    			CFrameQuest = CFrame.new(5210.87353515625, 1004.1356811523438, 755.8411254882812)
    			CFrameMon = CFrame.new(4731.27197265625, 1090.177978515625, 1078.1712646484375)
    		elseif MyLevel == 1700 or MyLevel <= 1724 then
    			NameMon, NameQuest, LevelQuest = "Marine Commodore", "MarineTreeIsland", 1;
    			CFrameQuest = CFrame.new(2180.54126, 27.8156815, - 6741.5498, - 0.965929747, 0, 0.258804798, 0, 1, 0, - 0.258804798, 0, - 0.965929747)
    			CFrameMon = CFrame.new(2286.0078125, 73.13391876220703, - 7159.80908203125)
    		elseif MyLevel == 1725 or MyLevel <= 1774 then
    			NameMon, NameQuest, LevelQuest = "Marine Rear Admiral", "MarineTreeIsland", 2;
    			CFrameQuest = CFrame.new(2179.98828125, 28.731239318848, - 6740.0551757813)
    			CFrameMon = CFrame.new(3656.773681640625, 160.52406311035156, - 7001.5986328125)
    		elseif MyLevel == 1775 or MyLevel <= 1799 then
    			NameMon, NameQuest, LevelQuest = "Fishman Raider", "DeepForestIsland3", 1;
    			CFrameQuest = CFrame.new(- 10581.6563, 330.872955, - 8761.18652, - 0.882952213, 0, 0.469463557, 0, 1, 0, - 0.469463557, 0, - 0.882952213)
    			CFrameMon = CFrame.new(- 10407.5263671875, 331.76263427734375, - 8368.5166015625)
    		elseif MyLevel == 1800 or MyLevel <= 1824 then
    			NameMon, NameQuest, LevelQuest = "Fishman Captain", "DeepForestIsland3", 2;
    			CFrameQuest = CFrame.new(- 10581.6563, 330.872955, - 8761.18652, - 0.882952213, 0, 0.469463557, 0, 1, 0, - 0.469463557, 0, - 0.882952213)
    			CFrameMon = CFrame.new(- 10994.701171875, 352.38140869140625, - 9002.1103515625)
    		elseif MyLevel == 1825 or MyLevel <= 1849 then
    			NameMon, NameQuest, LevelQuest = "Forest Pirate", "DeepForestIsland", 1;
    			CFrameQuest = CFrame.new(- 13234.04, 331.488495, - 7625.40137, 0.707134247, - 0, - 0.707079291, 0, 1, - 0, 0.707079291, 0, 0.707134247)
    			CFrameMon = CFrame.new(- 13274.478515625, 332.3781433105469, - 7769.58056640625)
    		elseif MyLevel == 1850 or MyLevel <= 1899 then
    			NameMon, NameQuest, LevelQuest = "Mythological Pirate", "DeepForestIsland", 2;
    			CFrameQuest = CFrame.new(- 13234.04, 331.488495, - 7625.40137, 0.707134247, - 0, - 0.707079291, 0, 1, - 0, 0.707079291, 0, 0.707134247)
    			CFrameMon = CFrame.new(- 13680.607421875, 501.08154296875, - 6991.189453125)
    		elseif MyLevel == 1900 or MyLevel <= 1924 then
    			NameMon, NameQuest, LevelQuest = "Jungle Pirate", "DeepForestIsland2", 1;
    			CFrameQuest = CFrame.new(- 12680.3818, 389.971039, - 9902.01953, - 0.0871315002, 0, 0.996196866, 0, 1, 0, - 0.996196866, 0, - 0.0871315002)
    			CFrameMon = CFrame.new(- 12256.16015625, 331.73828125, - 10485.8369140625)
    		elseif MyLevel == 1925 or MyLevel <= 1974 then
    			NameMon, NameQuest, LevelQuest = "Musketeer Pirate", "DeepForestIsland2", 2;
    			CFrameQuest = CFrame.new(- 12680.3818, 389.971039, - 9902.01953, - 0.0871315002, 0, 0.996196866, 0, 1, 0, - 0.996196866, 0, - 0.0871315002)
    			CFrameMon = CFrame.new(- 13457.904296875, 391.545654296875, - 9859.177734375)
    		elseif MyLevel == 1975 or MyLevel <= 1999 then
    			NameMon, NameQuest, LevelQuest = "Reborn Skeleton", "HauntedQuest1", 1;
    			CFrameQuest = CFrame.new(- 9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, - 0, - 1, 0, 0)
    			CFrameMon = CFrame.new(- 8763.7236328125, 165.72299194335938, 6159.86181640625)
    		elseif MyLevel == 2000 or MyLevel <= 2024 then
    			NameMon, NameQuest, LevelQuest = "Living Zombie", "HauntedQuest1", 2;
    			CFrameQuest = CFrame.new(- 9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, - 0, - 1, 0, 0)
    			CFrameMon = CFrame.new(- 10144.1318359375, 138.62667846679688, 5838.0888671875)
    		elseif MyLevel == 2025 or MyLevel <= 2049 then
    			NameMon, NameQuest, LevelQuest = "Demonic Soul", "HauntedQuest2", 1;
    			CFrameQuest = CFrame.new(- 9516.99316, 172.017181, 6078.46533, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 9505.8720703125, 172.10482788085938, 6158.9931640625)
    		elseif MyLevel == 2050 or MyLevel <= 2074 then
    			NameMon, NameQuest, LevelQuest = "Posessed Mummy", "HauntedQuest2", 2;
    			CFrameQuest = CFrame.new(- 9516.99316, 172.017181, 6078.46533, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 9582.0224609375, 6.251527309417725, 6205.478515625)
    		elseif MyLevel == 2075 or MyLevel <= 2099 then
    			NameMon, NameQuest, LevelQuest = "Peanut Scout", "NutsIslandQuest", 1;
    			CFrameQuest = CFrame.new(- 2104.3908691406, 38.104167938232, - 10194.21875, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 2143.241943359375, 47.72198486328125, - 10029.9951171875)
    		elseif MyLevel == 2100 or MyLevel <= 2124 then
    			NameMon, NameQuest, LevelQuest = "Peanut President", "NutsIslandQuest", 2;
    			CFrameQuest = CFrame.new(- 2104.3908691406, 38.104167938232, - 10194.21875, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 1859.35400390625, 38.10316848754883, - 10422.4296875)
    		elseif MyLevel == 2125 or MyLevel <= 2149 then
    			NameMon, NameQuest, LevelQuest = "Ice Cream Chef", "IceCreamIslandQuest", 1;
    			CFrameQuest = CFrame.new(- 820.64825439453, 65.819526672363, - 10965.795898438, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 872.24658203125, 65.81957244873047, - 10919.95703125)
    		elseif MyLevel == 2150 or MyLevel <= 2199 then
    			NameMon, NameQuest, LevelQuest = "Ice Cream Commander", "IceCreamIslandQuest", 2;
    			CFrameQuest = CFrame.new(- 820.64825439453, 65.819526672363, - 10965.795898438, 0, 0, - 1, 0, 1, 0, 1, 0, 0)
    			CFrameMon = CFrame.new(- 558.06103515625, 112.04895782470703, - 11290.7744140625)
    		elseif MyLevel == 2200 or MyLevel <= 2224 then
    			NameMon, NameQuest, LevelQuest = "Cookie Crafter", "CakeQuest1", 1;
    			CFrameQuest = CFrame.new(- 2021.32007, 37.7982254, - 12028.7295, 0.957576931, - 8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, - 0.288177818, - 5.2032135e-08, 0.957576931)
    			CFrameMon = CFrame.new(- 2374.13671875, 37.79826354980469, - 12125.30859375)
    		elseif MyLevel == 2225 or MyLevel <= 2249 then
    			NameMon, NameQuest, LevelQuest = "Cake Guard", "CakeQuest1", 2;
    			CFrameQuest = CFrame.new(- 2021.32007, 37.7982254, - 12028.7295, 0.957576931, - 8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, - 0.288177818, - 5.2032135e-08, 0.957576931)
    			CFrameMon = CFrame.new(- 1598.3070068359375, 43.773197174072266, - 12244.5810546875)
    		elseif MyLevel == 2250 or MyLevel <= 2274 then
    			NameMon, NameQuest, LevelQuest = "Baking Staff", "CakeQuest2", 1;
    			CFrameQuest = CFrame.new(- 1927.91602, 37.7981339, - 12842.5391, - 0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, - 0.250778586, 2.64211941e-08, - 0.96804446)
    			CFrameMon = CFrame.new(- 1887.8099365234375, 77.6185073852539, - 12998.3505859375)
    		elseif MyLevel == 2275 or MyLevel <= 2299 then
    			NameMon, NameQuest, LevelQuest = "Head Baker", "CakeQuest2", 2;
    			CFrameQuest = CFrame.new(- 1927.91602, 37.7981339, - 12842.5391, - 0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, - 0.250778586, 2.64211941e-08, - 0.96804446)
    			CFrameMon = CFrame.new(- 2216.188232421875, 82.884521484375, - 12869.2939453125)
    		elseif MyLevel == 2300 or MyLevel <= 2324 then
    			NameMon, NameQuest, LevelQuest = "Cocoa Warrior", "ChocQuest1", 1;
    			CFrameQuest = CFrame.new(233.22836303710938, 29.876001358032227, - 12201.2333984375)
    			CFrameMon = CFrame.new(- 21.55328369140625, 80.57499694824219, - 12352.3876953125)
    		elseif MyLevel == 2325 or MyLevel <= 2349 then
    			NameMon, NameQuest, LevelQuest = "Chocolate Bar Battler", "ChocQuest1", 2;
    			CFrameQuest = CFrame.new(233.22836303710938, 29.876001358032227, - 12201.2333984375)
    			CFrameMon = CFrame.new(582.590576171875, 77.18809509277344, - 12463.162109375)
    		elseif MyLevel == 2350 or MyLevel <= 2374 then
    			NameMon, NameQuest, LevelQuest = "Sweet Thief", "ChocQuest2", 1;
    			CFrameQuest = CFrame.new(150.5066375732422, 30.693693161010742, - 12774.5029296875)
    			CFrameMon = CFrame.new(165.1884765625, 76.05885314941406, - 12600.8369140625)
    		elseif MyLevel == 2375 or MyLevel <= 2399 then
    			NameMon, NameQuest, LevelQuest = "Candy Rebel", "ChocQuest2", 2;
    			CFrameQuest = CFrame.new(150.5066375732422, 30.693693161010742, - 12774.5029296875)
    			CFrameMon = CFrame.new(134.86563110351562, 77.2476806640625, - 12876.5478515625)
    		elseif MyLevel == 2400 or MyLevel <= 2449 then
    			NameMon, NameQuest, LevelQuest = "Candy Pirate", "CandyQuest1", 1;
    			CFrameQuest = CFrame.new(- 1150.0400390625, 20.378934860229492, - 14446.3349609375)
    			CFrameMon = CFrame.new(- 1310.5003662109375, 26.016523361206055, - 14562.404296875)
    		elseif MyLevel == 2425 or MyLevel <= 2450 then
    			NameMon, NameQuest, LevelQuest = "Snow Demon", "CandyQuest1", 2;
    			CFrameQuest = CFrame.new(- 1150.0400390625, 20.378934860229492, - 14446.3349609375)
    			CFrameMon = CFrame.new(- 750.1473388671875, 15.250883102416992, - 14343.2578125)
    		elseif MyLevel == 2450 or MyLevel <= 2475 then
    			NameMon, NameQuest, LevelQuest = "Isle Outlaw", "TikiQuest1", 1;
    			CFrameQuest = CFrame.new(- 16547.45703125, 56.00029754638672, - 174.1670684814453)
    			CFrameMon = CFrame.new(- 16303.1435546875, 188.16168212890625, - 268.9233703613281)
    		elseif MyLevel == 2475 or MyLevel <= 2525 then
    			NameMon, NameQuest, LevelQuest = "Island Boy", "TikiQuest1", 2;
    			CFrameQuest = CFrame.new(- 16547.45703125, 56.00029754638672, - 174.1670684814453)
    			CFrameMon = CFrame.new(- 16303.1435546875, 188.16168212890625, - 268.9233703613281)
    		elseif MyLevel == 2525 or MyLevel <= 2550 then
    			NameMon, NameQuest, LevelQuest = "Isle Champion", "TikiQuest2", 2;
    			CFrameQuest = CFrame.new(- 16523.0996, 55.9234467, 1049.65784, - 0.418787986, - 0.0126074236, 0.907996595, - 0.0160101596, 0.99985069, 0.00649857335, - 0.907942891, - 0.0118156485, - 0.418927342)
    			CFrameMon = CFrame.new(- 16748.4609375, 94.38502502441406, 1129.7178955078125)
    		elseif MyLevel >= 2551 and MyLevel <= 2600 then
    			NameMon, NameQuest, LevelQuest = "Serpent Hunter", "TikiQuest3", 1;
    			CFrameQuest = CFrame.new(- 16665.462890625, 105.3105697631836, 1577.8289794921875)
    			CFrameMon = CFrame.new(- 16959.2734375, 110.61740112304688, 1669.6007080078125)
    		end
    	end
        if not NameMon or not CFrameQuest or not CFrameMon then return nil end
        return {Mob=NameMon, Name=NameQuest, Tier=LevelQuest, Quest=CFrameQuest, Spawn=CFrameMon, Entrance=Entrance}
    end
    
    local function bossForName(selected)
        local MsBoss, NameBoss, CFrameBoss, NameQuestBoss, LevelQuestBoss, CFrameQuestBoss
    	if selected == "Saber Expert" then
    		MsBoss = "Saber Expert"
    		NameBoss = "Saber Expert"
    		CFrameBoss = CFrame.new(- 1458.89502, 29.8870335, - 50.633564, 0.858821094, 1.13848939e-08, 0.512275636, - 4.85649254e-09, 1, - 1.40823326e-08, - 0.512275636, 9.6063415e-09, 0.858821094)
    	elseif selected == "The Saw" then
    		MsBoss = "The Saw"
    		NameBoss = "The Saw"
    		CFrameBoss = CFrame.new(- 683.519897, 13.8534927, 1610.87854, - 0.290192783, 6.88365773e-08, 0.956968188, 6.98413629e-08, 1, - 5.07531119e-08, - 0.956968188, 5.21077759e-08, - 0.290192783)
    	elseif selected == "Greybeard" then
    		MsBoss = "Greybeard"
    		NameBoss = "Greybeard"
    		CFrameBoss = CFrame.new(- 4955.72949, 80.8163834, 4305.82666, - 0.433646321, - 1.03394289e-08, 0.901083171, - 3.0443168e-08, 1, - 3.17633075e-09, - 0.901083171, - 2.88092288e-08, - 0.433646321)
    	elseif selected == "The Gorilla King" then
    		MsBoss = "The Gorilla King"
    		NameBoss = "The Gorilla King"
    		NameQuestBoss = "JungleQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 1604.12012, 36.8521118, 154.23732, 0.0648873374, - 4.70858913e-06, - 0.997892559, 1.41431883e-07, 1, - 4.70933674e-06, 0.997892559, 1.64442184e-07, 0.0648873374)
    		CFrameBoss = CFrame.new(- 1223.52808, 6.27936459, - 502.292664, 0.310949147, - 5.66602516e-08, 0.950426519, - 3.37275488e-08, 1, 7.06501808e-08, - 0.950426519, - 5.40241736e-08, 0.310949147)
    	elseif selected == "Bobby" then
    		MsBoss = "Bobby"
    		NameBoss = "Bobby"
    		NameQuestBoss = "BuggyQuest1"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 1139.59717, 4.75205183, 3825.16211, - 0.959730506, - 7.5857054e-09, 0.280922383, - 4.06310328e-08, 1, - 1.11807175e-07, - 0.280922383, - 1.18718916e-07, - 0.959730506)
    		CFrameBoss = CFrame.new(- 1147.65173, 32.5966301, 4156.02588, 0.956680477, - 1.77109952e-10, - 0.29113996, 5.16530874e-10, 1, 1.08897802e-09, 0.29113996, - 1.19218679e-09, 0.956680477)
    	elseif selected == "Yeti" then
    		MsBoss = "Yeti"
    		NameBoss = "Yeti"
    		NameQuestBoss = "SnowQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(1384.90247, 87.3078308, - 1296.6825, 0.280209213, 2.72035177e-08, - 0.959938943, - 6.75690828e-08, 1, 8.6151708e-09, 0.959938943, 6.24481444e-08, 0.280209213)
    		CFrameBoss = CFrame.new(1221.7356, 138.046906, - 1488.84082, 0.349343032, - 9.49245944e-08, 0.936994851, 6.29478194e-08, 1, 7.7838429e-08, - 0.936994851, 3.17894653e-08, 0.349343032)
    	elseif selected == "Mob Leader" then
    		MsBoss = "Mob Leader"
    		NameBoss = "Mob Leader"
    		CFrameBoss = CFrame.new(- 2848.59399, 7.4272871, 5342.44043, - 0.928248107, - 8.7248246e-08, 0.371961564, - 7.61816636e-08, 1, 4.44474857e-08, - 0.371961564, 1.29216433e-08, - 0.92824)
    	elseif selected == "Vice Admiral" then
    		MsBoss = "Vice Admiral"
    		NameBoss = "Vice Admiral"
    		NameQuestBoss = "MarineQuest2"
    		LevelQuestBoss = 2;
    		CFrameQuestBoss = CFrame.new(- 5035.42285, 28.6520386, 4324.50293, - 0.0611100644, - 8.08395768e-08, 0.998130739, - 1.57416586e-08, 1, 8.00271849e-08, - 0.998130739, - 1.08217701e-08, - 0.0611100644)
    		CFrameBoss = CFrame.new(- 5078.45898, 99.6520691, 4402.1665, - 0.555574954, - 9.88630566e-11, 0.831466436, - 6.35508286e-08, 1, - 4.23449258e-08, - 0.831466436, - 7.63661632e-08, - 0.555574954)
    	elseif selected == "Warden" then
    		MsBoss = "Warden"
    		NameBoss = "Warden"
    		NameQuestBoss = "ImpelQuest"
    		LevelQuestBoss = 1;
    		CFrameQuestBoss = CFrame.new(4851.35059, 5.68744135, 743.251282, - 0.538484037, - 6.68303741e-08, - 0.842635691, 1.38001752e-08, 1, - 8.81300792e-08, 0.842635691, - 5.90851599e-08, - 0.538484037)
    		CFrameBoss = CFrame.new(5232.5625, 5.26856995, 747.506897, 0.943829298, - 4.5439414e-08, 0.330433697, 3.47818627e-08, 1, 3.81658154e-08, - 0.330433697, - 2.45289105e-08, 0.943829298)
    	elseif selected == "Chief Warden" then
    		MsBoss = "Chief Warden"
    		NameBoss = "Chief Warden"
    		NameQuestBoss = "ImpelQuest"
    		LevelQuestBoss = 2;
    		CFrameQuestBoss = CFrame.new(4851.35059, 5.68744135, 743.251282, - 0.538484037, - 6.68303741e-08, - 0.842635691, 1.38001752e-08, 1, - 8.81300792e-08, 0.842635691, - 5.90851599e-08, - 0.538484037)
    		CFrameBoss = CFrame.new(5232.5625, 5.26856995, 747.506897, 0.943829298, - 4.5439414e-08, 0.330433697, 3.47818627e-08, 1, 3.81658154e-08, - 0.330433697, - 2.45289105e-08, 0.943829298)
    	elseif selected == "Swan" then
    		MsBoss = "Swan"
    		NameBoss = "Swan"
    		NameQuestBoss = "ImpelQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(4851.35059, 5.68744135, 743.251282, - 0.538484037, - 6.68303741e-08, - 0.842635691, 1.38001752e-08, 1, - 8.81300792e-08, 0.842635691, - 5.90851599e-08, - 0.538484037)
    		CFrameBoss = CFrame.new(5232.5625, 5.26856995, 747.506897, 0.943829298, - 4.5439414e-08, 0.330433697, 3.47818627e-08, 1, 3.81658154e-08, - 0.330433697, - 2.45289105e-08, 0.943829298)
    	elseif selected == "Magma Admiral" then
    		MsBoss = "Magma Admiral"
    		NameBoss = "Magma Admiral"
    		NameQuestBoss = "MagmaQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 5317.07666, 12.2721891, 8517.41699, 0.51175487, - 2.65508806e-08, - 0.859131515, - 3.91131572e-08, 1, - 5.42026761e-08, 0.859131515, 6.13418294e-08, 0.51175487)
    		CFrameBoss = CFrame.new(- 5530.12646, 22.8769703, 8859.91309, 0.857838571, 2.23414389e-08, 0.513919294, 1.53689133e-08, 1, - 6.91265853e-08, - 0.513919294, 6.71978384e-08, 0.857838571)
    	elseif selected == "Fishman Lord" then
    		MsBoss = "Fishman Lord"
    		NameBoss = "Fishman Lord"
    		NameQuestBoss = "FishmanQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(61123.0859, 18.5066795, 1570.18018, 0.927145958, 1.0624845e-07, 0.374700129, - 6.98219367e-08, 1, - 1.10790765e-07, - 0.374700129, 7.65569368e-08, 0.927145958)
    		CFrameBoss = CFrame.new(61351.7773, 31.0306778, 1113.31409, 0.999974668, 0, - 0.00714713801, 0, 1.00000012, 0, 0.00714714266, 0, 0.999974549)
    	elseif selected == "Wysper" then
    		MsBoss = "Wysper"
    		NameBoss = "Wysper"
    		NameQuestBoss = "SkyExp1Quest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 7862.94629, 5545.52832, - 379.833954, 0.462944925, 1.45838088e-08, - 0.886386991, 1.0534996e-08, 1, 2.19553424e-08, 0.886386991, - 1.95022007e-08, 0.462944925)
    		CFrameBoss = CFrame.new(- 7925.48389, 5550.76074, - 636.178345, 0.716468513, - 1.22915289e-09, 0.697619379, 3.37381434e-09, 1, - 1.70304748e-09, - 0.697619379, 3.57381835e-09, 0.716468513)
    	elseif selected == "Thunder God" then
    		MsBoss = "Thunder God"
    		NameBoss = "Thunder God"
    		NameQuestBoss = "SkyExp2Quest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 7902.78613, 5635.99902, - 1411.98706, - 0.0361216255, - 1.16895912e-07, 0.999347389, 1.44533963e-09, 1, 1.17024491e-07, - 0.999347389, 5.6715117e-09, - 0.0361216255)
    		CFrameBoss = CFrame.new(- 7917.53613, 5616.61377, - 2277.78564, 0.965189934, 4.80563429e-08, - 0.261550069, - 6.73089886e-08, 1, - 6.46515304e-08, 0.261550069, 8.00056768e-08, 0.965189934)
    	elseif selected == "Cyborg" then
    		MsBoss = "Cyborg"
    		NameBoss = "Cyborg"
    		NameQuestBoss = "FountainQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(5253.54834, 38.5361786, 4050.45166, - 0.0112687312, - 9.93677887e-08, - 0.999936521, 2.55291371e-10, 1, - 9.93769547e-08, 0.999936521, - 1.37512213e-09, - 0.0112687312)
    		CFrameBoss = CFrame.new(6041.82813, 52.7112198, 3907.45142, - 0.563162148, 1.73805248e-09, - 0.826346457, - 5.94632716e-08, 1, 4.26280238e-08, 0.826346457, 7.31437524e-08, - 0.563162148)
    	elseif selected == "Diamond" then
    		MsBoss = "Diamond"
    		NameBoss = "Diamond"
    		NameQuestBoss = "Area1Quest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 424.080078, 73.0055847, 1836.91589, 0.253544956, - 1.42165932e-08, 0.967323601, - 6.00147771e-08, 1, 3.04272909e-08, - 0.967323601, - 6.5768397e-08, 0.253544956)
    		CFrameBoss = CFrame.new(- 1736.26587, 198.627731, - 236.412857, - 0.997808516, 0, - 0.0661673471, 0, 1, 0, 0.0661673471, 0, - 0.997808516)
    	elseif selected == "Jeremy" then
    		MsBoss = "Jeremy"
    		NameBoss = "Jeremy"
    		NameQuestBoss = "Area2Quest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(632.698608, 73.1055908, 918.666321, - 0.0319722369, 8.96074881e-10, - 0.999488771, 1.36326533e-10, 1, 8.92172336e-10, 0.999488771, - 1.07732087e-10, - 0.0319722369)
    		CFrameBoss = CFrame.new(2203.76953, 448.966034, 752.731079, - 0.0217453763, 0, - 0.999763548, 0, 1, 0, 0.999763548, 0, - 0.0217453763)
    	elseif selected == "Fajita" then
    		MsBoss = "Fajita"
    		NameBoss = "Fajita"
    		NameQuestBoss = "MarineQuest3"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 2442.65015, 73.0511475, - 3219.11523, - 0.873540044, 4.2329841e-08, - 0.486752301, 5.64383384e-08, 1, - 1.43220786e-08, 0.486752301, - 3.99823996e-08, - 0.873540044)
    		CFrameBoss = CFrame.new(- 2297.40332, 115.449463, - 3946.53833, 0.961227536, - 1.46645796e-09, - 0.275756449, - 2.3212845e-09, 1, - 1.34094433e-08, 0.275756449, 1.35296352e-08, 0.961227536)
    	elseif selected == "Don Swan" then
    		MsBoss = "Don Swan"
    		NameBoss = "Don Swan"
    		CFrameBoss = CFrame.new(2288.802, 15.1870775, 863.034607, 0.99974072, - 8.41247214e-08, - 0.0227668174, 8.4774733e-08, 1, 2.75850098e-08, 0.0227668174, - 2.95079072e-08, 0.99974072)
    	elseif selected == "Smoke Admiral" then
    		MsBoss = "Smoke Admiral"
    		NameBoss = "Smoke Admiral"
    		NameQuestBoss = "IceSideQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 6059.96191, 15.9868021, - 4904.7373, - 0.444992423, - 3.0874483e-09, 0.895534337, - 3.64098796e-08, 1, - 1.4644522e-08, - 0.895534337, - 3.91229982e-08, - 0.444992423)
    		CFrameBoss = CFrame.new(- 5115.72754, 23.7664986, - 5338.2207, 0.251453817, 1.48345061e-08, - 0.967869282, 4.02796978e-08, 1, 2.57916977e-08, 0.967869282, - 4.54708946e-08, 0.251453817)
    	elseif selected == "Cursed Captain" then
    		MsBoss = "Cursed Captain"
    		NameBoss = "Cursed Captain"
    		CFrameBoss = CFrame.new(916.928589, 181.092773, 33422, - 0.999505103, 9.26310495e-09, 0.0314563364, 8.42916226e-09, 1, - 2.6643713e-08, - 0.0314563364, - 2.63653774e-08, - 0.999505103)
    	elseif selected == "Darkbeard" then
    		MsBoss = "Darkbeard"
    		NameBoss = "Darkbeard"
    		CFrameBoss = CFrame.new(3876.00366, 24.6882591, - 3820.21777, - 0.976951957, 4.97356325e-08, 0.213458836, 4.57335361e-08, 1, - 2.36868622e-08, - 0.213458836, - 1.33787044e-08, - 0.976951957)
    	elseif selected == "Order" then
    		MsBoss = "Order"
    		NameBoss = "Order"
    		CFrameBoss = CFrame.new(- 6221.15039, 16.2351036, - 5045.23584, - 0.380726993, 7.41463495e-08, 0.924687505, 5.85604774e-08, 1, - 5.60738549e-08, - 0.924687505, 3.28013137e-08, - 0.380726993)
    	elseif selected == "Awakened Ice Admiral" then
    		MsBoss = "Awakened Ice Admiral"
    		NameBoss = "Awakened Ice Admiral"
    		NameQuestBoss = "FrostQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(5669.33203, 28.2118053, - 6481.55908, 0.921275556, - 1.25320829e-08, 0.388910472, 4.72230788e-08, 1, - 7.96414241e-08, - 0.388910472, 9.17372489e-08, 0.921275556)
    		CFrameBoss = CFrame.new(6407.33936, 340.223785, - 6892.521, 0.49051559, - 5.25310213e-08, - 0.871432424, - 2.76146022e-08, 1, - 7.58250565e-08, 0.871432424, 6.12576301e-08, 0.49051559)
    	elseif selected == "Tide Keeper" then
    		MsBoss = "Tide Keeper"
    		NameBoss = "Tide Keeper"
    		NameQuestBoss = "ForgottenQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 3053.89648, 236.881363, - 10148.2324, - 0.985987961, - 3.58504737e-09, 0.16681771, - 3.07832915e-09, 1, 3.29612559e-09, - 0.16681771, 2.73641976e-09, - 0.985987961)
    		CFrameBoss = CFrame.new(- 3570.18652, 123.328949, - 11555.9072, 0.465199202, - 1.3857326e-08, 0.885206044, 4.0332897e-09, 1, 1.35347511e-08, - 0.885206044, - 2.72606271e-09, 0.465199202)
    	elseif selected == "Stone" then
    		MsBoss = "Stone"
    		NameBoss = "Stone"
    		NameQuestBoss = "PiratePortQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 290, 44, 5577)
    		CFrameBoss = CFrame.new(- 1085, 40, 6779)
    	elseif selected == "Hydra Leader" then
    		MsBoss = "Hydra Leader"
    		NameBoss = "Hydra Leader"
    		NameQuestBoss = "AmazonQuest2"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(5210.87353515625, 1004.1356811523438, 755.8411254882812)
    		CFrameBoss = CFrame.new(5942.8154296875, 1019.0787353515625, - 116.86933135986328)
    	elseif selected == "Kilo Admiral" then
    		MsBoss = "Kilo Admiral"
    		NameBoss = "Kilo Admiral"
    		NameQuestBoss = "MarineTreeIsland"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(2178, 29, - 6737)
    		CFrameBoss = CFrame.new(2846, 433, - 7100)
    	elseif selected == "Captain Elephant" then
    		MsBoss = "Captain Elephant"
    		NameBoss = "Captain Elephant"
    		NameQuestBoss = "DeepForestIsland"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 13232, 333, - 7631)
    		CFrameBoss = CFrame.new(- 13221, 325, - 8405)
    	elseif selected == "Beautiful Pirate" then
    		MsBoss = "Beautiful Pirate"
    		NameBoss = "Beautiful Pirate"
    		NameQuestBoss = "DeepForestIsland2"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 12686, 391, - 9902)
    		CFrameBoss = CFrame.new(5182, 23, - 20)
    	elseif selected == "Cake Queen" then
    		MsBoss = "Cake Queen"
    		NameBoss = "Cake Queen"
    		NameQuestBoss = "IceCreamIslandQuest"
    		LevelQuestBoss = 3;
    		CFrameQuestBoss = CFrame.new(- 716, 382, - 11010)
    		CFrameBoss = CFrame.new(- 821, 66, - 10965)
    	elseif selected == "rip_indra True Form" then
    		MsBoss = "rip_indra True Form"
    		NameBoss = "rip_indra True Form"
    		CFrameBoss = CFrame.new(- 5359, 424, - 2735)
    	elseif selected == "Longma" then
    		MsBoss = "Longma"
    		NameBoss = "Longma"
    		CFrameBoss = CFrame.new(- 10248.3936, 353.79129, - 9306.34473)
    	elseif selected == "Soul Reaper" then
    		MsBoss = "Soul Reaper"
    		NameBoss = "Soul Reaper"
    		CFrameBoss = CFrame.new(- 9515.62109, 315.925537, 6691.12012)
    	end
        if not CFrameBoss then return nil end
        return {Mob=MsBoss or NameBoss, Name=NameQuestBoss, Tier=LevelQuestBoss, Quest=CFrameQuestBoss, Spawn=CFrameBoss}
    end
    
    local function materialForName(selected)
        local MMon, MPos
    	if selected == "Radioactive Material" then
    		MMon = "Factory Staff"
    		MPos = CFrame.new(- 507.7895202636719, 72.99479675292969, - 126.45632934570312)
    	elseif selected == "Mystic Droplet" then
    		MMon = "Water Fighter"
    		MPos = CFrame.new(- 3214.218017578125, 298.69952392578125, - 10543.685546875)
    	elseif selected == "Magma Ore" then
    		if game.PlaceId == 2753915549 then
    			MMon = "Military Spy"
    			MPos = CFrame.new(- 5850.2802734375, 77.28675079345703, 8848.6748046875)
    		elseif game.PlaceId == 4442272183 then
    			MMon = "Lava Pirate"
    			MPos = CFrame.new(- 5234.60595703125, 51.953372955322266, - 4732.27880859375)
    		end
    	elseif selected == "Angel Wings" then
    		MMon = "Royal Soldier"
    		MPos = CFrame.new(- 7827.15625, 5606.912109375, - 1705.5833740234375)
    	elseif selected == "Leather" then
    		if game.PlaceId == 2753915549 then
    			MMon = "Pirate"
    			MPos = CFrame.new(- 1211.8792724609375, 4.787090301513672, 3916.83056640625)
    		elseif game.PlaceId == 4442272183 then
    			MMon = "Marine Captain"
    			MPos = CFrame.new(- 2010.5059814453125, 73.00115966796875, - 3326.620849609375)
    		elseif game.PlaceId == 7449423635 then
    			MMon = "Jungle Pirate"
    			MPos = CFrame.new(- 11975.78515625, 331.7734069824219, - 10620.0302734375)
    		end
    	elseif selected == "Scrap Metal" then
    		if game.PlaceId == 2753915549 then
    			MMon = "Brute"
    			MPos = CFrame.new(- 1132.4202880859375, 14.844913482666016, 4293.30517578125)
    		elseif game.PlaceId == 4442272183 then
    			MMon = "Mercenary"
    			MPos = CFrame.new(- 972.307373046875, 73.04473876953125, 1419.2901611328125)
    		elseif game.PlaceId == 7449423635 then
    			MMon = "Pirate Millionaire"
    			MPos = CFrame.new(- 289.6311950683594, 43.8282470703125, 5583.66357421875)
    		end
    	elseif selected == "Demonic Wisp" then
    		MMon = "Demonic Soul"
    		MPos = CFrame.new(- 9503.388671875, 172.139892578125, 6143.0634765625)
    	elseif selected == "Vampire Fang" then
    		MMon = "Vampire"
    		MPos = CFrame.new(- 5999.20458984375, 6.437741279602051, - 1290.059326171875)
    	elseif selected == "Conjured Cocoa" then
    		MMon = "Chocolate Bar Battler"
    		MPos = CFrame.new(747.428466796875, 237.9543914794922, - 12700.2041015625)
    	elseif selected == "Dragon Scale" then
    		MMon = "Dragon Crew Warrior"
    		MPos = CFrame.new(5824.06982421875, 51.38640213012695, - 1106.694580078125)
    	elseif selected == "Gunpowder" then
    		MMon = "Pistol Billionaire"
    		MPos = CFrame.new(- 379.6134338378906, 73.84449768066406, 5928.5263671875)
    	elseif selected == "Fish Tail" then
    		MMon = "Fishman Captain"
    		MPos = CFrame.new(- 10961.0126953125, 331.7977600097656, - 8914.29296875)
    	elseif selected == "Mini Tusk" then
    		MMon = "Mythological Pirate"
    		MPos = CFrame.new(- 13516.0458984375, 469.8182373046875, - 6899.16064453125)
    	end
        if MMon and MPos then return {Mob=MMon, Spawn=MPos} end
    end
    
    local materialNames = {"Radioactive Material", "Mystic Droplet", "Magma Ore", "Angel Wings", "Leather", "Scrap Metal", "Demonic Wisp", "Vampire Fang", "Conjured Cocoa", "Dragon Scale", "Gunpowder", "Fish Tail", "Mini Tusk"}
    local bossNames = {"Saber Expert", "The Saw", "Greybeard", "The Gorilla King", "Bobby", "Yeti", "Mob Leader", "Vice Admiral", "Warden", "Chief Warden", "Swan", "Magma Admiral", "Fishman Lord", "Wysper", "Thunder God", "Cyborg", "Diamond", "Jeremy", "Fajita", "Don Swan", "Smoke Admiral", "Cursed Captain", "Darkbeard", "Order", "Awakened Ice Admiral", "Tide Keeper", "Stone", "Hydra Leader", "Kilo Admiral", "Captain Elephant", "Beautiful Pirate", "Cake Queen", "rip_indra True Form", "Longma", "Soul Reaper"}
    local islandData = {
        ["WindMill"] = {Target=CFrame.new(979.79895019531, 16.516613006592, 1429.0466308594), Entrance=false},
        ["Marine"] = {Target=CFrame.new(-2566.4296875, 6.8556680679321, 2045.2561035156), Entrance=false},
        ["Middle Town"] = {Target=CFrame.new(-690.33081054688, 15.09425163269, 1582.2380371094), Entrance=false},
        ["Jungle"] = {Target=CFrame.new(-1612.7957763672, 36.852081298828, 149.12843322754), Entrance=false},
        ["Pirate Village"] = {Target=CFrame.new(-1181.3093261719, 4.7514905929565, 3803.5456542969), Entrance=false},
        ["Desert"] = {Target=CFrame.new(944.15789794922, 20.919729232788, 4373.3002929688), Entrance=false},
        ["Snow Island"] = {Target=CFrame.new(1347.8067626953, 104.66806030273, -1319.7370605469), Entrance=false},
        ["MarineFord"] = {Target=CFrame.new(-4914.8212890625, 50.963626861572, 4281.0278320313), Entrance=false},
        ["Colosseum"] = {Target=CFrame.new(-1427.6203613281, 7.2881078720093, -2792.7722167969), Entrance=false},
        ["Sky Island 1"] = {Target=CFrame.new(-4869.1025390625, 733.46051025391, -2667.0180664063), Entrance=false},
        ["Sky Island 2"] = {Target=CFrame.new(-4607.82275, 872.54248, -1667.55688), Entrance=true},
        ["Sky Island 3"] = {Target=CFrame.new(-7894.6176757813, 5547.1416015625, -380.29119873047), Entrance=true},
        ["Prison"] = {Target=CFrame.new(4875.330078125, 5.6519818305969, 734.85021972656), Entrance=false},
        ["Magma Village"] = {Target=CFrame.new(-5247.7163085938, 12.883934020996, 8504.96875), Entrance=false},
        ["Under Water Island"] = {Target=CFrame.new(61163.8515625, 11.6796875, 1819.7841796875), Entrance=true},
        ["Fountain City"] = {Target=CFrame.new(5127.1284179688, 59.501365661621, 4105.4458007813), Entrance=false},
        ["Shank Room"] = {Target=CFrame.new(-1442.16553, 29.8788261, -28.3547478), Entrance=false},
        ["Mob Island"] = {Target=CFrame.new(-2850.20068, 7.39224768, 5354.99268), Entrance=false},
        ["The Cafe"] = {Target=CFrame.new(-380.47927856445, 77.220390319824, 255.82550048828), Entrance=false},
        ["Frist Spot"] = {Target=CFrame.new(-11.311455726624, 29.276733398438, 2771.5224609375), Entrance=false},
        ["Dark Area"] = {Target=CFrame.new(3780.0302734375, 22.652164459229, -3498.5859375), Entrance=false},
        ["Flamingo Mansion"] = {Target=CFrame.new(-483.73370361328, 332.0383605957, 595.32708740234), Entrance=false},
        ["Flamingo Room"] = {Target=CFrame.new(2284.4140625, 15.152037620544, 875.72534179688), Entrance=false},
        ["Green Zone"] = {Target=CFrame.new(-2448.5300292969, 73.016105651855, -3210.6306152344), Entrance=false},
        ["Factory"] = {Target=CFrame.new(424.12698364258, 211.16171264648, -427.54049682617), Entrance=false},
        ["Colossuim"] = {Target=CFrame.new(-1503.6224365234, 219.7956237793, 1369.3101806641), Entrance=false},
        ["Zombie Island"] = {Target=CFrame.new(-5622.033203125, 492.19604492188, -781.78552246094), Entrance=false},
        ["Two Snow Mountain"] = {Target=CFrame.new(753.14288330078, 408.23559570313, -5274.6147460938), Entrance=false},
        ["Punk Hazard"] = {Target=CFrame.new(-6127.654296875, 15.951762199402, -5040.2861328125), Entrance=false},
        ["Cursed Ship"] = {Target=CFrame.new(923.40197753906, 125.05712890625, 32885.875), Entrance=false},
        ["Ice Castle"] = {Target=CFrame.new(6148.4116210938, 294.38687133789, -6741.1166992188), Entrance=false},
        ["Forgotten Island"] = {Target=CFrame.new(-3032.7641601563, 317.89672851563, -10075.373046875), Entrance=false},
        ["Ussop Island"] = {Target=CFrame.new(4816.8618164063, 8.4599885940552, 2863.8195800781), Entrance=false},
        ["Mini Sky Island"] = {Target=CFrame.new(-288.74060058594, 49326.31640625, -35248.59375), Entrance=false},
        ["Great Tree"] = {Target=CFrame.new(2681.2736816406, 1682.8092041016, -7190.9853515625), Entrance=false},
        ["Castle On The Sea"] = {Target=CFrame.new(-5074.45556640625, 314.5155334472656, -2991.054443359375), Entrance=false},
        ["MiniSky"] = {Target=CFrame.new(-260.65557861328, 49325.8046875, -35253.5703125), Entrance=false},
        ["Port Town"] = {Target=CFrame.new(-290.7376708984375, 6.729952812194824, 5343.5537109375), Entrance=false},
        ["Hydra Island"] = {Target=CFrame.new(5255.1049, 1004.1949, 344.7700), Entrance=false},
        ["Floating Turtle"] = {Target=CFrame.new(-13274.528320313, 531.82073974609, -7579.22265625), Entrance=false},
        ["Mansion"] = {Target=CFrame.new(-12471.169921875, 374.94024658203, -7551.677734375), Entrance=true},
        ["Haunted Castle"] = {Target=CFrame.new(-9515.3720703125, 164.00624084473, 5786.0610351562), Entrance=false},
        ["Ice Cream Island"] = {Target=CFrame.new(-902.56817626953, 79.93204498291, -10988.84765625), Entrance=false},
        ["Peanut Island"] = {Target=CFrame.new(-2062.7475585938, 50.473892211914, -10232.568359375), Entrance=false},
        ["Cake Island"] = {Target=CFrame.new(-1884.7747802734375, 19.327526092529297, -11666.8974609375), Entrance=false},
        ["Cocoa Island"] = {Target=CFrame.new(87.94276428222656, 73.55451202392578, -12319.46484375), Entrance=false},
        ["Candy Island"] = {Target=CFrame.new(-1014.4241943359375, 149.11068725585938, -14555.962890625), Entrance=false},
        ["Tiki Outpost"] = {Target=CFrame.new(-16218.6826, 9.08636189, 445.618408, -0.0610186495, 1.10512588e-09, -0.99813664, -1.83458475e-08, 1, 2.22871765e-09, 0.99813664, 1.84476558e-08, -0.0610186495), Entrance=false},
    }
    local shopData = {
        {Name="Buy Geppo", Calls={{"BuyHaki","Geppo"}}},
        {Name="Buy Buso Haki", Calls={{"BuyHaki","Buso"}}},
        {Name="Buy Soru", Calls={{"BuyHaki","Soru"}}},
        {Name="Buy Observation Haki", Calls={{"KenTalk","Buy"}}},
        {Name="Buy Black Leg", Calls={{"BuyBlackLeg"}}},
        {Name="Buy Electro", Calls={{"BuyElectro"}}},
        {Name="Buy Water Kung Fu", Calls={{"BuyFishmanKarate"}}},
        {Name="Buy Dragon Claw", Calls={{"BlackbeardReward","DragonClaw","1"},{"BlackbeardReward","DragonClaw","2"}}},
        {Name="Buy Superhuman", Calls={{"BuySuperhuman"}}},
        {Name="Buy Death Step", Calls={{"BuyDeathStep"}}},
        {Name="Buy Sharkman Karate", Calls={{"BuySharkmanKarate",true},{"BuySharkmanKarate"}}},
        {Name="Buy Electric Claw", Calls={{"BuyElectricClaw"}}},
        {Name="Buy Dragon Talon", Calls={{"BuyDragonTalon"}}},
        {Name="Buy God Human", Calls={{"BuyGodhuman"}}},
        {Name="Buy Sanguine Art", Calls={{"BuySanguineArt", true},{"BuySanguineArt"}}},
        {Name="Cutlass", Calls={{"BuyItem","Cutlass"}}},
        {Name="Katana", Calls={{"BuyItem","Katana"}}},
        {Name="Iron Mace", Calls={{"BuyItem","Iron Mace"}}},
        {Name="Dual Katana", Calls={{"BuyItem","Dual Katana"}}},
        {Name="Triple Katana", Calls={{"BuyItem","Triple Katana"}}},
        {Name="Pipe", Calls={{"BuyItem","Pipe"}}},
        {Name="Dual-Headed Blade", Calls={{"BuyItem","Dual-Headed Blade"}}},
        {Name="Bisento", Calls={{"BuyItem","Bisento"}}},
        {Name="Soul Cane", Calls={{"BuyItem","Soul Cane"}}},
        {Name="Pole v.2", Calls={{"ThunderGodTalk"}}},
        {Name="Slingshot", Calls={{"BuyItem","Slingshot"}}},
        {Name="Musket", Calls={{"BuyItem","Musket"}}},
        {Name="Flintlock", Calls={{"BuyItem","Flintlock"}}},
        {Name="Refined Slingshot", Calls={{"BuyItem", "Refined Slingshot"}}},
        {Name="Cannon", Calls={{"BuyItem","Cannon"}}},
        {Name="Kabucha", Calls={{"BlackbeardReward","Slingshot","1"},{"BlackbeardReward","Slingshot","2"}}},
        {Name="Reset Stats", Calls={{"BlackbeardReward","Refund","1"},{"BlackbeardReward","Refund","2"}}},
        {Name="Random Race", Calls={{"BlackbeardReward","Reroll","1"},{"BlackbeardReward","Reroll","2"}}},
        {Name="Refined Flintlock", Calls={{"BuyItem", "Refined Flintlock"}}},
        {Name="Black Cape", Calls={{"BuyItem", "Black Cape"}}},
        {Name="Swordsman Hat", Calls={{"BuyItem", "Swordsman Hat"}}},
        {Name="Tomoe Ring", Calls={{"BuyItem", "Tomoe Ring"}}},
        {Name="Bizarre Rifle", Calls={{"Ectoplasm", "Buy", 1}}},
    }
    -- Adapted from Kaitun GetBestQuest/GetQuestPosition and QuestUpdate handling.
    -- Only named in-game modules are consulted; never executes the uploaded script.
    local function initQuestRuntime()
        local cache={}
        local state={Known=false,Active=false,Name=nil,Mob=nil,Modules="not_loaded"}
        local watchedRemote,questConnection
        local excluded={BartiloQuest=true,Trainees=true,MarineQuest=true,CitizenQuest=true}
        local function moduleData(name)
            local module=RS:FindFirstChild(name)
            local entry=cache[name]
            if entry and entry.Module==module and (entry.Data or os.clock()<entry.RetryAt) then return entry.Data end
            entry={Module=module,RetryAt=os.clock()+5}
            cache[name]=entry
            if not module or not module:IsA("ModuleScript") then return nil end
            local ok,data=pcall(require,module)
            if not active or destroyed then return nil end
            if ok and type(data)=="table" then entry.Data=data;return data end
            state.LastError=name..": "..tostring(ok and "unexpected module schema" or data)
            debugLog("WARN","quests.module",state.LastError)
        end
        local function cframeOf(value)
            if typeof(value)=="CFrame" then return value end
            if typeof(value)=="Vector3" then return CFrame.new(value) end
            if typeof(value)=="Instance" then
                if value:IsA("BasePart") then return value.CFrame end
                if value:IsA("Model") then return value:GetPivot() end
            end
        end
        local function referencesQuest(entry,name,depth,visited)
            if type(entry)~="table" or depth>2 or visited[entry] then return false end
            visited[entry]=true
            for _,value in pairs(entry) do
                if value==name then return true end
                if type(value)=="table" and referencesQuest(value,name,depth+1,visited) then return true end
            end
            return false
        end
        local function GetQuestPosition(name)
            if type(name)~="string" or name=="" then return nil end
            local guide=moduleData("GuideModule")
            local list=guide and type(guide.Data)=="table" and guide.Data.NPCList
            if type(list)~="table" then return nil end
            local _,_,root=character()
            local nearestPosition,shortest=nil,math.huge
            for _,entry in pairs(list) do
                if type(entry)=="table" and referencesQuest(entry,name,0,{}) then
                    local position=cframeOf(entry.Position)
                    if position then
                        local d=root and (root.Position-position.Position).Magnitude or 0
                        if d<shortest then nearestPosition,shortest=position,d end
                    end
                end
            end
            return nearestPosition
        end
        local function onQuestUpdate(payload)
            if not active or destroyed then return end
            if payload==nil or payload==false then
                state.Known=true;state.Active=false;state.Name=nil;state.Mob=nil
            elseif type(payload)=="table" and type(payload.Progress)=="table" then
                local mob
                for name in pairs(payload.Progress) do
                    if type(name)=="string" and name~="" and (not mob or name<mob) then mob=name end
                end
                if not mob then
                    state.Known=true;state.Active=false;state.Name=nil;state.Mob=nil
                elseif type(payload.InternalQuestName)=="string" and payload.InternalQuestName~="" then
                    state.Known=true;state.Active=true;state.Name=payload.InternalQuestName;state.Mob=mob
                else
                    debugLog("WARN","quests.event","quest update ignored: missing InternalQuestName")
                    return
                end
            else
                debugLog("WARN","quests.event","unrecognized payload ignored")
                return
            end
            debugLog("INFO","quests.event",state.Active and (state.Name.." / "..state.Mob) or "quest completed/cleared")
        end
        local function observeQuestUpdate()
            local remote=path(RS,"Remotes","QuestUpdate")
            if remote==watchedRemote then return end
            if questConnection then questConnection:Disconnect();questConnection=nil end
            watchedRemote=remote
            state.Known=false;state.Active=false;state.Name=nil;state.Mob=nil
            if remote and remote:IsA("RemoteEvent") then
                questConnection=bind(remote.OnClientEvent,onQuestUpdate,"quests.update")
            end
        end
        local function Refresh()
            observeQuestUpdate()
            local quests=moduleData("Quests")
            local guide=moduleData("GuideModule")
            state.Modules=quests and guide and "available" or "fallback"
            return quests
        end
        local function record(name,tier,mob,definition)
            return {Name=name,Tier=tonumber(tier) or tier,Mob=mob,Quest=GetQuestPosition(name),
                LevelReq=definition and definition.LevelReq,Source="game_modules"}
        end
        local function GetBestQuest()
            local quests=Refresh()
            local value=path(LocalPlayer,"Data","Level")
            local level=value and tonumber(value.Value)
            if not quests or not level then return nil end
            -- In-game tables can contain all seas. Keep selection in the current sea's level band.
            if game.PlaceId==2753915549 then level=math.min(level,699)
            elseif game.PlaceId==4442272183 then level=math.min(level,1499) end
            local best,bestLevel,bestKey=nil,-1,nil
            for name,stages in pairs(quests) do
                if type(name)=="string" and not excluded[name] and type(stages)=="table" then
                    for tier,definition in pairs(stages) do
                        if (type(tier)=="number" or type(tier)=="string") and type(definition)=="table" then
                            local req,tasks=definition.LevelReq,definition.Task
                            if type(req)=="number" and req>=0 and req<=level and type(tasks)=="table" then
                                for mob,count in pairs(tasks) do
                                    if type(mob)=="string" and type(count)=="number" and count>1 and count<math.huge then
                                        local key=name..":"..tostring(tier)..":"..mob
                                        if req>bestLevel or (req==bestLevel and (not bestKey or key<bestKey)) then
                                            best={Name=name,Tier=tonumber(tier) or tier,Mob=mob,LevelReq=req,Source="game_modules"}
                                            bestLevel,bestKey=req,key
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if best then best.Quest=GetQuestPosition(best.Name) end
            return best
        end
        local function GetActiveQuest()
            local quests=Refresh()
            if not state.Known or not state.Active then return nil end
            local stages=quests and quests[state.Name]
            if type(stages)=="table" then
                for tier,definition in pairs(stages) do
                    if type(definition)=="table" and type(definition.Task)=="table" then
                        for mob in pairs(definition.Task) do
                            if type(mob)=="string" and cleanName(mob)==cleanName(state.Mob) then
                                return record(state.Name,tier,mob,definition)
                            end
                        end
                    end
                end
            end
            -- A recognized event still supplies the real current target if module layout changed.
            return {Name=state.Name,Mob=state.Mob,Quest=GetQuestPosition(state.Name),Source="quest_event"}
        end
        table.insert(cleanupFns,function()
            if questConnection then questConnection:Disconnect();questConnection=nil end
            watchedRemote=nil
            table.clear(cache)
        end)
        return {Refresh=Refresh,GetBestQuest=GetBestQuest,GetQuestPosition=GetQuestPosition,
            GetActiveQuest=GetActiveQuest,GetState=function() return table.clone(state) end}
    end
    local questRuntime=initQuestRuntime()
    local modes={"Off","Level","Nearest","Raid","Material","Bone","Cake","Ectoplasm","Elite","Boss","Law","White Belt","Dragon Hunter","Sea Event","Golem","Player"}
    local mobGroups={Bone={"Reborn Skeleton","Living Zombie","Demonic Soul","Posessed Mummy"},
        Cake={"Cookie Crafter","Cake Guard","Baking Staff","Head Baker","Cake Prince","Dough King"},
        Ectoplasm={"Ship Deckhand","Ship Engineer","Ship Steward","Ship Officer","Cursed Captain"},
        Elite={"Deandre","Diablo","Urban"},["White Belt"]={"Serpent Hunter","Skull Slayer"},
        ["Dragon Hunter"]={"Venomous Assailant","Hydra Enforcer"},["Sea Event"]={"Terrorshark","Shark","Piranha","Fish Crew Member"},Golem={"Lava Golem","Ancient Golem"}}
    local function questVisible()
        local q=path(PlayerGui,"Main","Quest")
        return q and q.Visible==true,q
    end
    local farmQuest, farmQuestKey
    local farmQuestSource="legacy_data"
    local farmSpawnSource
    local farmStatus={Phase="idle"}
    local lastFarmLog, lastFarmMessage=0,""
    local function farmProgress(phase,mob,target,destination,title)
        local _,_,root=character()
        local point=part(target)
        farmStatus={Phase=phase,ExpectedMob=mob,Target=target and target.Name or nil,
            Destination=destination and destination.Position or nil,Position=root and root.Position or nil,
            Distance=root and point and (root.Position-point.Position).Magnitude or nil,
            QuestTitle=title,At=os.clock(),QuestSource=farmQuestSource,SpawnSource=farmSpawnSource}
        local message=phase.." | expected="..tostring(mob).." | target="..tostring(farmStatus.Target)
            .." | distance="..tostring(farmStatus.Distance).." | destination="..tostring(farmStatus.Destination)
        local important=phase..":"..tostring(mob)..":"..tostring(farmStatus.Target)
        if debugEnabled and (important~=lastFarmMessage or os.clock()-lastFarmLog>=5) then
            local names={}
            local folder=workspace:FindFirstChild("Enemies")
            if phase=="waiting_spawn" and folder then
                for _,object in ipairs(folder:GetDescendants()) do
                    if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then
                        names[#names+1]=object.Name
                        if #names>=6 then break end
                    end
                end
            end
            debugLog("INFO","farm.progress",message.." | quest="..tostring(title).." | source="..tostring(farmQuestSource).." | spawn="..tostring(farmSpawnSource).." | nearby_names="..table.concat(names,", "))
            lastFarmLog=os.clock();lastFarmMessage=important
        end
    end
    onJobStop.Farm=function() fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil;farmProgress("idle") end
    local function spawnCFrame(object)
        if object:IsA("BasePart") then return object.CFrame end
        if object:IsA("Model") then
            local ok,pivot=pcall(function() return object:GetPivot() end)
            if ok and typeof(pivot)=="CFrame" then return pivot end
        end
        if object:IsA("Attachment") then return object.WorldCFrame end
    end
    local function liveSpawn(mob)
        local folders={}
        local function add(folder,label) if folder then folders[#folders+1]={Folder=folder,Label=label} end end
        add(path(workspace,"_WorldOrigin","EnemySpawns"),"world_spawns")
        add(workspace:FindFirstChild("EnemySpawns"),"workspace_spawns")
        add(RS:FindFirstChild("FortBuilderReplicatedSpawnPositionsFolder"),"replicated_spawns")
        local _,_,root=character()
        local best,metric,source=nil,math.huge,nil
        for _,entry in ipairs(folders) do
            for _,object in ipairs(entry.Folder:GetDescendants()) do
                if cleanName(object.Name)==cleanName(mob) then
                    local cf=spawnCFrame(object)
                    local d=cf and root and (root.Position-cf.Position).Magnitude or math.huge
                    if d<metric then best,metric,source=cf,d,entry.Label end
                end
            end
        end
        return best,source
    end
    local function levelQuest(visible)
        local current=visible and questRuntime.GetActiveQuest() or nil
        local q=current or (visible and farmQuest) or questRuntime.GetBestQuest()
        local legacy=questForLevel()
        if not q then
            if legacy then legacy.Source="legacy_data" end
            return legacy
        end
        -- Use old coordinates only if they identify the exact same mission/mob/stage.
        if legacy and legacy.Name==q.Name and cleanName(legacy.Mob)==cleanName(q.Mob)
            and (q.Tier==nil or tostring(legacy.Tier)==tostring(q.Tier)) then
            q.Tier=q.Tier or legacy.Tier
            q.Spawn=legacy.Spawn
            if not q.Quest then q.Quest=legacy.Quest;q.Entrance=legacy.Entrance;q.Source=q.Source.."+legacy_position" end
        end
        return q
    end
    local function farmStep()
        local mode=options.Mode
        local _,_,root=character()
        if not root then farmProgress("waiting_character");return end
        local enemies=workspace:FindFirstChild("Enemies")
        local target
        if mode=="Level" or mode=="Boss" then
            local visible,questGui=questVisible()
            if mode=="Level" then
                questRuntime.Refresh()
                local observed=questRuntime.GetState()
                if observed.Known then visible=observed.Active end
            end
            local key=mode..":"..(mode=="Boss" and options.Boss or "level")
            if key~=farmQuestKey then farmQuest=nil;farmQuestKey=key end
            if not visible then farmQuest=nil end
            -- Preserve the accepted quest until completion, even if level changes.
            local q
            if mode=="Level" then q=levelQuest(visible) else q=farmQuest or bossForName(options.Boss) end
            if not q then
                farmProgress("waiting_quest_data")
                stopMove("Farm")
                return
            end
            farmQuestSource=q.Source or "legacy_boss_data"
            local titleObject=path(questGui,"Container","QuestTitle","Title")
            local title=titleObject and titleObject:IsA("TextLabel") and titleObject.Text or ""
            if q.Entrance and q.Quest and (root.Position-q.Quest.Position).Magnitude>10000 then
                farmProgress("requesting_entrance",q.Mob,nil,CFrame.new(q.Entrance),title)
                comm("entrance",5,"requestEntrance",q.Entrance);return
            end
            if q.Name then
                if not visible then
                    if not q.Quest or q.Tier==nil then
                        farmProgress("waiting_quest_position",q.Mob,nil,nil,title)
                        stopMove("Farm")
                        return
                    end
                    farmProgress("quest_giver",q.Mob,nil,q.Quest,title)
                    move(q.Quest,"Farm")
                    if (root.Position-q.Quest.Position).Magnitude<12 then
                        local requested=comm("quest.start",2,"StartQuest",q.Name,q.Tier)
                        if requested then farmQuest=q end
                    end
                    return
                end
                -- GUI text can be translated/pluralized. It is diagnostic text,
                -- never sufficient evidence for abandoning an accepted quest.
                farmQuest=q
            end
            target=farmNamed(enemies,{q.Mob})
            if not target then
                local point,source=liveSpawn(q.Mob)
                local destination=point and point*CFrame.new(0,3,0) or q.Spawn
                farmSpawnSource=source or (q.Spawn and "legacy_position" or "unavailable")
                farmProgress("waiting_spawn",q.Mob,nil,destination,title)
                move(destination,"Farm")
            else
                farmSpawnSource=nil
                farmProgress(distance(target)<=100 and "combat" or "moving_to_target",q.Mob,target,part(target).CFrame,title)
            end
        elseif mode=="Raid" then
            local timer=path(PlayerGui,"Main","Timer")
            if not timer or not timer.Visible then farmProgress("waiting_raid");return end
            target=nearest(enemies,function(o) return distance(o)<1500 end)
            if not target then
                local locations=path(workspace,"_WorldOrigin","Locations")
                for i=5,1,-1 do
                    local point=part(path(locations,"Island "..i))
                    if point then move(point.CFrame*CFrame.new(0,25,0),"Farm");break end
                end
            end
        elseif mode=="Nearest" then target=retainedFarmTarget(enemies) or nearest(enemies)
        elseif mode=="Material" then
            local data=materialForName(options.Material)
            if data then target=farmNamed(enemies,{data.Mob});if not target then move(data.Spawn,"Farm") end end
        elseif mode=="Law" then target=farmNamed(enemies,{"Order"})
        elseif mode=="Player" then
            local p=Players:FindFirstChild(options.Player)
            if p and p~=LocalPlayer then target=p.Character end
        else
            target=farmNamed(enemies,mobGroups[mode] or {})
            if mode=="Elite" then
                if not questVisible() then comm("elite.quest",5,"EliteHunter") end
            elseif mode=="White Belt" then net("dojo.quest",5,"RF/InteractDragonQuest",{NPC="Dojo Trainer",Command="RequestQuest"}) end
        end
        if target then
            if mode~="Level" and mode~="Boss" then farmProgress(distance(target)<=100 and "combat" or "moving_to_target",target.Name,target,part(target).CFrame) end
            fight(target,"Farm")
        end
    end
    -- Original six ESP types plus event/gear/berry markers; all owned explicitly.
    local espFlags,markers={},{}
    local function clearMarkers(group)
        for object,entry in pairs(markers) do
            if not group or entry.Group==group then entry.Gui:Destroy(); markers[object]=nil end
        end
    end
    local function classify(o)
        local name=o.Name:lower()
        if espFlags.Chest and name:find("chest",1,true) then return "Chest" end
        if espFlags.Berry and (name:find("berry",1,true) or o:GetAttribute("BerryType")~=nil) then return "Berry" end
        if espFlags.Gear and (name=="meshpart" and o:IsDescendantOf(path(workspace,"Map","MysticIsland") or uiGui) or name:find("gear",1,true)) then return "Gear" end
        if espFlags.Flower and (o.Name=="Flower1" or o.Name=="Flower2") then return "Flower" end
        if espFlags.DevilFruit and o:IsA("Tool") and name:find("fruit",1,true) then return "DevilFruit" end
        if espFlags.RealFruit and o.Parent and o.Parent.Name=="AppleSpawner" then return "RealFruit" end
        if espFlags.Island and o.Parent and o.Parent.Name=="Locations" then return "Island" end
        if espFlags.Mirage and o.Name=="MysticIsland" then return "Mirage" end
        if espFlags.Prehistoric and o.Name=="PrehistoricIsland" then return "Prehistoric" end
        if espFlags.Kitsune and o.Name=="KitsuneIsland" then return "Kitsune" end
    end
    local function espStep()
        local seen={}
        local function mark(o,group,label)
            local p=part(o)
            if not p then return end
            seen[o]=true
            local entry=markers[o]
            if not entry then
                local gui=Instance.new("BillboardGui")
                gui.Name="_XerecaESP";gui.Adornee=p;gui.Size=UDim2.fromOffset(220,50)
                gui.AlwaysOnTop=true;gui.StudsOffset=Vector3.new(0,3,0);gui.Parent=uiGui
                local text=Instance.new("TextLabel");text.Size=UDim2.fromScale(1,1)
                text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(120,255,170)
                text.TextStrokeTransparency=0.5;text.Font=Enum.Font.GothamBold;text.TextSize=13;text.Parent=gui
                entry={Gui=gui,Text=text,Group=group};markers[o]=entry
            end
            entry.Gui.Adornee=p
            local d=distance(p)
            entry.Text.Text=(label or o.Name)..(d<math.huge and ("\n"..math.floor(d/3).." m") or "")
        end
        if espFlags.Player then for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character then mark(p.Character,"Player",p.Name) end end end
        for _,o in ipairs(workspace:GetDescendants()) do
            if o:IsA("Model") or o:IsA("BasePart") or o:IsA("Tool") then
                local group=classify(o)
                if group then mark(o,group) end
            end
        end
        for object,entry in pairs(markers) do if not seen[object] or not object.Parent then entry.Gui:Destroy();markers[object]=nil end end
    end
    local function setESP(group,on)
        espFlags[group]=on==true
        if not on then clearMarkers(group) end
        local any=false
        for _,v in pairs(espFlags) do if v then any=true end end
        if any then
            if not jobs.ESP then startJob("ESP",1,espStep) end
        else stopJob("ESP");clearMarkers() end
    end
    -- Replace fragile inlined ESP while retaining the existing six toggles.
    ownedESP:StopLoop()
    ownedESP.Set=function(_,name,on) setESP((name:gsub("ESP$","")),on) end
    ownedESP.StopLoop=function() stopJob("ESP");clearMarkers() end
    for _,method in ipairs({"UpdateIsland","UpdatePlayers","UpdateChest","UpdateDevilFruit","UpdateFlower","UpdateRealFruit"}) do ownedESP[method]=function() end end
    local pagePlayer=addTab("Haki & Stats")
    local pageRaid=addTab("Raids")
    local pageShop=addTab("Compras")
    local pageTP=addTab("Teleport")
    local pageSea=addTab("Sea Events")
    local pageDojo=addTab("Dragon Dojo")
    local pageRace=addTab("Race V4")
    local pageStatus=addTab("Status")
    addSection(Farm,"Farm integrado")
    addLabel(Farm,"Um modo de farm por vez. Coordenadas/missões vêm das fontes; progresso e dano dependem do servidor. Missões consultadas no jogo; tabela alternativa até nível 2600.")
    local farmControl
    speedSlider(Farm)
    addToggle(Farm,"Manter posição fixa no farm",true,function(on)
        options.FixedFarm=on
        fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil
        stopMove("Farm")
    end)
    addLabel(Farm,"Velocidade do Tween: menor = mais lento. O ajuste também vale durante o deslocamento.")
    dropdown(Farm,"Ataque do farm",{"Auto","Matsune Click","Hoho R2","Tool"},"Auto",function(v) attackState.Method=v end)
    addLabel(Farm,"Auto: clique Matsune + ataque da arma/Net. Matsune Click: VirtualUser com alternativa R2. Hoho R2: exemplo comentado do carregador Hoho. Tool: ativação normal. DEBUG distingue envio e vida observada.")
    dropdown(Farm,"Arma",{"Melee","Sword","Gun","Blox Fruit"},options.Weapon,function(v) options.Weapon=v end)
    dropdown(Farm,"Modo",modes,"Off",function(v)
        options.Mode=v;farmQuest=nil;farmQuestKey=nil;fixedCombatTarget=nil;fixedCombatPoint=nil;stopMove("Farm")
        if v=="Off" and farmControl then farmControl.Set(false) end
    end)
    options.Material="Scrap Metal"
    dropdown(Farm,"Material",materialNames,options.Material,function(v) options.Material=v end)
    dropdown(Farm,"Boss",bossNames,options.Boss,function(v) options.Boss=v;farmQuest=nil;farmQuestKey=nil;fixedCombatTarget=nil;fixedCombatPoint=nil;stopMove("Farm") end)
    dropdown(Farm,"Finalizar mastery",{"Off","Blox Fruit","Gun","Sword"},"Off",function(v) options.Mastery=v end)
    addSlider(Farm,{Name="Mastery: vida restante (%)",Min=5,Max=80,Default=30,Step=1,Callback=function(v) options.MasteryHealth=v end})
    addSlider(Farm,{Name="Distância acima do alvo",Min=3,Max=60,Default=20,Step=1,Callback=function(v) options.Offset=v end})
    farmControl=toggleJob(Farm,"Ativar farm selecionado","Farm",0.3,farmStep)
    controls.SkillSpam=addToggle(Farm,"Usar skills Z/X/C/V/F",false,function(on) flags.SkillSpam=on end)
    for _,key in ipairs({"Z","X","C","V","F"}) do
        addToggle(Farm,"Skill "..key,options["Skill"..key],function(on) options["Skill"..key]=on end)
    end
    button(Farm,"Parar todos os movimentos",function()
        for name,control in pairs(controls) do if name=="Farm" or name=="FruitCollect" or name=="RaidNext" or name=="SeaCombat" or name=="Boat" or name=="Trials" or name=="Azure" or name=="BoneCollect" or name=="EggCollect" then control.Set(false) end end
        stopMove()
    end)
    addSection(pagePlayer,"Haki e habilidades")
    toggleJob(pagePlayer,"Auto Haki do Armamento","Buso",2,function()
        local c=character()
        if c and not c:FindFirstChild("HasBuso") then comm("haki.buso",3,"Buso") end
    end)
    toggleJob(pagePlayer,"Auto Haki da Observação","Ken",5,function()
        local remote=path(RS,"Remotes","CommE")
        if not remote or not remote:IsA("RemoteEvent") then fail("RemoteEvent CommE indisponível.") end
        remote:FireServer("Ken",true)
    end)
    toggleJob(pagePlayer,"Auto ativar Race V3","Race3",5,function() press("T") end)
    toggleJob(pagePlayer,"Auto ativar Race V4","Race4",5,function() press("Y") end)
    addSection(pagePlayer,"Atributos")
    local points=1
    addSlider(pagePlayer,{Name="Pontos por solicitação",Min=1,Max=100,Step=1,Default=1,Callback=function(v) points=v end})
    for _,stat in ipairs({"Melee","Defense","Sword","Gun","Demon Fruit"}) do
        toggleJob(pagePlayer,"Auto "..stat,"Stats."..stat,1,function()
            local available=path(LocalPlayer,"Data","Points")
            if available and available.Value>0 then comm("stats."..stat,1,"AddPoint",stat,math.min(points,available.Value)) end
        end)
    end
    local jumpOn=false
    controls.Jump=addToggle(pagePlayer,"Pulo contínuo",false,function(v) jumpOn=v end)
    bind(UserInputService.JumpRequest,function()
        if jumpOn and active and not UserInputService:GetFocusedTextBox() then local _,h=character();if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end
    end,"features.jump")
    toggleJob(Farm,"Coletar chests por contato","Chests",0.8,function()
        local best,dist=nil,math.huge
        for _,o in ipairs(workspace:GetDescendants()) do
            if o.Name:lower():find("chest",1,true) and part(o) then local d=distance(o);if d<dist then best,dist=o,d end end
        end
        if best then move(part(best).CFrame,"Chests") end
    end)
    toggleJob(Farm,"Coletar berries","Berries",1,function()
        local service=game:GetService("CollectionService")
        local best,name,metric=nil,nil,math.huge
        for _,bush in ipairs(service:GetTagged("BerryBush")) do
            for attribute in pairs(bush:GetAttributes()) do
                local point=part(bush.Parent)
                if point then local d=distance(point);if d<metric then best,name,metric=bush.Parent,attribute,d end end
            end
        end
        local point=best and (part(best:FindFirstChild(name,true)) or part(best))
        if point then move(point.CFrame*CFrame.new(0,1,0),"Berries");if distance(point)<10 then press("E") end end
    end)
    local function fruits(container)
        local found={}
        if container then for _,o in ipairs(container:GetChildren()) do if o:IsA("Tool") and o.Name:lower():find("fruit",1,true) then found[#found+1]=o end end end
        return found
    end
    local function storeFruits()
        local c=LocalPlayer.Character
        local all=fruits(LocalPlayer:FindFirstChildOfClass("Backpack"))
        for _,o in ipairs(fruits(c)) do all[#all+1]=o end
        for _,fruit in ipairs(all) do
            local original=fruit:GetAttribute("OriginalName")
            if type(original)=="string" then comm("fruit.store."..original,5,"StoreFruit",original,fruit) end
        end
    end
    button(Fruit,"Soltar frutas do inventário",function()
        local _,_,root=character()
        if not root then return end
        for _,fruit in ipairs(fruits(LocalPlayer:FindFirstChildOfClass("Backpack"))) do
            fruit.Parent=workspace
            local handle=part(fruit);if handle then handle.CFrame=root.CFrame*CFrame.new(0,0,-4) end
        end
    end)
    local function collectFruit()
        local target,best=nil,math.huge
        for _,fruit in ipairs(fruits(workspace)) do local d=distance(fruit);if d<best then target,best=fruit,d end end
        if target then move(part(target).CFrame,"FruitCollect") end
    end
    addSection(Fruit,"Funções importadas")
    button(Fruit,"Guardar frutas do inventário",storeFruits)
    toggleJob(Fruit,"Auto guardar frutas","FruitStore",5,storeFruits)
    toggleJob(Fruit,"Ir até fruta caída","FruitCollect",0.5,collectFruit)
    addLabel(Fruit,"A coleta ocorre por contato normal do personagem. O servidor decide se a fruta pode ser coletada/guardada.")
    local function hasTool(name)
        return path(LocalPlayer.Character,name) or path(LocalPlayer:FindFirstChildOfClass("Backpack"),name)
    end
    local function raidActive()
        local timer=path(PlayerGui,"Main","Timer")
        return timer and timer.Visible==true
    end
    local function startRaid(law)
        if raidActive() then return end
        if not hasTool(law and "Microchip" or "Special Microchip") then fail("Microchip necessário no inventário/personagem.") end
        local map=workspace:FindFirstChild("Map")
        local zone=map and (map:FindFirstChild("CircleIsland") or map:FindFirstChild("Boat Castle"))
        local detector=path(zone,law and "RaidSummon" or "RaidSummon2","Button","Main","ClickDetector")
        if not detector then fail("Botão de raid não encontrado neste mar.") end
        if type(fireclickdetector)~="function" then fail("fireclickdetector não está disponível neste ambiente.") end
        fireclickdetector(detector)
    end
    local function nextIsland()
        if not raidActive() then return end
        local locations=path(workspace,"_WorldOrigin","Locations")
        for i=5,1,-1 do local o=path(locations,"Island "..i);local p=part(o);if p then move(p.CFrame*CFrame.new(0,25,0),"RaidNext");return end end
    end
    addSection(pageRaid,"Raids e Law")
    dropdown(pageRaid,"Chip",{"Flame","Ice","Sand","Dark","Light","Magma","Quake","Buddha","Spider","Phoenix","Rumble","Dough"},"Flame",function(v) options.Chip=v end)
    local function buyChip() if not hasTool("Special Microchip") and not raidActive() then comm("raid.buy",10,"RaidsNpc","Select",options.Chip) end end
    button(pageRaid,"Comprar chip selecionado",buyChip)
    toggleJob(pageRaid,"Auto comprar chip","RaidBuy",10,buyChip)
    button(pageRaid,"Iniciar raid",function() startRaid(false) end)
    toggleJob(pageRaid,"Auto iniciar raid","RaidStart",5,function() if hasTool("Special Microchip") then startRaid(false) end end)
    toggleJob(pageRaid,"Auto próxima ilha","RaidNext",1,nextIsland)
    toggleJob(pageRaid,"Auto despertar fruta","Awakener",10,function() comm("raid.awaken",10,"Awakener","Awaken") end)
    button(pageRaid,"Comprar microchip Law",function() comm("law.buy",10,"BlackbeardReward","Microchip","2") end)
    button(pageRaid,"Iniciar Law",function() startRaid(true) end)
    toggleJob(pageRaid,"Auto comprar microchip Law","LawBuy",10,function() if not hasTool("Microchip") then comm("law.buy",10,"BlackbeardReward","Microchip","2") end end)
    toggleJob(pageRaid,"Auto iniciar Law","LawStart",5,function() if hasTool("Microchip") then startRaid(true) end end)
    addLabel(pageRaid,"Farm integrado: modos Raid (combate e próxima ilha) e Law (Order). Compras/despertar podem gastar recursos do jogo.")
    addSection(pageShop,"Compras das fontes")
    addLabel(pageShop,"Preços não são presumidos. Cada botão solicita uma compra; o servidor verifica custo, requisitos e resultado. Ative DEBUG para ver a resposta.")
    for _,item in ipairs(shopData) do
        button(pageShop,item.Name,function()
            commSequence("shop."..item.Name,5,item.Calls)
        end)
    end
    local boat="PirateBrigade"
    dropdown(pageShop,"Barco",{"Dinghy","PirateBasic","PirateBrigade","PirateSloop","Enforcer","RocketBoost"},boat,function(v) boat=v end)
    button(pageShop,"Comprar barco",function() comm("boat.buy",10,"BuyBoat",boat) end)
    button(pageShop,"Comprar Haki Color",function() comm("color.buy",10,"ColorsDealer","2") end)
    toggleJob(pageShop,"Auto Legendary Sword Dealer","Legendary",30,function() for i=1,3 do comm("sword.dealer."..i,30,"LegendarySwordDealer",tostring(i)) end end)
    toggleJob(pageShop,"Auto comprar habilidades básicas","AbilitiesBuy",20,function()
        commSequence("abilities.buy",20,{{"BuyHaki","Geppo"},{"BuyHaki","Buso"},{"BuyHaki","Soru"}})
    end)
    button(pageShop,"Trocar Bones",function() comm("bone.trade",5,"Bones","Buy",1,1) end)
    toggleJob(pageShop,"Auto trocar Bones","BonesTrade",10,function() comm("bone.trade",10,"Bones","Buy",1,1) end)
    button(pageSea,"Rezar na Kitsune Statue",function() net("kitsune.pray",5,"RF/KitsuneStatuePray") end)
    local function islandNames()
        local names={};for name in pairs(islandData) do names[#names+1]=name end;table.sort(names);return names
    end
    local selectedIsland="Middle Town"
    dropdown(pageTP,"Ilha (confira o mar)",islandNames(),selectedIsland,function(v) selectedIsland=v end)
    button(pageTP,"Ir à ilha selecionada",function()
        local data=islandData[selectedIsland]
        if data.Entrance then comm("entrance",3,"requestEntrance",data.Target.Position) else move(data.Target,"Manual") end
    end)
    for _,sea in ipairs({{"Primeiro mar","TravelMain"},{"Segundo mar","TravelDressrosa"},{"Terceiro mar","TravelZou"}}) do button(pageTP,sea[1],function() comm("travel",5,sea[2]) end) end
    speedSlider(pageTP)
    local npcSelection=""
    local function npcNames()
        local names={};local folder=workspace:FindFirstChild("NPCs")
        if folder then for _,npc in ipairs(folder:GetChildren()) do if part(npc) then names[#names+1]=npc.Name end end end
        table.sort(names);return names
    end
    local npcControl=dropdown(pageTP,"NPC deste servidor",npcNames(),"",function(v) npcSelection=v end)
    button(pageTP,"Atualizar NPCs",function() npcControl.Refresh(npcNames()) end)
    button(pageTP,"Ir até NPC",function()
        local point=part(path(workspace,"NPCs",npcSelection))
        if point then move(point.CFrame*CFrame.new(0,3,0),"Manual") else fail("NPC não encontrado no servidor atual.") end
    end)
    local function playerNames()
        local names={};for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then names[#names+1]=p.Name end end;table.sort(names);return names
    end
    local playerSelect=dropdown(pageTP,"Jogador",playerNames(),"",function(v) options.Player=v end)
    button(pageTP,"Atualizar jogadores",function() playerSelect.Refresh(playerNames()) end)
    button(pageTP,"Ir até jogador",function() local p=Players:FindFirstChild(options.Player);local root=p and part(p.Character);if root then move(root.CFrame*CFrame.new(0,3,0),"Manual") end end)
    local originalSubject
    local function restoreCamera()
        local camera=workspace.CurrentCamera
        local _,h=character()
        if camera then camera.CameraSubject=(originalSubject and originalSubject.Parent and originalSubject) or h end
        originalSubject=nil
    end
    toggleJob(pageTP,"Observar jogador","Spectate",0.5,function()
        local camera=workspace.CurrentCamera
        local p=Players:FindFirstChild(options.Player)
        local humanoid=p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        if camera and humanoid then
            if not originalSubject then originalSubject=camera.CameraSubject end
            camera.CameraSubject=humanoid
        end
    end)
    -- Restore immediately when the toggle is switched off.
    local oldSpectateSet=controls.Spectate.Set
    controls.Spectate.Set=function(v) oldSpectateSet(v);if not v then restoreCamera() end end
    -- A normal user click goes through the job callback, so stopJob also restores below.
    local baseStopJob=stopJob
    stopJob=function(name) baseStopJob(name);if name=="Spectate" then restoreCamera() end end
    toggleJob(pageTP,"Câmera no jogador selecionado","AimCamera",0.1,function()
        if UserInputService:GetFocusedTextBox() then return end
        local camera=workspace.CurrentCamera
        local player=Players:FindFirstChild(options.Player)
        local target=player and part(player.Character)
        if camera and target then camera.CFrame=CFrame.lookAt(camera.CFrame.Position,target.Position) end
    end)
    button(pageTP,"Reentrar no servidor",function() TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end)
    addTextbox(pageTP,{Placeholder="JobId para entrar",Callback=function(id) options.Job=id end})
    button(pageTP,"Entrar no JobId",function() if options.Job and options.Job~="" then TeleportService:TeleportToPlaceInstance(game.PlaceId,options.Job,LocalPlayer) end end)
    addSection(ESPtab,"ESP de eventos")
    for _,group in ipairs({"Berry","Gear","Mirage","Prehistoric","Kitsune"}) do controls["ESP."..group]=addToggle(ESPtab,"ESP "..group,false,function(on) setESP(group,on) end) end
    addSection(pageSea,"Eventos marítimos")
    local seaTarget="Terrorshark"
    dropdown(pageSea,"Alvo",{"Terrorshark","Shark","Piranha","Fish Crew Member","SeaBeast","Ghost Ship","Leviathan Segment","Leviathan Tail"},seaTarget,function(v) seaTarget=v end)
    toggleJob(pageSea,"Combater alvo marítimo","SeaCombat",0.4,function()
        local target=named(workspace:FindFirstChild("Enemies"),{seaTarget})
        if seaTarget=="Ghost Ship" then target=named(workspace:FindFirstChild("Enemies"),{"FishBoat","PirateBasic","PirateBrigade","PirateGrandBrigade"})
        elseif not target and seaTarget=="SeaBeast" then target=nearest(workspace:FindFirstChild("SeaBeasts"))
        elseif not target and seaTarget:find("Leviathan",1,true) then target=named(workspace:FindFirstChild("SeaBeasts"),{seaTarget}) end
        if target then fight(target,"SeaCombat") end
    end)
    local function eventPart(name)
        return path(workspace,"Map",name) or path(workspace,"_WorldOrigin","Locations",name)
    end
    for _,entry in ipairs({{"Kitsune Island","KitsuneIsland"},{"Mirage Island","MysticIsland"},{"Prehistoric Island","PrehistoricIsland"}}) do
        button(pageSea,"Ir a "..entry[1],function() local p=part(eventPart(entry[2]) or eventPart(entry[1]));if p then move(p.CFrame*CFrame.new(0,10,0),"Manual") else fail("Ilha não encontrada neste servidor.") end end)
    end
    local function collectNamed(needle,owner)
        local best,d=nil,math.huge
        for _,o in ipairs(workspace:GetDescendants()) do
            if o.Name:lower():find(needle,1,true) and part(o) then local dist=distance(o);if dist<d then best,d=o,dist end end
        end
        if best then move(part(best).CFrame,owner) end
    end
    toggleJob(pageSea,"Coletar Azure Ember por contato","Azure",0.7,function() collectNamed("azure","Azure") end)
    toggleJob(pageSea,"Coletar Dragon Bone por contato","BoneCollect",0.7,function() collectNamed("dragonbone","BoneCollect") end)
    toggleJob(pageSea,"Coletar Dragon Egg por contato","EggCollect",0.7,function() collectNamed("dragonegg","EggCollect") end)
    local boatDirection=Vector3.new(-1,0,0)
    dropdown(pageSea,"Rumo do barco",{"Oeste","Leste","Norte","Sul"},"Oeste",function(v) boatDirection=({Oeste=Vector3.new(-1,0,0),Leste=Vector3.new(1,0,0),Norte=Vector3.new(0,0,-1),Sul=Vector3.new(0,0,1)})[v] end)
    toggleJob(pageSea,"Navegar barco sentado","Boat",0.5,function()
        local _,h=character();local seat=h and h.SeatPart
        if not seat or not seat:IsA("VehicleSeat") then return end
        local boatModel=seat:FindFirstAncestorOfClass("Model")
        if boatModel then boatModel:PivotTo(boatModel:GetPivot()+boatDirection*25) end
    end)
    local lightingOriginal
    controls.Day=addToggle(pageSea,"Sempre dia",false,function(on)
        if on then
            lightingOriginal=lightingOriginal or Lighting.ClockTime
            startJob("Day",1,function() Lighting.ClockTime=12 end)
        else stopJob("Day");if lightingOriginal then Lighting.ClockTime=lightingOriginal;lightingOriginal=nil end end
    end)
    local fogOriginal
    controls.Fog=addToggle(pageSea,"Remover neblina",false,function(on)
        if on then
            if not fogOriginal then fogOriginal={FogEnd=Lighting.FogEnd,FogStart=Lighting.FogStart,Atmospheres={}} end
            Lighting.FogEnd=100000;Lighting.FogStart=100000
            for _,o in ipairs(Lighting:GetChildren()) do if o:IsA("Atmosphere") then fogOriginal.Atmospheres[o]=o.Density;o.Density=0 end end
        elseif fogOriginal then
            Lighting.FogEnd=fogOriginal.FogEnd;Lighting.FogStart=fogOriginal.FogStart
            for o,value in pairs(fogOriginal.Atmospheres) do if o.Parent then o.Density=value end end
            fogOriginal=nil
        end
    end)
    addSection(pageDojo,"Dragon Dojo")
    button(pageDojo,"Ir ao Dragon Dojo",function() move(CFrame.new(5841.2988,1208.3218,884.3173),"Manual") end)
    button(pageDojo,"Pedir missão Dojo Trainer",function() net("dojo.quest",5,"RF/InteractDragonQuest",{NPC="Dojo Trainer",Command="RequestQuest"}) end)
    button(pageDojo,"Ver missão Dragon Hunter",function() net("dragon.check",5,"RF/DragonHunter",{Context="Check"}) end)
    button(pageDojo,"Craft Volcanic Magnet",function() comm("dragon.craft",10,"CraftItem","Craft","Volcanic Magnet") end)
    addLabel(pageDojo,"Farm: modos White Belt e Dragon Hunter. O botão pede a missão; progresso e requisitos são controlados pelo servidor.")
    local racePositions={Human=CFrame.new(29221.8223,14890.9756,-205.9911),Skypiea=CFrame.new(28960.1582,14919.624,235.0395),Fishman=CFrame.new(28231.1758,14890.9756,-211.6417),Cyborg=CFrame.new(28502.6816,14895.9756,-423.7279),Ghoul=CFrame.new(28674.2441,14890.6768,445.4311),Mink=CFrame.new(29012.3418,14890.9756,-380.1493)}
    addSection(pageRace,"Race V4")
    button(pageRace,"Topo da Great Tree",function() move(CFrame.new(3030.3945,2280.6172,-7320.1836),"Manual") end)
    button(pageRace,"Temple of Time",function() comm("entrance",3,"requestEntrance",Vector3.new(28286.3555,14895.3018,102.6247)) end)
    button(pageRace,"Alavanca",function() move(CFrame.new(28575.1816,14936.6279,72.3164),"Manual") end)
    button(pageRace,"Ancient Clock",function() move(CFrame.new(29553.7812,15066.6133,-88.275),"Manual") end)
    button(pageRace,"Porta da minha raça",function()
        local race=path(LocalPlayer,"Data","Race");local cf=race and racePositions[race.Value]
        if cf then move(cf,"Manual") else fail("Raça sem coordenadas nas fontes.") end
    end)
    button(pageRace,"Consultar progresso Ancient One",function() comm("race.progress",5,"UpgradeRace","Check") end)
    button(pageRace,"Comprar upgrade Ancient One",function() comm("race.upgrade",5,"UpgradeRace","Buy") end)
    toggleJob(pageRace,"Olhar para a lua","Moon",0.2,function()
        local camera=workspace.CurrentCamera
        if camera then camera.CFrame=CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+Lighting:GetMoonDirection()) end
    end)
    toggleJob(pageRace,"Trial: combate Human/Ghoul","Trials",0.4,function()
        local timer=path(PlayerGui,"Main","Timer")
        if not timer or not timer.Visible then return end
        local race=path(LocalPlayer,"Data","Race")
        if race and (race.Value=="Human" or race.Value=="Ghoul") then
            local target=nearest(workspace:FindFirstChild("Enemies"));if target then fight(target,"Trials") end
        end
    end)
    toggleJob(pageRace,"Trial: caminho Sky/Mink/Cyborg/Shark","TrialPath",0.7,function()
        local timer=path(PlayerGui,"Main","Timer")
        if not timer or not timer.Visible then return end
        local race=path(LocalPlayer,"Data","Race")
        local value=race and race.Value
        if value=="Skypiea" then
            local trial=path(workspace,"Map","SkyTrial")
            local goal=trial and trial:FindFirstChild("snowisland_Cylinder.081",true)
            if goal and part(goal) then move(part(goal).CFrame,"TrialPath") end
        elseif value=="Mink" then
            local trial=path(workspace,"Map","MinkTrial")
            local goal=trial and trial:FindFirstChild("StartPoint",true)
            if goal and part(goal) then move(part(goal).CFrame*CFrame.new(0,3,0),"TrialPath") end
        elseif value=="Cyborg" then move(CFrame.new(28654,14898.7832,-30),"TrialPath")
        elseif value=="Fishman" then
            local target=nearest(workspace:FindFirstChild("SeaBeasts"))
            if target then fight(target,"TrialPath") end
        end
    end)
    addLabel(pageRace,"Trials: combate normal; não altera Health local nem confirma conclusão no servidor. Para PvP, escolha jogador e modo Player em Farm.")
    addSection(pageStatus,"Status do servidor")
    local statusLabel=addLabel(pageStatus,"Clique em Atualizar status.")
    local function status()
        local sky=Lighting:FindFirstChildOfClass("Sky")
        local text="Mar/PlaceId: "..tostring(game.PlaceId).." | Horário: "..tostring(Lighting.ClockTime)
        for _,pair in ipairs({{"Mirage","MysticIsland"},{"Kitsune","KitsuneIsland"},{"Prehistoric","PrehistoricIsland"}}) do text=text.."\n"..pair[1]..": "..(eventPart(pair[2]) and "presente" or "não encontrado") end
        if sky then text=text.."\nLua (asset): "..tostring(sky.MoonTextureId) end
        local quest=questRuntime.GetBestQuest() or questForLevel();text=text.."\nQuest selecionada: "..(quest and quest.Mob or "sem dados")
        statusLabel.Text=text
    end
    button(pageStatus,"Atualizar status",status)
    toggleJob(pageStatus,"Atualizar status automaticamente","Status",5,status)
    bind(LocalPlayer.CharacterAdded,function()
        stopMove();fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil;restoreCamera()
    end,"features.respawn")
    bind(LocalPlayer.CharacterRemoving,function()
        stopMove();fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil
    end,"features.character_removing")
    local function restoreVisuals()
        if lightingOriginal then Lighting.ClockTime=lightingOriginal;lightingOriginal=nil end
        if fogOriginal then
            Lighting.FogEnd=fogOriginal.FogEnd;Lighting.FogStart=fogOriginal.FogStart
            for o,v in pairs(fogOriginal.Atmospheres) do if o.Parent then o.Density=v end end
            fogOriginal=nil
        end
    end
    local function stopAll()
        requestSession=requestSession+1
        jumpOn=false;flags.SkillSpam=false
        for _,control in pairs(controls) do control.Set(false) end
        for _,control in pairs(espControls) do control.Set(false) end
        for name in pairs(jobs) do stopJob(name) end
        stopMove();clearMarkers();restoreCamera();restoreVisuals()
    end
    local function cleanup()
        if not active then return end
        active=false;stopAll()
        local vim=game:GetService("VirtualInputManager")
        for key in pairs(heldKeys) do pcall(function() vim:SendKeyEvent(false,key,false,game) end) end
    end
    table.insert(cleanupFns,cleanup)
    addSection(Settings,"Módulos importados")
    button(Settings,"Parar funções importadas",stopAll)
    addLabel(Settings,"Portes Cokka/Matsune: funções ativadas somente pelos controles. Contratos do jogo e coordenadas precisam de validação no cliente.")
    report("startup",supported and "target game detected" or "UI available; target game unavailable")
    return {StopAll=stopAll,GetState=function()
        local running={};for name in pairs(jobs) do running[#running+1]=name end;table.sort(running)
        return {Active=active,SupportedGame=supported,Mode=options.Mode,Attack=table.clone(attackState),TweenSpeed=options.Speed,Jobs=running,Flags=table.clone(flags),Farm=table.clone(farmStatus),QuestRuntime=questRuntime.GetState(),Movement={Owner=moveOwner,Suspended=motionState~=nil,Destination=moveTarget and moveTarget.Position or nil,FixedFarm=options.FixedFarm}}
    end}
end

local importedFeatures = initImportedFeatures()

-- A read-only check: does not fire remotes or change window/toggle state.
local function runDebug()
    local checks = {}
    local function check(name, passed, detail)
        checks[#checks + 1] = {Name=name, Passed=passed == true, Detail=tostring(detail or "")}
        debugLog(passed and "INFO" or "WARN", "check." .. name, detail)
    end
    check("lifecycle", not destroyed, destroyed and "unloaded" or "active")
    check("gui", not destroyed and uiGui.Parent == PlayerGui, "owned ScreenGui")
    check("FastAttack", type(fastAttackApi) == "table" and type(fastAttackApi.Start) == "function", "API initialized")
    check("ESP", type(ownedESP) == "table" and type(ownedESP.Set) == "function", "API initialized")
    check("camera", workspace.CurrentCamera ~= nil, "camera may be temporarily absent")
    if not destroyed then
        local target = sizeFor(state)
        local settled = not sizeTween or sizeTween.PlaybackState ~= Enum.PlaybackState.Playing
        if settled then
            check("geometry", Main.Size == target, "state=" .. state .. " actual=" .. tostring(Main.Size) .. " expected=" .. tostring(target))
        end
        local closing = openTween and openTween.PlaybackState == Enum.PlaybackState.Playing
        if not closing then check("visibility", Main.Visible == isUIOpen, "open=" .. tostring(isUIOpen) .. " visible=" .. tostring(Main.Visible)) end
    end
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local fruitRemote = remotes and remotes:FindFirstChild("CommF_")
    check("fruit.remote", fruitRemote ~= nil and fruitRemote:IsA("RemoteFunction"), "optional; only available in the target game")
    return {Enabled=debugEnabled, Destroyed=destroyed, State=state, Open=isUIOpen, Checks=checks, Features=importedFeatures.GetState()}
end
local function getDebugLog()
    local copy = {}
    for i, entry in ipairs(debugHistory) do copy[i] = table.clone(entry) end
    return copy
end

-- Diagnostics stay local; no external logging or global error interception.
local debugWindow=new("Frame",{Name="XerecaDebugWindow",ZIndex=20,Size=UDim2.fromOffset(460,420),Position=UDim2.fromOffset(30,80),Visible=false,Active=true,BorderSizePixel=0,Theme={BackgroundColor3="ComponentBg"}},uiGui)
new("UICorner",{CornerRadius=UDim.new(0,8)},debugWindow)
local debugTitle=new("TextLabel",{Text="XERECA | DEBUG • arraste aqui",Size=UDim2.new(1,-45,0,36),BackgroundTransparency=1,Active=true,Font=Enum.Font.GothamBold,TextSize=13,Theme={TextColor3="Text"}},debugWindow)
local debugClose=new("TextButton",{Text="X",Size=UDim2.fromOffset(34,30),Position=UDim2.new(1,-38,0,3),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=14,Theme={TextColor3="Text"}},debugWindow)
local debugPage=new("ScrollingFrame",{Position=UDim2.fromOffset(12,40),Size=UDim2.new(1,-20,1,-48),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},debugWindow)
new("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},debugPage)
local function fitDebugWindow()
    local camera=workspace.CurrentCamera
    local v=camera and camera.ViewportSize or Vector2.new(800,600)
    debugWindow.Size=UDim2.fromOffset(math.min(460,math.max(180,v.X-24)),math.min(420,math.max(160,v.Y-48)))
    local x=math.clamp(debugWindow.Position.X.Offset,0,math.max(0,v.X-debugWindow.Size.X.Offset))
    local y=math.clamp(debugWindow.Position.Y.Offset,0,math.max(0,v.Y-debugWindow.Size.Y.Offset))
    debugWindow.Position=UDim2.fromOffset(x,y)
end
local debugDrag,debugDragPoint,debugDragOrigin
bind(debugTitle.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        debugDrag=input;debugDragPoint=input.Position;debugDragOrigin=debugWindow.Position
    end
end,"debug.drag.begin")
bind(UserInputService.InputChanged,function(input)
    if not debugDrag then return end
    if debugDrag.UserInputType==Enum.UserInputType.Touch and input~=debugDrag then return end
    if debugDrag.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=input.Position-debugDragPoint
    debugWindow.Position=UDim2.fromOffset(debugDragOrigin.X.Offset+delta.X,debugDragOrigin.Y.Offset+delta.Y)
    fitDebugWindow()
end,"debug.drag.move")
bind(UserInputService.InputEnded,function(input) if input==debugDrag or input.UserInputType==Enum.UserInputType.MouseButton1 then debugDrag=nil end end,"debug.drag.end")
bind(UserInputService.WindowFocusReleased,function() debugDrag=nil end,"debug.drag.focus")
bind(debugClose.Activated,function() setDebug(false) end,"debug.close")
addBtn(Settings,"Abrir janela DEBUG",function() setDebug(true) end)
addSection(debugPage,"Diagnóstico do XERECA HUB")
addLabel(debugPage,"Envio de ataque não confirma dano. Confira a vida observada abaixo. Logs locais, limitados a 100 entradas; nenhum envio externo.")
local panelPaused,onlyProblems=false,false
local debugSearch=""
local debugStatus=addLabel(debugPage,"DEBUG desativado")
local debugOutput=addLabel(debugPage,"")
debugOutput.RichText=false
local function debugReportText()
    local snapshot=importedFeatures.GetState()
    local farm=snapshot.Farm or {}
    local attack=snapshot.Attack or {}
    local movement=snapshot.Movement or {}
    local rows={"XERECA HUB | diagnóstico local",
        "Farm: "..tostring(farm.Phase).." | alvo: "..tostring(farm.Target or farm.ExpectedMob),
        "Ataque: "..tostring(attack.Phase).." | método: "..tostring(attack.Method).." | transporte: "..tostring(attack.Transport).." | clique: "..tostring(attack.Input),
        "Arma: "..tostring(attack.Tool).." | distância: "..tostring(attack.Distance).." | tentativas: "..tostring(attack.Attempts),
        "Última perda de vida observada (relógio local): "..tostring(attack.LastDamageAt),
        "Movimento: "..tostring(movement.Owner).." | suspenso: "..tostring(movement.Suspended),
        "Missão: "..tostring(farm.QuestSource).." | spawn: "..tostring(farm.SpawnSource),
        "Interface: "..tostring(state).." | aberta: "..tostring(isUIOpen).." | descarregada: "..tostring(destroyed)}
    return table.concat(rows,"\n")
end
local function refreshDebugPanel()
    if destroyed then return end
    if not debugEnabled then debugStatus.Text="DEBUG desativado";return end
    debugStatus.Text=debugReportText()
    local rows={}
    for i=#debugHistory,1,-1 do
        local e=debugHistory[i]
        local line=string.format("[%.1f] [%s] %s: %s",e.Time,e.Level,e.Event,e.Detail)
        if (not onlyProblems or e.Level=="ERROR" or e.Level=="WARN") and (debugSearch=="" or line:lower():find(debugSearch,1,true)) then
            table.insert(rows,1,line:sub(1,600))
            if #rows>=25 then break end
        end
    end
    debugOutput.Text=#rows>0 and table.concat(rows,"\n") or "Sem registros para este filtro."
end
debugPanelControl=addToggle(debugPage,"Ativar painel DEBUG",false,function(on) setDebug(on);refreshDebugPanel() end)
addToggle(debugPage,"Pausar atualização do painel",false,function(on) panelPaused=on end)
addToggle(debugPage,"Somente avisos e erros",false,function(on) onlyProblems=on;refreshDebugPanel() end)
addTextbox(debugPage,{Placeholder="Filtrar logs (ex.: combat)",Callback=function(text) debugSearch=tostring(text):lower();refreshDebugPanel() end})
addBtn(debugPage,"Atualizar diagnóstico",function() runDebug();refreshDebugPanel() end)
addBtn(debugPage,"Limpar registros",function() table.clear(debugHistory);refreshDebugPanel() end)
debugVisibility=function(on)
    if destroyed then return end
    debugWindow.Visible=on
    debugDrag=nil
    if on then fitDebugWindow();refreshDebugPanel() end
end
local lastDebugPaint=0
bind(game:GetService("RunService").Heartbeat,function()
    if debugEnabled and debugWindow.Visible and not panelPaused and os.clock()-lastDebugPaint>=1 then
        lastDebugPaint=os.clock();fitDebugWindow();refreshDebugPanel()
    end
end,"debug.panel")

addSection(Settings, "DEBUG")
debugControl=addToggle(Settings, "Ativar DEBUG (Output)", DEBUG_DEFAULT, setDebug)
addBtn(Settings, "Executar diagnóstico", function()
    local report = runDebug()
    local failures = 0
    for _, check in ipairs(report.Checks) do if not check.Passed then failures = failures + 1 end end
    notify({Title="DEBUG", Text=tostring(#report.Checks) .. " verificações; " .. tostring(failures)
        .. " pontos para conferir. Ative DEBUG para detalhes no Output."})
end)

addBtn(Settings, "KILL / Descarregar script", unload)

local UILib = {
    Kill = function() unload() end,
    Features = importedFeatures,
    SetDebug = function(first, second)
        if type(first)=="table" then return setDebug(second) end
        return setDebug(first)
    end,
    IsDebugEnabled = function() return debugEnabled end,
    RunDebug = runDebug,
    GetDebugReport = debugReportText,
    GetDebugLog = getDebugLog,
    ClearDebugLog = function() table.clear(debugHistory) end,
    Destroy = function() unload() end,
    SetTheme = function(name) if not destroyed and THEMES[name] then activeTheme=name; applyTheme({}); Float.BackgroundColor3=T().Accent end end,
    Notify = notify,
    Toggle = toggleUI,
}
_G.XerecaUILib = UILib
table.insert(cleanupFns,function() if _G.XerecaUILib==UILib then _G.XerecaUILib=nil end end)
shared._UILibUnload = unload

setOpen(true)
debugLog("INFO", "startup", "UI ready; RightShift configured")
print("[UILib] XERECA HUB loaded successfully.")
return UILib



