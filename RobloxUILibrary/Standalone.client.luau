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

-- The vendor is embedded, so this preview does not fetch third-party UI code at runtime.
local function initFluentVendor()
    -- Own the vendor's timers and spring-render connections as part of KILL/reload.
    local scheduler=task
    local task=setmetatable({}, {__index=scheduler})
    for _,method in ipairs({"spawn","defer","delay"}) do
        task[method]=function(...) local thread=scheduler[method](...);trackTask(thread);return thread end
    end
    local realGame=game
    local run=realGame:GetService("RunService")
    local trackedRun={IsStudio=function() return run:IsStudio() end}
    for _,name in ipairs({"RenderStepped","Heartbeat","Stepped"}) do
        local signal=run[name]
        trackedRun[name]={Connect=function(_,fn) return bind(signal,fn,"fluent.render") end,Wait=function() return signal:Wait() end}
    end
    local game={GetService=function(_,name) if name=="RunService" then return trackedRun end;return realGame:GetService(name) end}
--[[FLUENT_VENDOR_BEGIN]]
--[=[
MIT License

Copyright (c) 2023 dawid

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


]=]
--[[
    Fluent Interface Suite
    This script is not intended to be modified.
    To view the source code, see the 'src' folder on GitHub!

    Author: dawid
    License: MIT
    GitHub: https://github.com/dawid-scripts/Fluent
--]]

local a,b={{1,'ModuleScript',{'MainModule'},{{18,'ModuleScript',{'Creator'}},{28,'ModuleScript',{'Icons'}},{47,'ModuleScript',{'Themes'},{{50,'ModuleScript',{'Dark'}},{52,'ModuleScript',{'Light'}},{51,'ModuleScript',{'Darker'}},{53,'ModuleScript',{'Rose'}},{49,'ModuleScript',{'Aqua'}},{48,'ModuleScript',{'Amethyst'}}}},{19,'ModuleScript',{'Elements'},{{21,'ModuleScript',{'Colorpicker'}},{27,'ModuleScript',{'Toggle'}},{23,'ModuleScript',{'Input'}},{20,'ModuleScript',{'Button'}},{25,'ModuleScript',{'Paragraph'}},{22,'ModuleScript',{'Dropdown'}},{26,'ModuleScript',{'Slider'}},{24,'ModuleScript',{'Keybind'}}}},{29,'Folder',{'Packages'},{{30,'ModuleScript',{'Flipper'},{{33,'ModuleScript',{'GroupMotor'}},{46,'ModuleScript',{'isMotor.spec'}},{39,'ModuleScript',{'Signal'}},{40,'ModuleScript',{'Signal.spec'}},{45,'ModuleScript',{'isMotor'}},{36,'ModuleScript',{'Instant.spec'}},{44,'ModuleScript',{'Spring.spec'}},{42,'ModuleScript',{'SingleMotor.spec'}},{38,'ModuleScript',{'Linear.spec'}},{31,'ModuleScript',{'BaseMotor'}},{43,'ModuleScript',{'Spring'}},{35,'ModuleScript',{'Instant'}},{37,'ModuleScript',{'Linear'}},{41,'ModuleScript',{'SingleMotor'}},{34,'ModuleScript',{'GroupMotor.spec'}},{32,'ModuleScript',{'BaseMotor.spec'}}}}}},{2,'ModuleScript',{'Acrylic'},{{3,'ModuleScript',{'AcrylicBlur'}},{5,'ModuleScript',{'CreateAcrylic'}},{6,'ModuleScript',{'Utils'}},{4,'ModuleScript',{'AcrylicPaint'}}}},{7,'Folder',{'Components'},{{9,'ModuleScript',{'Button'}},{12,'ModuleScript',{'Notification'}},{13,'ModuleScript',{'Section'}},{17,'ModuleScript',{'Window'}},{14,'ModuleScript',{'Tab'}},{10,'ModuleScript',{'Dialog'}},{8,'ModuleScript',{'Assets'}},{16,'ModuleScript',{'TitleBar'}},{15,'ModuleScript',{'Textbox'}},{11,'ModuleScript',{'Element'}}}}}}}local aa={function()local c,d,e,f,g=b(1)local h,i,j,k,l,m=game:GetService'Lighting',game:GetService'RunService',game:GetService'Players'.LocalPlayer,game:GetService'UserInputService',game:GetService'TweenService',game:GetService'Workspace'.CurrentCamera local n,o=j:GetMouse(),d local p,q,r,s=e(o.Creator),e(o.Elements),e(o.Acrylic),o.Components local t,u,v=e(s.Notification),p.New,protectgui or(syn and syn.protect_gui)or function()end local w=u('ScreenGui',{Name='_XerecaFluent',Parent=i:IsStudio()and j.PlayerGui or game:GetService'CoreGui'})v(w)t:Init(w)local x={Version='1.1.0',OpenFrames={},Options={},Themes=e(o.Themes).Names,Window=nil,WindowFrame=nil,Unloaded=false,Theme='Dark',DialogOpen=false,UseAcrylic=false,Acrylic=false,Transparency=true,MinimizeKeybind=nil,MinimizeKey=Enum.KeyCode.LeftControl,GUI=w}function x.SafeCallback(y,z,...)if not z then return end local A,B=pcall(z,...)if not A then local C,D=B:find':%d+: 'if not D then return x:Notify{Title='Interface',Content='Callback error',SubContent=B,Duration=5}end return x:Notify{Title='Interface',Content='Callback error',SubContent=B:sub(D+1),Duration=5}end end function x.Round(y,z,A)if A==0 then return math.floor(z)end z=tostring(z)return z:find'%.'and tonumber(z:sub(1,z:find'%.'+A))or z end local y=e(o.Icons).assets function x.GetIcon(z,A)if A~=nil and y['lucide-'..A]then return y['lucide-'..A]end return nil end local z={}z.__index=z z.__namecall=function(A,B,...)return z[B](...)end for A,B in ipairs(q)do z['Add'..B.__type]=function(C,D,E)B.Container=C.Container B.Type=C.Type B.ScrollFrame=C.ScrollFrame B.Library=x return B:New(D,E)end end x.Elements=z function x.CreateWindow(C,D)assert(D.Title,'Window - Missing Title')if x.Window then print'You cannot create more than one window.'return end x.MinimizeKey=D.MinimizeKey x.UseAcrylic=D.Acrylic if D.Acrylic then r.init()end local E=e(s.Window){Parent=w,Size=D.Size,Title=D.Title,SubTitle=D.SubTitle,TabWidth=D.TabWidth}x.Window=E x:SetTheme(D.Theme)return E end function x.SetTheme(C,D)if x.Window and table.find(x.Themes,D)then x.Theme=D p.UpdateTheme()end end function x.Destroy(C)if x.Window then x.Unloaded=true if x.UseAcrylic then x.Window.AcrylicPaint.Model:Destroy()end p.Disconnect()x.GUI:Destroy()end end function x.ToggleAcrylic(C,D)if x.Window then if x.UseAcrylic then x.Acrylic=D x.Window.AcrylicPaint.Model.Transparency=D and 0.98 or 1 if D then r.Enable()else r.Disable()end end end end function x.ToggleTransparency(C,D)if x.Window then x.Window.AcrylicPaint.Frame.Background.BackgroundTransparency=D and 0.35 or 0 end end function x.Notify(C,D)return t:New(D)end return x end,function()local c,d,e,f,g=b(2)local h={AcrylicBlur=e(d.AcrylicBlur),CreateAcrylic=e(d.CreateAcrylic),AcrylicPaint=e(d.AcrylicPaint)}function h.init()local i=Instance.new'DepthOfFieldEffect'i.FarIntensity=0 i.InFocusRadius=0.1 i.NearIntensity=1 local j={}function h.Enable()for k,l in pairs(j)do l.Enabled=false end i.Parent=game:GetService'Lighting'end function h.Disable()for k,l in pairs(j)do l.Enabled=l.enabled end i.Parent=nil end local k=function()local k=function(k)if k:IsA'DepthOfFieldEffect'then j[k]={enabled=k.Enabled}end end for l,m in pairs(game:GetService'Lighting':GetChildren())do k(m)end if game:GetService'Workspace'.CurrentCamera then for n,o in pairs(game:GetService'Workspace'.CurrentCamera:GetChildren())do k(o)end end end k()h.Enable()end return h end,function()local c,d,e,f,g=b(3)local h,i,j,k=e(d.Parent.Parent.Creator),e(d.Parent.CreateAcrylic),unpack(e(d.Parent.Utils))local l=function(l)local m={}l=l or 0.001 local n,o={topLeft=Vector2.new(),topRight=Vector2.new(),bottomRight=Vector2.new()},i()o.Parent=workspace local p,q=function(p,q)n.topLeft=q n.topRight=q+Vector2.new(p.X,0)n.bottomRight=q+p end,function()local p=game:GetService'Workspace'.CurrentCamera if p then p=p.CFrame end local q=p if not q then q=CFrame.new()end local r,s,t,u=q,n.topLeft,n.topRight,n.bottomRight local v,w,x=j(s,l),j(t,l),j(u,l)local y,z=(w-v).Magnitude,(w-x).Magnitude o.CFrame=CFrame.fromMatrix((v+x)/2,r.XVector,r.YVector,r.ZVector)o.Mesh.Scale=Vector3.new(y,z,0)end local r,s=function(r)local s=k()local t,u=r.AbsoluteSize-Vector2.new(s,s),r.AbsolutePosition+Vector2.new(s/2,s/2)p(t,u)task.spawn(q)end,function()local r=game:GetService'Workspace'.CurrentCamera if not r then return end table.insert(m,r:GetPropertyChangedSignal'CFrame':Connect(q))table.insert(m,r:GetPropertyChangedSignal'ViewportSize':Connect(q))table.insert(m,r:GetPropertyChangedSignal'FieldOfView':Connect(q))task.spawn(q)end o.Destroying:Connect(function()for t,u in m do pcall(function()u:Disconnect()end)end end)s()return r,o end return function(m)local n,o,p={},l(m)local q=h.New('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})h.AddSignal(q:GetPropertyChangedSignal'AbsolutePosition',function()o(q)end)h.AddSignal(q:GetPropertyChangedSignal'AbsoluteSize',function()o(q)end)n.AddParent=function(r)h.AddSignal(r:GetPropertyChangedSignal'Visible',function()n.SetVisibility(r.Visible)end)end n.SetVisibility=function(r)p.Transparency=r and 0.98 or 1 end n.Frame=q n.Model=p return n end end,function()local c,d,e,f,g=b(4)local h,i=e(d.Parent.Parent.Creator),e(d.Parent.AcrylicBlur)local j=h.New return function(k)local l={}l.Frame=j('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=0.9,BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0},{j('ImageLabel',{Image='rbxassetid://8992230677',ScaleType='Slice',SliceCenter=Rect.new(Vector2.new(99,99),Vector2.new(99,99)),AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.new(1,120,1,116),Position=UDim2.new(0.5,0,0.5,0),BackgroundTransparency=1,ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.7}),j('UICorner',{CornerRadius=UDim.new(0,8)}),j('Frame',{BackgroundTransparency=0.45,Size=UDim2.fromScale(1,1),Name='Background',ThemeTag={BackgroundColor3='AcrylicMain'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=0.4,Size=UDim2.fromScale(1,1)},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIGradient',{Rotation=90,ThemeTag={Color='AcrylicGradient'}})}),j('ImageLabel',{Image='rbxassetid://9968344105',ImageTransparency=0.98,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('ImageLabel',{Image='rbxassetid://9968344227',ImageTransparency=0.9,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.new(0,128,0,128),Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ThemeTag={ImageTransparency='AcrylicNoise'}},{j('UICorner',{CornerRadius=UDim.new(0,8)})}),j('Frame',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=2},{j('UICorner',{CornerRadius=UDim.new(0,8)}),j('UIStroke',{Transparency=0.5,Thickness=1,ThemeTag={Color='AcrylicBorder'}})})})local m if e(d.Parent.Parent).UseAcrylic then m=i()m.Frame.Parent=l.Frame l.Model=m.Model l.AddParent=m.AddParent l.SetVisibility=m.SetVisibility end return l end end,function()local c,d,e,f,g=b(5)local h=d.Parent.Parent local i=e(h.Creator)local j=function()local j=i.New('Part',{Name='Body',Color=Color3.new(0,0,0),Material=Enum.Material.Glass,Size=Vector3.new(1,1,0),Anchored=true,CanCollide=false,Locked=true,CastShadow=false,Transparency=0.98},{i.New('SpecialMesh',{MeshType=Enum.MeshType.Brick,Offset=Vector3.new(0,0,-1E-6)})})return j end return j end,function()local c,d,e,f,g=b(6)local h,i=function(h,i,j,k,l)return(h-i)*(l-k)/(j-i)+k end,function(h,i)local j=game:GetService'Workspace'.CurrentCamera:ScreenPointToRay(h.X,h.Y)return j.Origin+j.Direction*i end local j=function()local j=game:GetService'Workspace'.CurrentCamera.ViewportSize.Y return h(j,0,2560,8,56)end return{i,j}end,[8]=function()local c,d,e,f,g=b(8)return{Close='rbxassetid://9886659671',Min='rbxassetid://9886659276',Max='rbxassetid://9886659406',Restore='rbxassetid://9886659001'}end,[9]=function()local c,d,e,f,g=b(9)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l=j.New,i.Spring.new return function(m,n,o)o=o or false local p={}p.Title=k('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ThemeTag={TextColor3='Text'}})p.HoverFrame=k('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ThemeTag={BackgroundColor3='Hover'}},{k('UICorner',{CornerRadius=UDim.new(0,4)})})p.Frame=k('TextButton',{Size=UDim2.new(0,0,0,32),Parent=n,ThemeTag={BackgroundColor3='DialogButton'}},{k('UICorner',{CornerRadius=UDim.new(0,4)}),k('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Transparency=0.65,ThemeTag={Color='DialogButtonBorder'}}),p.HoverFrame,p.Title})local q,r=j.SpringMotor(1,p.HoverFrame,'BackgroundTransparency',o)j.AddSignal(p.Frame.MouseEnter,function()r(0.97)end)j.AddSignal(p.Frame.MouseLeave,function()r(1)end)j.AddSignal(p.Frame.MouseButton1Down,function()r(1)end)j.AddSignal(p.Frame.MouseButton1Up,function()r(0.97)end)return p end end,[10]=function()local c,d,e,f,g=b(10)local h,i,j,k=game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,d.Parent.Parent local l,m=e(k.Packages.Flipper),e(k.Creator)local n,o,p,q=l.Spring.new,l.Instant.new,m.New,{Window=nil}function q.Init(r,s)q.Window=s return q end function q.Create(r)local s={Buttons=0}s.TintFrame=p('TextButton',{Text='',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=1,Parent=q.Window.Root},{p('UICorner',{CornerRadius=UDim.new(0,8)})})local t,u=m.SpringMotor(1,s.TintFrame,'BackgroundTransparency',true)s.ButtonHolder=p('Frame',{Size=UDim2.new(1,-40,1,-40),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),BackgroundTransparency=1},{p('UIListLayout',{Padding=UDim.new(0,10),FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder})})s.ButtonHolderFrame=p('Frame',{Size=UDim2.new(1,0,0,70),Position=UDim2.new(0,0,1,-70),ThemeTag={BackgroundColor3='DialogHolder'}},{p('Frame',{Size=UDim2.new(1,0,0,1),ThemeTag={BackgroundColor3='DialogHolderLine'}}),s.ButtonHolder})s.Title=p('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),Text='Dialog',TextColor3=Color3.fromRGB(240,240,240),TextSize=22,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,22),Position=UDim2.fromOffset(20,25),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})s.Scale=p('UIScale',{Scale=1})local v,w=m.SpringMotor(1.1,s.Scale,'Scale')s.Root=p('CanvasGroup',{Size=UDim2.fromOffset(300,165),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),GroupTransparency=1,Parent=s.TintFrame,ThemeTag={BackgroundColor3='Dialog'}},{p('UICorner',{CornerRadius=UDim.new(0,8)}),p('UIStroke',{Transparency=0.5,ThemeTag={Color='DialogBorder'}}),s.Scale,s.Title,s.ButtonHolderFrame})local x,y=m.SpringMotor(1,s.Root,'GroupTransparency')function s.Open(z)e(k).DialogOpen=true s.Scale.Scale=1.1 u(0.75)y(0)w(1)end function s.Close(z)e(k).DialogOpen=false u(1)y(1)w(1.1)s.Root.UIStroke:Destroy()task.wait(0.15)s.TintFrame:Destroy()end function s.Button(z,A,B)s.Buttons=s.Buttons+1 A=A or'Button'B=B or function()end local C=e(k.Components.Button)('',s.ButtonHolder,true)C.Title.Text=A for D,E in next,s.ButtonHolder:GetChildren()do if E:IsA'TextButton'then E.Size=UDim2.new(1/s.Buttons,-(((s.Buttons-1)*10)/s.Buttons),0,32)end end m.AddSignal(C.Frame.MouseButton1Click,function()e(k):SafeCallback(B)pcall(function()s:Close()end)end)return C end return s end return q end,[11]=function()local c,d,e,f,g=b(11)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l=j.New,i.Spring.new return function(m,n,o,p)local q={}q.TitleLabel=k('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Medium,Enum.FontStyle.Normal),Text=m,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})q.DescLabel=k('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=n,TextColor3=Color3.fromRGB(200,200,200),TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),ThemeTag={TextColor3='SubText'}})q.LabelHolder=k('Frame',{AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-28,0,0)},{k('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center}),k('UIPadding',{PaddingBottom=UDim.new(0,13),PaddingTop=UDim.new(0,13)}),q.TitleLabel,q.DescLabel})q.Border=k('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=Color3.fromRGB(0,0,0),ThemeTag={Color='ElementBorder'}})q.Frame=k('TextButton',{Size=UDim2.new(1,0,0,0),BackgroundTransparency=0.89,BackgroundColor3=Color3.fromRGB(130,130,130),Parent=o,AutomaticSize=Enum.AutomaticSize.Y,Text='',LayoutOrder=7,ThemeTag={BackgroundColor3='Element',BackgroundTransparency='ElementTransparency'}},{k('UICorner',{CornerRadius=UDim.new(0,4)}),q.Border,q.LabelHolder})function q.SetTitle(r,s)q.TitleLabel.Text=s end function q.SetDesc(r,s)if s==nil then s=''end if s==''then q.DescLabel.Visible=false else q.DescLabel.Visible=true end q.DescLabel.Text=s end function q.Destroy(r)q.Frame:Destroy()end q:SetTitle(m)q:SetDesc(n)if p then local r,s,t=h.Themes,j.SpringMotor(j.GetThemeProperty'ElementTransparency',q.Frame,'BackgroundTransparency',false,true)j.AddSignal(q.Frame.MouseEnter,function()t(j.GetThemeProperty'ElementTransparency'-j.GetThemeProperty'HoverChange')end)j.AddSignal(q.Frame.MouseLeave,function()t(j.GetThemeProperty'ElementTransparency')end)j.AddSignal(q.Frame.MouseButton1Down,function()t(j.GetThemeProperty'ElementTransparency'+j.GetThemeProperty'HoverChange')end)j.AddSignal(q.Frame.MouseButton1Up,function()t(j.GetThemeProperty'ElementTransparency'-j.GetThemeProperty'HoverChange')end)end return q end end,[12]=function()local c,d,e,f,g=b(12)local h=d.Parent.Parent local i,j,k=e(h.Packages.Flipper),e(h.Creator),e(h.Acrylic)local l,m,n,o=i.Spring.new,i.Instant.new,j.New,{}function o.Init(p,q)o.Holder=n('Frame',{Position=UDim2.new(1,-30,1,-30),Size=UDim2.new(0,310,1,-30),AnchorPoint=Vector2.new(1,1),BackgroundTransparency=1,Parent=q},{n('UIListLayout',{HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Bottom,Padding=UDim.new(0,20)})})end function o.New(p,q)q.Title=q.Title or'Title'q.Content=q.Content or'Content'q.SubContent=q.SubContent or''q.Duration=q.Duration or nil q.Buttons=q.Buttons or{}local r={Closed=false}r.AcrylicPaint=k.AcrylicPaint()r.Title=n('TextLabel',{Position=UDim2.new(0,14,0,17),Text=q.Title,RichText=true,TextColor3=Color3.fromRGB(255,255,255),TextTransparency=0,FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextSize=13,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-12,0,12),TextWrapped=true,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})r.ContentLabel=n('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=q.Content,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextWrapped=true,ThemeTag={TextColor3='Text'}})r.SubContentLabel=n('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=q.SubContent,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,14),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextWrapped=true,ThemeTag={TextColor3='SubText'}})r.LabelHolder=n('Frame',{AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Position=UDim2.fromOffset(14,40),Size=UDim2.new(1,-28,0,0)},{n('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,3)}),r.ContentLabel,r.SubContentLabel})r.CloseButton=n('TextButton',{Text='',Position=UDim2.new(1,-14,0,13),Size=UDim2.fromOffset(20,20),AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1},{n('ImageLabel',{Image=e(d.Parent.Assets).Close,Size=UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,ThemeTag={ImageColor3='Text'}})})r.Root=n('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,1,0),Position=UDim2.fromScale(1,0)},{r.AcrylicPaint.Frame,r.Title,r.CloseButton,r.LabelHolder})if q.Content==''then r.ContentLabel.Visible=false end if q.SubContent==''then r.SubContentLabel.Visible=false end r.Holder=n('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,200),Parent=o.Holder},{r.Root})local s=i.GroupMotor.new{Scale=1,Offset=60}s:onStep(function(t)r.Root.Position=UDim2.new(t.Scale,t.Offset,0,0)end)j.AddSignal(r.CloseButton.MouseButton1Click,function()r:Close()end)function r.Open(t)local u=r.LabelHolder.AbsoluteSize.Y r.Holder.Size=UDim2.new(1,0,0,58+u)s:setGoal{Scale=l(0,{frequency=5}),Offset=l(0,{frequency=5})}end function r.Close(t)if not r.Closed then r.Closed=true task.spawn(function()s:setGoal{Scale=l(1,{frequency=5}),Offset=l(60,{frequency=5})}task.wait(0.4)if e(h).UseAcrylic then r.AcrylicPaint.Model:Destroy()end r.Holder:Destroy()end)end end r:Open()if q.Duration then task.delay(q.Duration,function()r:Close()end)end return r end return o end,[13]=function()local c,d,e,f,g=b(13)local h=d.Parent.Parent local i=e(h.Creator)local j=i.New return function(k,l)local m={}m.Layout=j('UIListLayout',{Padding=UDim.new(0,5)})m.Container=j('Frame',{Size=UDim2.new(1,0,0,26),Position=UDim2.fromOffset(0,24),BackgroundTransparency=1},{m.Layout})m.Root=j('Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,26),LayoutOrder=7,Parent=l},{j('TextLabel',{RichText=true,Text=k,TextTransparency=0,FontFace=Font.new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),TextSize=18,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-16,0,18),Position=UDim2.fromOffset(0,2),ThemeTag={TextColor3='Text'}}),m.Container})i.AddSignal(m.Layout:GetPropertyChangedSignal'AbsoluteContentSize',function()m.Container.Size=UDim2.new(1,0,0,m.Layout.AbsoluteContentSize.Y)m.Root.Size=UDim2.new(1,0,0,m.Layout.AbsoluteContentSize.Y+25)end)return m end end,[14]=function()local c,d,e,f,g=b(14)local h=d.Parent.Parent local i,j=e(h.Packages.Flipper),e(h.Creator)local k,l,m,n,o=j.New,i.Spring.new,i.Instant.new,h.Components,{Window=nil,Tabs={},Containers={},SelectedTab=0,TabCount=0}function o.Init(p,q)o.Window=q return o end function o.GetCurrentTabPos(p)local q,r=o.Window.TabHolder.AbsolutePosition.Y,o.Tabs[o.SelectedTab].Frame.AbsolutePosition.Y return r-q end function o.New(p,q,r,s)local t,u=e(h),o.Window local v=t.Elements o.TabCount=o.TabCount+1 local w,x=o.TabCount,{Selected=false,Name=q,Type='Tab'}if t:GetIcon(r)then r=t:GetIcon(r)end if r==''or nil then r=nil end x.Frame=k('TextButton',{Size=UDim2.new(1,0,0,34),BackgroundTransparency=1,Parent=s,ThemeTag={BackgroundColor3='Tab'}},{k('UICorner',{CornerRadius=UDim.new(0,6)}),k('TextLabel',{AnchorPoint=Vector2.new(0,0.5),Position=r and UDim2.new(0,30,0.5,0)or UDim2.new(0,12,0.5,0),Text=q,RichText=true,TextColor3=Color3.fromRGB(255,255,255),TextTransparency=0,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-12,1,0),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}}),k('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Size=UDim2.fromOffset(16,16),Position=UDim2.new(0,8,0.5,0),BackgroundTransparency=1,Image=r and r or nil,ThemeTag={ImageColor3='Text'}})})local y=k('UIListLayout',{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})x.ContainerFrame=k('ScrollingFrame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Parent=u.ContainerHolder,Visible=false,BottomImage='rbxassetid://6889812791',MidImage='rbxassetid://6889812721',TopImage='rbxassetid://6276641225',ScrollBarImageColor3=Color3.fromRGB(255,255,255),ScrollBarImageTransparency=0.95,ScrollBarThickness=3,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),ScrollingDirection=Enum.ScrollingDirection.Y},{y,k('UIPadding',{PaddingRight=UDim.new(0,10),PaddingLeft=UDim.new(0,1),PaddingTop=UDim.new(0,1),PaddingBottom=UDim.new(0,1)})})j.AddSignal(y:GetPropertyChangedSignal'AbsoluteContentSize',function()x.ContainerFrame.CanvasSize=UDim2.new(0,0,0,y.AbsoluteContentSize.Y+2)end)x.Motor,x.SetTransparency=j.SpringMotor(1,x.Frame,'BackgroundTransparency')j.AddSignal(x.Frame.MouseEnter,function()x.SetTransparency(x.Selected and 0.85 or 0.89)end)j.AddSignal(x.Frame.MouseLeave,function()x.SetTransparency(x.Selected and 0.89 or 1)end)j.AddSignal(x.Frame.MouseButton1Down,function()x.SetTransparency(0.92)end)j.AddSignal(x.Frame.MouseButton1Up,function()x.SetTransparency(x.Selected and 0.85 or 0.89)end)j.AddSignal(x.Frame.MouseButton1Click,function()o:SelectTab(w)end)o.Containers[w]=x.ContainerFrame o.Tabs[w]=x x.Container=x.ContainerFrame x.ScrollFrame=x.Container function x.AddSection(z,A)local B,C={Type='Section'},e(n.Section)(A,x.Container)B.Container=C.Container B.ScrollFrame=x.Container setmetatable(B,v)return B end setmetatable(x,v)return x end function o.SelectTab(p,q)local r=o.Window o.SelectedTab=q for s,t in next,o.Tabs do t.SetTransparency(1)t.Selected=false end o.Tabs[q].SetTransparency(0.89)o.Tabs[q].Selected=true r.TabDisplay.Text=o.Tabs[q].Name r.SelectorPosMotor:setGoal(l(o:GetCurrentTabPos(),{frequency=6}))task.spawn(function()r.ContainerPosMotor:setGoal(l(110,{frequency=10}))r.ContainerBackMotor:setGoal(l(1,{frequency=10}))task.wait(0.15)for u,v in next,o.Containers do v.Visible=false end o.Containers[q].Visible=true r.ContainerPosMotor:setGoal(l(94,{frequency=5}))r.ContainerBackMotor:setGoal(l(0,{frequency=8}))end)end return o end,[15]=function()local c,d,e,f,g=b(15)local h,i=game:GetService'TextService',d.Parent.Parent local j,k=e(i.Packages.Flipper),e(i.Creator)local l=k.New return function(m,n)n=n or false local o={}o.Input=l('TextBox',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',TextColor3=Color3.fromRGB(200,200,200),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(10,0),ThemeTag={TextColor3='Text',PlaceholderColor3='SubText'}})o.Container=l('Frame',{BackgroundTransparency=1,ClipsDescendants=true,Position=UDim2.new(0,6,0,0),Size=UDim2.new(1,-12,1,0)},{o.Input})o.Indicator=l('Frame',{Size=UDim2.new(1,-4,0,1),Position=UDim2.new(0,2,1,0),AnchorPoint=Vector2.new(0,1),BackgroundTransparency=n and 0.5 or 0,ThemeTag={BackgroundColor3=n and'InputIndicator'or'DialogInputLine'}})o.Frame=l('Frame',{Size=UDim2.new(0,0,0,30),BackgroundTransparency=n and 0.9 or 0,Parent=m,ThemeTag={BackgroundColor3=n and'Input'or'DialogInput'}},{l('UICorner',{CornerRadius=UDim.new(0,4)}),l('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Transparency=n and 0.5 or 0.65,ThemeTag={Color=n and'InElementBorder'or'DialogButtonBorder'}}),o.Indicator,o.Container})local p=function()local p,q=2,o.Container.AbsoluteSize.X if not o.Input:IsFocused()or o.Input.TextBounds.X<=q-2*p then o.Input.Position=UDim2.new(0,p,0,0)else local r=o.Input.CursorPosition if r~=-1 then local s=string.sub(o.Input.Text,1,r-1)local t=h:GetTextSize(s,o.Input.TextSize,o.Input.Font,Vector2.new(math.huge,math.huge)).X local u=o.Input.Position.X.Offset+t if u<p then o.Input.Position=UDim2.fromOffset(p-t,0)elseif u>q-p-1 then o.Input.Position=UDim2.fromOffset(q-t-p-1,0)end end end end task.spawn(p)k.AddSignal(o.Input:GetPropertyChangedSignal'Text',p)k.AddSignal(o.Input:GetPropertyChangedSignal'CursorPosition',p)k.AddSignal(o.Input.Focused,function()p()o.Indicator.Size=UDim2.new(1,-2,0,2)o.Indicator.Position=UDim2.new(0,1,1,0)o.Indicator.BackgroundTransparency=0 k.OverrideTag(o.Frame,{BackgroundColor3=n and'InputFocused'or'DialogHolder'})k.OverrideTag(o.Indicator,{BackgroundColor3='Accent'})end)k.AddSignal(o.Input.FocusLost,function()p()o.Indicator.Size=UDim2.new(1,-4,0,1)o.Indicator.Position=UDim2.new(0,2,1,0)o.Indicator.BackgroundTransparency=0.5 k.OverrideTag(o.Frame,{BackgroundColor3=n and'Input'or'DialogInput'})k.OverrideTag(o.Indicator,{BackgroundColor3=n and'InputIndicator'or'DialogInputLine'})end)return o end end,[16]=function()local c,d,e,f,g=b(16)local h,i=d.Parent.Parent,e(d.Parent.Assets)local j,k=e(h.Creator),e(h.Packages.Flipper)local l,m=j.New,j.AddSignal return function(n)local o,p,q={},e(h),function(o,p,q,r)local s={Callback=r or function()end}s.Frame=l('TextButton',{Size=UDim2.new(0,34,1,-8),AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1,Parent=q,Position=p,Text='',ThemeTag={BackgroundColor3='Text'}},{l('UICorner',{CornerRadius=UDim.new(0,7)}),l('ImageLabel',{Image=o,Size=UDim2.fromOffset(16,16),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Name='Icon',ThemeTag={ImageColor3='Text'}})})local t,u=j.SpringMotor(1,s.Frame,'BackgroundTransparency')m(s.Frame.MouseEnter,function()u(0.94)end)m(s.Frame.MouseLeave,function()u(1,true)end)m(s.Frame.MouseButton1Down,function()u(0.96)end)m(s.Frame.MouseButton1Up,function()u(0.94)end)m(s.Frame.MouseButton1Click,s.Callback)s.SetCallback=function(v)s.Callback=v end return s end o.Frame=l('Frame',{Size=UDim2.new(1,0,0,42),BackgroundTransparency=1,Parent=n.Parent},{l('Frame',{Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,16,0,0),BackgroundTransparency=1},{l('UIListLayout',{Padding=UDim.new(0,5),FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder}),l('TextLabel',{RichText=true,Text=n.Title,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}}),l('TextLabel',{RichText=true,Text=n.SubTitle,TextTransparency=0.4,FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),TextSize=12,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.fromScale(0,1),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})}),l('Frame',{BackgroundTransparency=0.5,Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,0),ThemeTag={BackgroundColor3='TitleBarLine'}})})o.CloseButton=q(i.Close,UDim2.new(1,-4,0,4),o.Frame,function()p.Window:Minimize()end)o.MaxButton=q(i.Max,UDim2.new(1,-40,0,4),o.Frame,function()n.Window.Maximize(not n.Window.Maximized)end)o.MinButton=q(i.Min,UDim2.new(1,-80,0,4),o.Frame,function()p.Window:Minimize()end)return o end end,[17]=function()local c,d,e,f,g=b(17)local h,i,j,k=game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,d.Parent.Parent local l,m,n,o,p=e(k.Packages.Flipper),e(k.Creator),e(k.Acrylic),e(d.Parent.Assets),d.Parent local q,r,s=l.Spring.new,l.Instant.new,m.New return function(t)local u,v,w,x,y,z=e(k),{Minimized=false,Maximized=false,Size=t.Size,CurrentPos=0,Position=UDim2.fromOffset((game:GetService'Workspace'.CurrentCamera or j).ViewportSize.X/2-t.Size.X.Offset/2,(game:GetService'Workspace'.CurrentCamera or j).ViewportSize.Y/2-t.Size.Y.Offset/2)},false local A,B=false local C=false v.AcrylicPaint=n.AcrylicPaint()local D,E=s('Frame',{Size=UDim2.fromOffset(4,0),BackgroundColor3=Color3.fromRGB(76,194,255),Position=UDim2.fromOffset(0,17),AnchorPoint=Vector2.new(0,0.5),ThemeTag={BackgroundColor3='Accent'}},{s('UICorner',{CornerRadius=UDim.new(0,2)})}),s('Frame',{Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,Position=UDim2.new(1,-20,1,-20)})v.TabHolder=s('ScrollingFrame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ScrollBarImageTransparency=1,ScrollBarThickness=0,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0),ScrollingDirection=Enum.ScrollingDirection.Y},{s('UIListLayout',{Padding=UDim.new(0,4)})})local F=s('Frame',{Size=UDim2.new(0,t.TabWidth,1,-66),Position=UDim2.new(0,12,0,54),BackgroundTransparency=1,ClipsDescendants=true},{v.TabHolder,D})v.TabDisplay=s('TextLabel',{RichText=true,Text='Tab',TextTransparency=0,FontFace=Font.new('rbxassetid://12187365364',Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),TextSize=28,TextXAlignment='Left',TextYAlignment='Center',Size=UDim2.new(1,-16,0,28),Position=UDim2.fromOffset(t.TabWidth+26,56),BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})v.ContainerHolder=s('CanvasGroup',{Size=UDim2.new(1,-t.TabWidth-32,1,-102),Position=UDim2.fromOffset(t.TabWidth+26,90),BackgroundTransparency=1})v.Root=s('Frame',{BackgroundTransparency=1,Size=v.Size,Position=v.Position,Parent=t.Parent},{v.AcrylicPaint.Frame,v.TabDisplay,v.ContainerHolder,F,E})v.TitleBar=e(d.Parent.TitleBar){Title=t.Title,SubTitle=t.SubTitle,Parent=v.Root,Window=v}if e(k).UseAcrylic then v.AcrylicPaint.AddParent(v.Root)end local G,H=l.GroupMotor.new{X=v.Size.X.Offset,Y=v.Size.Y.Offset},l.GroupMotor.new{X=v.Position.X.Offset,Y=v.Position.Y.Offset}v.SelectorPosMotor=l.SingleMotor.new(17)v.SelectorSizeMotor=l.SingleMotor.new(0)v.ContainerBackMotor=l.SingleMotor.new(0)v.ContainerPosMotor=l.SingleMotor.new(94)G:onStep(function(I)v.Root.Size=UDim2.new(0,I.X,0,I.Y)end)H:onStep(function(I)v.Root.Position=UDim2.new(0,I.X,0,I.Y)end)local I,J=0,0 v.SelectorPosMotor:onStep(function(K)D.Position=UDim2.new(0,0,0,K+17)local L=tick()local M=L-J if I~=nil then v.SelectorSizeMotor:setGoal(q((math.abs(K-I)/(M*60))+16))I=K end J=L end)v.SelectorSizeMotor:onStep(function(K)D.Size=UDim2.new(0,4,0,K)end)v.ContainerBackMotor:onStep(function(K)v.ContainerHolder.GroupTransparency=K end)v.ContainerPosMotor:onStep(function(K)v.ContainerHolder.Position=UDim2.fromOffset(t.TabWidth+26,K)end)m.AddSignal(h.WindowFocusReleased,function()w=false A=false end)m.AddSignal(v.Root:GetPropertyChangedSignal'Visible',function()w=false A=false end)local K,L v.Maximize=function(M,N,O)local wasMaximized=v.Maximized v.Maximized=M v.TitleBar.MaxButton.Frame.Icon.Image=M and o.Restore or o.Max if M and not wasMaximized then K=v.Size.X.Offset L=v.Size.Y.Offset end local P,Q=M and (game:GetService'Workspace'.CurrentCamera or j).ViewportSize.X or K,M and (game:GetService'Workspace'.CurrentCamera or j).ViewportSize.Y or L G:setGoal{X=l[O and'Instant'or'Spring'].new(P,{frequency=6}),Y=l[O and'Instant'or'Spring'].new(Q,{frequency=6})}v.Size=UDim2.fromOffset(P,Q)if not N then H:setGoal{X=q(M and 0 or v.Position.X.Offset,{frequency=6}),Y=q(M and 0 or v.Position.Y.Offset,{frequency=6})}end end m.AddSignal(v.TitleBar.Frame.InputBegan,function(M)if M.UserInputType==Enum.UserInputType.MouseButton1 or M.UserInputType==Enum.UserInputType.Touch then w=true y=M.Position z=v.Root.Position if v.Maximized then z=UDim2.fromOffset(i.X-(i.X*((K-100)/v.Root.AbsoluteSize.X)),i.Y-(i.Y*(L/v.Root.AbsoluteSize.Y)))end m.AddSignal(M.Changed,function()if M.UserInputState==Enum.UserInputState.End then w=false end end)end end)m.AddSignal(v.TitleBar.Frame.InputChanged,function(M)if M.UserInputType==Enum.UserInputType.MouseMovement or M.UserInputType==Enum.UserInputType.Touch then x=M end end)m.AddSignal(E.InputBegan,function(M)if M.UserInputType==Enum.UserInputType.MouseButton1 or M.UserInputType==Enum.UserInputType.Touch then A=true B=M.Position end end)m.AddSignal(h.InputChanged,function(M)if M==x and w then local N=M.Position-y v.Position=UDim2.fromOffset(z.X.Offset+N.X,z.Y.Offset+N.Y)H:setGoal{X=r(v.Position.X.Offset),Y=r(v.Position.Y.Offset)}if v.Maximized then v.Maximize(false,true,true)end end if(M.UserInputType==Enum.UserInputType.MouseMovement or M.UserInputType==Enum.UserInputType.Touch)and A then local N,O=M.Position-B,v.Size local P=Vector3.new(O.X.Offset,O.Y.Offset,0)+Vector3.new(1,1,0)*N local Q=Vector2.new(math.clamp(P.X,470,2048),math.clamp(P.Y,380,2048))G:setGoal{X=l.Instant.new(Q.X),Y=l.Instant.new(Q.Y)}end end)m.AddSignal(h.InputEnded,function(M)if A==true or M.UserInputType==Enum.UserInputType.Touch then A=false v.Size=UDim2.fromOffset(G:getValue().X,G:getValue().Y)end end)m.AddSignal(v.TabHolder.UIListLayout:GetPropertyChangedSignal'AbsoluteContentSize',function()v.TabHolder.CanvasSize=UDim2.new(0,0,0,v.TabHolder.UIListLayout.AbsoluteContentSize.Y)end)function v.Minimize(M)v.Minimized=not v.Minimized v.Root.Visible=not v.Minimized if not C then C=true local N='Ctrl esquerdo' u:Notify{Title='Interface',Content='Press '..N..' to toggle the inteface.',Duration=6}end end function v.Destroy(M)if e(k).UseAcrylic then v.AcrylicPaint.Model:Destroy()end v.Root:Destroy()end local M=e(p.Dialog):Init(v)function v.Dialog(N,O)local P=M:Create()P.Title.Text=O.Title local Q=s('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=O.Content,TextColor3=Color3.fromRGB(240,240,240),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Size=UDim2.new(1,-40,1,0),Position=UDim2.fromOffset(20,60),BackgroundTransparency=1,Parent=P.Root,ClipsDescendants=false,ThemeTag={TextColor3='Text'}})s('UISizeConstraint',{MinSize=Vector2.new(300,165),MaxSize=Vector2.new(620,math.huge),Parent=P.Root})P.Root.Size=UDim2.fromOffset(Q.TextBounds.X+40,165)if Q.TextBounds.X+40>v.Size.X.Offset-120 then P.Root.Size=UDim2.fromOffset(v.Size.X.Offset-120,165)Q.TextWrapped=true P.Root.Size=UDim2.fromOffset(v.Size.X.Offset-120,Q.TextBounds.Y+150)end for R,S in next,O.Buttons do P:Button(S.Title,S.Callback)end P:Open()end local N=e(p.Tab):Init(v)function v.AddTab(O,P)return N:New(P.Title,P.Icon,v.TabHolder)end function v.SelectTab(O,P)N:SelectTab(P)end m.AddSignal(v.TabHolder:GetPropertyChangedSignal'CanvasPosition',function()I=N:GetCurrentTabPos()+16 J=0 v.SelectorPosMotor:setGoal(r(N:GetCurrentTabPos()))end)return v end end,[18]=function()local c,d,e,f,g=b(18)local h=d.Parent local i,j,k=e(h.Themes),e(h.Packages.Flipper),{Registry={},Signals={},TransparencyMotors={},DefaultProperties={ScreenGui={ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},Frame={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0},ScrollingFrame={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),ScrollBarImageColor3=Color3.new(0,0,0)},TextLabel={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),BackgroundTransparency=1,TextSize=14},TextButton={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),AutoButtonColor=false,Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),TextSize=14},TextBox={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),ClearTextOnFocus=false,Font=Enum.Font.SourceSans,Text='',TextColor3=Color3.new(0,0,0),TextSize=14},ImageLabel={BackgroundTransparency=1,BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0},ImageButton={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),AutoButtonColor=false},CanvasGroup={BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),BorderSizePixel=0}}}local l=function(l,m)if m.ThemeTag then k.AddThemeObject(l,m.ThemeTag)end end function k.AddSignal(m,n)table.insert(k.Signals,m:Connect(n))end function k.Disconnect()for m=#k.Signals,1,-1 do local n=table.remove(k.Signals,m)n:Disconnect()end end function k.GetThemeProperty(m)if i[e(h).Theme][m]then return i[e(h).Theme][m]end return i.Dark[m]end function k.UpdateTheme()for m,n in next,k.Registry do for o,p in next,n.Properties do m[o]=k.GetThemeProperty(p)end end for o,p in next,k.TransparencyMotors do p:setGoal(j.Instant.new(k.GetThemeProperty'ElementTransparency'))end end function k.AddThemeObject(m,n)local o=#k.Registry+1 local p={Object=m,Properties=n,Idx=o}k.Registry[m]=p k.UpdateTheme()return m end function k.OverrideTag(m,n)k.Registry[m].Properties=n k.UpdateTheme()end function k.New(m,n,o)local p=Instance.new(m)for q,r in next,k.DefaultProperties[m]or{}do p[q]=r end for s,t in next,n or{}do if s~='ThemeTag'then p[s]=t end end for u,v in next,o or{}do v.Parent=p end l(p,n)return p end function k.SpringMotor(m,n,o,p,s)p=p or false s=s or false local t=j.SingleMotor.new(m)t:onStep(function(u)n[o]=u end)if s then table.insert(k.TransparencyMotors,t)end local u=function(u,v)v=v or false if not p then if not v then if o=='BackgroundTransparency'and e(h).DialogOpen then return end end end t:setGoal(j.Spring.new(u,{frequency=8}))end return t,u end return k end,[19]=function()local c,d,e,f,g=b(19)local h={}for i,j in next,d:GetChildren()do table.insert(h,e(j))end return h end,[20]=function()local c,d,e,f,g=b(20)local h=d.Parent.Parent local i=e(h.Creator)local j,k,l=i.New,h.Components,{}l.__index=l l.__type='Button'function l.New(m,n)assert(n.Title,'Button - Missing Title')n.Callback=n.Callback or function()end local o=e(k.Element)(n.Title,n.Description,m.Container,true)local p=j('ImageLabel',{Image='rbxassetid://10709791437',Size=UDim2.fromOffset(16,16),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),BackgroundTransparency=1,Parent=o.Frame,ThemeTag={ImageColor3='Text'}})i.AddSignal(o.Frame.MouseButton1Click,function()m.Library:SafeCallback(n.Callback)end)return o end return l end,[21]=function()local c,d,e,f,g=b(21)local h,i,j,k=game:GetService'UserInputService',game:GetService'TouchInputService',game:GetService'RunService',game:GetService'Players'local l,m=j.RenderStepped,k.LocalPlayer local n,o=m:GetMouse(),d.Parent.Parent local p=e(o.Creator)local s,t,u=p.New,o.Components,{}u.__index=u u.__type='Colorpicker'function u.New(v,w,x)local y=v.Library assert(x.Title,'Colorpicker - Missing Title')assert(x.Default,'AddColorPicker: Missing default value.')local z={Value=x.Default,Transparency=x.Transparency or 0,Type='Colorpicker',Title=type(x.Title)=='string'and x.Title or'Colorpicker',Callback=x.Callback or function(z)end}function z.SetHSVFromRGB(A,B)local C,D,E=Color3.toHSV(B)z.Hue=C z.Sat=D z.Vib=E end z:SetHSVFromRGB(z.Value)local A=e(t.Element)(x.Title,x.Description,v.Container,true)z.SetTitle=A.SetTitle z.SetDesc=A.SetDesc local B=s('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=z.Value,Parent=A.Frame},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local aa,ab=s('ImageLabel',{Size=UDim2.fromOffset(26,26),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),Parent=A.Frame,Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40)},{s('UICorner',{CornerRadius=UDim.new(0,4)}),B}),function()local C=e(t.Dialog):Create()C.Title.Text=z.Title C.Root.Size=UDim2.fromOffset(430,330)local D,E,F,G,H,I=z.Hue,z.Sat,z.Vib,z.Transparency,function()local D=e(t.Textbox)()D.Frame.Parent=C.Root D.Frame.Size=UDim2.new(0,90,0,32)return D end,function(D,E)return s('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Medium,Enum.FontStyle.Normal),Text=D,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,32),Position=E,BackgroundTransparency=1,Parent=C.Root,ThemeTag={TextColor3='Text'}})end local J,K=function()local J=Color3.fromHSV(D,E,F)return{R=math.floor(J.r*255),G=math.floor(J.g*255),B=math.floor(J.b*255)}end,s('ImageLabel',{Size=UDim2.new(0,18,0,18),ScaleType=Enum.ScaleType.Fit,AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=4805639000'})local L,M=s('ImageLabel',{Size=UDim2.fromOffset(180,160),Position=UDim2.fromOffset(20,55),Image='rbxassetid://4155801252',BackgroundColor3=z.Value,BackgroundTransparency=0,Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),K}),s('Frame',{BackgroundColor3=z.Value,Size=UDim2.fromScale(1,1),BackgroundTransparency=z.Transparency},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local N,O=s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Position=UDim2.fromOffset(112,220),Size=UDim2.fromOffset(88,24),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),s('UIStroke',{Thickness=2,Transparency=0.75}),M}),s('Frame',{BackgroundColor3=z.Value,Size=UDim2.fromScale(1,1),BackgroundTransparency=0},{s('UICorner',{CornerRadius=UDim.new(0,4)})})local P,Q=s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Position=UDim2.fromOffset(20,220),Size=UDim2.fromOffset(88,24),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(0,4)}),s('UIStroke',{Thickness=2,Transparency=0.75}),O}),{}for R=0,1,0.1 do table.insert(Q,ColorSequenceKeypoint.new(R,Color3.fromHSV(R,1,1)))end local R,S=s('UIGradient',{Color=ColorSequence.new(Q),Rotation=90}),s('Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.fromOffset(0,5),BackgroundTransparency=1})local T,U,V=s('ImageLabel',{Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',Parent=S,ThemeTag={ImageColor3='DialogInput'}}),s('Frame',{Size=UDim2.fromOffset(12,190),Position=UDim2.fromOffset(210,55),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(1,0)}),R,S}),H()V.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,55)I('Hex',UDim2.fromOffset(x.Transparency and 360 or 340,55))local W=H()W.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,95)I('Red',UDim2.fromOffset(x.Transparency and 360 or 340,95))local X=H()X.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,135)I('Green',UDim2.fromOffset(x.Transparency and 360 or 340,135))local Y=H()Y.Frame.Position=UDim2.fromOffset(x.Transparency and 260 or 240,175)I('Blue',UDim2.fromOffset(x.Transparency and 360 or 340,175))local Z if x.Transparency then Z=H()Z.Frame.Position=UDim2.fromOffset(260,215)I('Alpha',UDim2.fromOffset(360,215))end local _,aa,ab if x.Transparency then local ac=s('Frame',{Size=UDim2.new(1,0,1,-10),Position=UDim2.fromOffset(0,5),BackgroundTransparency=1})aa=s('ImageLabel',{Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',Parent=ac,ThemeTag={ImageColor3='DialogInput'}})ab=s('Frame',{Size=UDim2.fromScale(1,1)},{s('UIGradient',{Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)},Rotation=270}),s('UICorner',{CornerRadius=UDim.new(1,0)})})_=s('Frame',{Size=UDim2.fromOffset(12,190),Position=UDim2.fromOffset(230,55),Parent=C.Root,BackgroundTransparency=1},{s('UICorner',{CornerRadius=UDim.new(1,0)}),s('ImageLabel',{Image='http://www.roblox.com/asset/?id=14204231522',ImageTransparency=0.45,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(40,40),BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Parent=C.Root},{s('UICorner',{CornerRadius=UDim.new(1,0)})}),ab,ac})end local ac=function()L.BackgroundColor3=Color3.fromHSV(D,1,1)T.Position=UDim2.new(0,-1,D,-6)K.Position=UDim2.new(E,0,1-F,0)O.BackgroundColor3=Color3.fromHSV(D,E,F)V.Input.Text='#'..Color3.fromHSV(D,E,F):ToHex()W.Input.Text=J().R X.Input.Text=J().G Y.Input.Text=J().B if x.Transparency then ab.BackgroundColor3=Color3.fromHSV(D,E,F)O.BackgroundTransparency=G aa.Position=UDim2.new(0,-1,1-G,-6)Z.Input.Text=e(o):Round((1-G)*100,0)..'%'end end p.AddSignal(V.Input.FocusLost,function(ad)if ad then local ae,af=pcall(Color3.fromHex,V.Input.Text)if ae and typeof(af)=='Color3'then D,E,F=Color3.toHSV(af)end end ac()end)p.AddSignal(W.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,W.Input.Text,ae.G,ae.B)if af and typeof(ag)=='Color3'then if tonumber(W.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)p.AddSignal(X.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,ae.R,X.Input.Text,ae.B)if af and typeof(ag)=='Color3'then if tonumber(X.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)p.AddSignal(Y.Input.FocusLost,function(ad)if ad then local ae=J()local af,ag=pcall(Color3.fromRGB,ae.R,ae.G,Y.Input.Text)if af and typeof(ag)=='Color3'then if tonumber(Y.Input.Text)<=255 then D,E,F=Color3.toHSV(ag)end end end ac()end)if x.Transparency then p.AddSignal(Z.Input.FocusLost,function(ad)if ad then pcall(function()local ae=tonumber(Z.Input.Text)if ae>=0 and ae<=100 then G=1-ae*0.01 end end)end ac()end)end p.AddSignal(L.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 or ad.UserInputType==Enum.UserInputType.Touch then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=L.AbsolutePosition.X local af=ae+L.AbsoluteSize.X local ag,ah=math.clamp(n.X,ae,af),L.AbsolutePosition.Y local ai=ah+L.AbsoluteSize.Y local aj=math.clamp(n.Y,ah,ai)E=(ag-ae)/(af-ae)F=1-((aj-ah)/(ai-ah))ac()l:Wait()end end end)p.AddSignal(U.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 or ad.UserInputType==Enum.UserInputType.Touch then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=U.AbsolutePosition.Y local af=ae+U.AbsoluteSize.Y local ag=math.clamp(n.Y,ae,af)D=((ag-ae)/(af-ae))ac()l:Wait()end end end)if x.Transparency then p.AddSignal(_.InputBegan,function(ad)if ad.UserInputType==Enum.UserInputType.MouseButton1 then while h:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)do local ae=_.AbsolutePosition.Y local af=ae+_.AbsoluteSize.Y local ag=math.clamp(n.Y,ae,af)G=1-((ag-ae)/(af-ae))ac()l:Wait()end end end)end ac()C:Button('Done',function()z:SetValue({D,E,F},G)end)C:Button'Cancel'C:Open()end function z.Display(ac)z.Value=Color3.fromHSV(z.Hue,z.Sat,z.Vib)B.BackgroundColor3=z.Value B.BackgroundTransparency=z.Transparency u.Library:SafeCallback(z.Callback,z.Value)u.Library:SafeCallback(z.Changed,z.Value)end function z.SetValue(ac,ad,ae)local af=Color3.fromHSV(ad[1],ad[2],ad[3])z.Transparency=ae or 0 z:SetHSVFromRGB(af)z:Display()end function z.SetValueRGB(ac,ad,ae)z.Transparency=ae or 0 z:SetHSVFromRGB(ad)z:Display()end function z.OnChanged(ac,ad)z.Changed=ad ad(z.Value)end function z.Destroy(ac)A:Destroy()y.Options[w]=nil end p.AddSignal(A.Frame.MouseButton1Click,function()ab()end)z:Display()y.Options[w]=z return z end return u end,[22]=function()local aa,ab,ac,ad,ae=b(22)local af,ag,ah,ai,aj=game:GetService'TweenService',game:GetService'UserInputService',game:GetService'Players'.LocalPlayer:GetMouse(),game:GetService'Workspace'.CurrentCamera,ab.Parent.Parent local c,d=ac(aj.Creator),ac(aj.Packages.Flipper)local e,f,g=c.New,aj.Components,{}g.__index=g g.__type='Dropdown'function g.New(h,i,j)local k,l,m=h.Library,{Values=j.Values,Value=j.Default,Multi=j.Multi,Buttons={},Opened=false,Type='Dropdown',Callback=j.Callback or function()end},ac(f.Element)(j.Title,j.Description,h.Container,false)m.DescLabel.Size=UDim2.new(1,-170,0,14)l.SetTitle=m.SetTitle l.SetDesc=m.SetDesc local n,o=e('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),Text='Value',TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,-30,0,14),Position=UDim2.new(0,8,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,TextTruncate=Enum.TextTruncate.AtEnd,ThemeTag={TextColor3='Text'}}),e('ImageLabel',{Image='rbxassetid://10709790948',Size=UDim2.fromOffset(16,16),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-8,0.5,0),BackgroundTransparency=1,ThemeTag={ImageColor3='SubText'}})local p,s=e('TextButton',{Size=UDim2.fromOffset(160,30),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=0.9,Parent=m.Frame,ThemeTag={BackgroundColor3='DropdownFrame'}},{e('UICorner',{CornerRadius=UDim.new(0,5)}),e('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='InElementBorder'}}),o,n}),e('UIListLayout',{Padding=UDim.new(0,3)})local t=e('ScrollingFrame',{Size=UDim2.new(1,-5,1,-10),Position=UDim2.fromOffset(5,5),BackgroundTransparency=1,BottomImage='rbxassetid://6889812791',MidImage='rbxassetid://6889812721',TopImage='rbxassetid://6276641225',ScrollBarImageColor3=Color3.fromRGB(255,255,255),ScrollBarImageTransparency=0.95,ScrollBarThickness=4,BorderSizePixel=0,CanvasSize=UDim2.fromScale(0,0)},{s})local u=e('Frame',{Size=UDim2.fromScale(1,0.6),ThemeTag={BackgroundColor3='DropdownHolder'}},{t,e('UICorner',{CornerRadius=UDim.new(0,7)}),e('UIStroke',{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='DropdownBorder'}}),e('ImageLabel',{BackgroundTransparency=1,Image='http://www.roblox.com/asset/?id=5554236805',ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(23,23,277,277),Size=UDim2.fromScale(1,1)+UDim2.fromOffset(30,30),Position=UDim2.fromOffset(-15,-15),ImageColor3=Color3.fromRGB(0,0,0),ImageTransparency=0.1})})local v=e('Frame',{BackgroundTransparency=1,Size=UDim2.fromOffset(170,300),Parent=h.Library.GUI,Visible=false},{u,e('UISizeConstraint',{MinSize=Vector2.new(170,0)})})table.insert(k.OpenFrames,v)local w,x=function()local w=0 if ai.ViewportSize.Y-p.AbsolutePosition.Y<v.AbsoluteSize.Y-5 then w=v.AbsoluteSize.Y-5-(ai.ViewportSize.Y-p.AbsolutePosition.Y)+40 end v.Position=UDim2.fromOffset(p.AbsolutePosition.X-1,p.AbsolutePosition.Y-5-w)end,0 local y,z=function()if#l.Values>10 then v.Size=UDim2.fromOffset(x,392)else v.Size=UDim2.fromOffset(x,s.AbsoluteContentSize.Y+10)end end,function()t.CanvasSize=UDim2.fromOffset(0,s.AbsoluteContentSize.Y)end w()y()c.AddSignal(p:GetPropertyChangedSignal'AbsolutePosition',w)c.AddSignal(p.MouseButton1Click,function()l:Open()end)c.AddSignal(ag.InputBegan,function(A)if A.UserInputType==Enum.UserInputType.MouseButton1 or A.UserInputType==Enum.UserInputType.Touch then local B,C=u.AbsolutePosition,u.AbsoluteSize if ah.X<B.X or ah.X>B.X+C.X or ah.Y<(B.Y-20-1)or ah.Y>B.Y+C.Y then l:Close()end end end)local A=h.ScrollFrame function l.Open(B)l.Opened=true A.ScrollingEnabled=false v.Visible=true af:Create(u,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromScale(1,1)}):Play()end function l.Close(B)l.Opened=false A.ScrollingEnabled=true u.Size=UDim2.fromScale(1,0.6)v.Visible=false end function l.Display(B)local C,D=l.Values,''if j.Multi then for E,F in next,C do if l.Value[F]then D=D..F..', 'end end D=D:sub(1,#D-2)else D=l.Value or''end n.Text=(D==''and'--'or D)end function l.GetActiveValues(B)if j.Multi then local C={}for D,E in next,l.Value do table.insert(C,D)end return C else return l.Value and 1 or 0 end end function l.BuildDropdownList(B)local C,D=l.Values,{}for E,F in next,t:GetChildren()do if not F:IsA'UIListLayout'then F:Destroy()end end local G=0 for H,I in next,C do local J={}G=G+1 local K,L=e('Frame',{Size=UDim2.fromOffset(4,14),BackgroundColor3=Color3.fromRGB(76,194,255),Position=UDim2.fromOffset(-1,16),AnchorPoint=Vector2.new(0,0.5),ThemeTag={BackgroundColor3='Accent'}},{e('UICorner',{CornerRadius=UDim.new(0,2)})}),e('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text=I,TextColor3=Color3.fromRGB(200,200,200),TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(10,0),Name='ButtonLabel',ThemeTag={TextColor3='Text'}})local M,N=(e('TextButton',{Size=UDim2.new(1,-5,0,32),BackgroundTransparency=1,ZIndex=23,Text='',Parent=t,ThemeTag={BackgroundColor3='DropdownOption'}},{K,L,e('UICorner',{CornerRadius=UDim.new(0,6)})}))if j.Multi then N=l.Value[I]else N=l.Value==I end local O,P=c.SpringMotor(1,M,'BackgroundTransparency')local Q,R=c.SpringMotor(1,K,'BackgroundTransparency')local S=d.SingleMotor.new(6)S:onStep(function(T)K.Size=UDim2.new(0,4,0,T)end)c.AddSignal(M.MouseEnter,function()P(N and 0.85 or 0.89)end)c.AddSignal(M.MouseLeave,function()P(N and 0.89 or 1)end)c.AddSignal(M.MouseButton1Down,function()P(0.92)end)c.AddSignal(M.MouseButton1Up,function()P(N and 0.85 or 0.89)end)function J.UpdateButton(T)if j.Multi then N=l.Value[I]if N then P(0.89)end else N=l.Value==I P(N and 0.89 or 1)end S:setGoal(d.Spring.new(N and 14 or 6,{frequency=6}))R(N and 0 or 1)end L.InputBegan:Connect(function(T)if T.UserInputType==Enum.UserInputType.MouseButton1 or T.UserInputType==Enum.UserInputType.Touch then local U=not N if l:GetActiveValues()==1 and not U and not j.AllowNull then else if j.Multi then N=U l.Value[I]=N and true or nil else N=U l.Value=N and I or nil for V,W in next,D do W:UpdateButton()end end J:UpdateButton()l:Display()k:SafeCallback(l.Callback,l.Value)k:SafeCallback(l.Changed,l.Value)end end end)J:UpdateButton()l:Display()D[M]=J end x=0 for J,K in next,D do if J.ButtonLabel then if J.ButtonLabel.TextBounds.X>x then x=J.ButtonLabel.TextBounds.X end end end x=x+30 z()y()end function l.SetValues(B,C)if C then l.Values=C end l:BuildDropdownList()end function l.OnChanged(B,C)l.Changed=C C(l.Value)end function l.SetValue(B,C)if l.Multi then local D={}for E,F in next,C do if table.find(l.Values,E)then D[E]=true end end l.Value=D else if not C then l.Value=nil elseif table.find(l.Values,C)then l.Value=C end end l:BuildDropdownList()k:SafeCallback(l.Callback,l.Value)k:SafeCallback(l.Changed,l.Value)end function l.Destroy(B)m:Destroy()k.Options[i]=nil end l:BuildDropdownList()l:Display()local B={}if type(j.Default)=='string'then local C=table.find(l.Values,j.Default)if C then table.insert(B,C)end elseif type(j.Default)=='table'then for C,D in next,j.Default do local E=table.find(l.Values,D)if E then table.insert(B,E)end end elseif type(j.Default)=='number'and l.Values[j.Default]~=nil then table.insert(B,j.Default)end if next(B)then for C=1,#B do local D=B[C]if j.Multi then l.Value[l.Values[D]]=true else l.Value=l.Values[D]end if not j.Multi then break end end l:BuildDropdownList()l:Display()end k.Options[i]=l return l end return g end,[23]=function()local aa,ab,ac,ad,ae=b(23)local af=ab.Parent.Parent local ag=ac(af.Creator)local ah,ai,aj,c=ag.New,ag.AddSignal,af.Components,{}c.__index=c c.__type='Input'function c.New(d,e,f)local g=d.Library assert(f.Title,'Input - Missing Title')f.Callback=f.Callback or function()end local h,i={Value=f.Default or'',Numeric=f.Numeric or false,Finished=f.Finished or false,Callback=f.Callback or function(h)end,Type='Input'},ac(aj.Element)(f.Title,f.Description,d.Container,false)h.SetTitle=i.SetTitle h.SetDesc=i.SetDesc local j=ac(aj.Textbox)(i.Frame,true)j.Frame.Position=UDim2.new(1,-10,0.5,0)j.Frame.AnchorPoint=Vector2.new(1,0.5)j.Frame.Size=UDim2.fromOffset(160,30)j.Input.Text=f.Default or''j.Input.PlaceholderText=f.Placeholder or''local k=j.Input function h.SetValue(l,m)if f.MaxLength and#m>f.MaxLength then m=m:sub(1,f.MaxLength)end if h.Numeric then if(not tonumber(m))and m:len()>0 then m=h.Value end end h.Value=m k.Text=m g:SafeCallback(h.Callback,h.Value)g:SafeCallback(h.Changed,h.Value)end if h.Finished then ai(k.FocusLost,function(l)if not l then return end h:SetValue(k.Text)end)else ai(k:GetPropertyChangedSignal'Text',function()h:SetValue(k.Text)end)end function h.OnChanged(l,m)h.Changed=m m(h.Value)end function h.Destroy(l)i:Destroy()g.Options[e]=nil end g.Options[e]=h return h end return c end,[24]=function()local aa,ab,ac,ad,ae=b(24)local af,ag=game:GetService'UserInputService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Keybind'function c.New(d,e,f)local g=d.Library assert(f.Title,'KeyBind - Missing Title')assert(f.Default,'KeyBind - Missing default value.')local h,i,j={Value=f.Default,Toggled=false,Mode=f.Mode or'Toggle',Type='Keybind',Callback=f.Callback or function(h)end,ChangedCallback=f.ChangedCallback or function(h)end},false,ac(aj.Element)(f.Title,f.Description,d.Container,true)h.SetTitle=j.SetTitle h.SetDesc=j.SetDesc local k=ai('TextLabel',{FontFace=Font.new('rbxasset://fonts/families/GothamSSm.json',Enum.FontWeight.Regular,Enum.FontStyle.Normal),Text=f.Default,TextColor3=Color3.fromRGB(240,240,240),TextSize=13,TextXAlignment=Enum.TextXAlignment.Center,Size=UDim2.new(0,0,0,14),Position=UDim2.new(0,0,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(255,255,255),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,ThemeTag={TextColor3='Text'}})local l=ai('TextButton',{Size=UDim2.fromOffset(0,30),Position=UDim2.new(1,-10,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=0.9,Parent=j.Frame,AutomaticSize=Enum.AutomaticSize.X,ThemeTag={BackgroundColor3='Keybind'}},{ai('UICorner',{CornerRadius=UDim.new(0,5)}),ai('UIPadding',{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)}),ai('UIStroke',{Transparency=0.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,ThemeTag={Color='InElementBorder'}}),k})function h.GetState(m)if af:GetFocusedTextBox()and h.Mode~='Always'then return false end if h.Mode=='Always'then return true elseif h.Mode=='Hold'then if h.Value=='None'then return false end local n=h.Value if n=='MouseLeft'or n=='MouseRight'then return n=='MouseLeft'and af:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)or n=='MouseRight'and af:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)else return af:IsKeyDown(Enum.KeyCode[h.Value])end else return h.Toggled end end function h.SetValue(m,n,o)n=n or h.Key o=o or h.Mode k.Text=n h.Value=n h.Mode=o end function h.OnClick(m,n)h.Clicked=n end function h.OnChanged(m,n)h.Changed=n n(h.Value)end function h.DoClick(m)g:SafeCallback(h.Callback,h.Toggled)g:SafeCallback(h.Clicked,h.Toggled)end function h.Destroy(m)j:Destroy()g.Options[e]=nil end ah.AddSignal(l.InputBegan,function(m)if m.UserInputType==Enum.UserInputType.MouseButton1 or m.UserInputType==Enum.UserInputType.Touch then i=true k.Text='...'wait(0.2)local n n=af.InputBegan:Connect(function(o)local p if o.UserInputType==Enum.UserInputType.Keyboard then p=o.KeyCode.Name elseif o.UserInputType==Enum.UserInputType.MouseButton1 then p='MouseLeft'elseif o.UserInputType==Enum.UserInputType.MouseButton2 then p='MouseRight'end local s s=af.InputEnded:Connect(function(t)if t.KeyCode.Name==p or p=='MouseLeft'and t.UserInputType==Enum.UserInputType.MouseButton1 or p=='MouseRight'and t.UserInputType==Enum.UserInputType.MouseButton2 then i=false k.Text=p h.Value=p g:SafeCallback(h.ChangedCallback,t.KeyCode or t.UserInputType)g:SafeCallback(h.Changed,t.KeyCode or t.UserInputType)n:Disconnect()s:Disconnect()end end)end)end end)ah.AddSignal(af.InputBegan,function(m)if not i and not af:GetFocusedTextBox()then if h.Mode=='Toggle'then local n=h.Value if n=='MouseLeft'or n=='MouseRight'then if n=='MouseLeft'and m.UserInputType==Enum.UserInputType.MouseButton1 or n=='MouseRight'and m.UserInputType==Enum.UserInputType.MouseButton2 then h.Toggled=not h.Toggled h:DoClick()end elseif m.UserInputType==Enum.UserInputType.Keyboard then if m.KeyCode.Name==n then h.Toggled=not h.Toggled h:DoClick()end end end end end)g.Options[e]=h return h end return c end,[25]=function()local aa,ab,ac,ad,ae=b(25)local af=ab.Parent.Parent local ag,ah,ai,aj=af.Components,ac(af.Packages.Flipper),ac(af.Creator),{}aj.__index=aj aj.__type='Paragraph'function aj.New(c,d)assert(d.Title,'Paragraph - Missing Title')d.Content=d.Content or''local e=ac(ag.Element)(d.Title,d.Content,aj.Container,false)e.Frame.BackgroundTransparency=0.92 e.Border.Transparency=0.6 return e end return aj end,[26]=function()local aa,ab,ac,ad,ae=b(26)local af,ag=game:GetService'UserInputService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Slider'function c.New(d,e,f)local g=d.Library assert(f.Title,'Slider - Missing Title.')assert(f.Default,'Slider - Missing default value.')assert(f.Min,'Slider - Missing minimum value.')assert(f.Max,'Slider - Missing maximum value.')assert(f.Rounding,'Slider - Missing rounding value.')local h,i,j={Value=nil,Min=f.Min,Max=f.Max,Rounding=f.Rounding,Callback=f.Callback or function(h)end,Type='Slider'},false,ac(aj.Element)(f.Title,f.Description,d.Container,false)local sliderInput j.DescLabel.Size=UDim2.new(1,-170,0,14)h.SetTitle=j.SetTitle h.SetDesc=j.SetDesc local k=ai('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,-7,0.5,0),Size=UDim2.fromOffset(14,14),Image='http://www.roblox.com/asset/?id=12266946128',ThemeTag={ImageColor3='Accent'}})local l,m,n=ai('Frame',{BackgroundTransparency=1,Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-14,1,0)},{k}),ai('Frame',{Size=UDim2.new(0,0,1,0),ThemeTag={BackgroundColor3='Accent'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)})}),ai('TextLabel',{FontFace=Font.new'rbxasset://fonts/families/GothamSSm.json',Text='Value',TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Right,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Size=UDim2.new(0,100,0,14),Position=UDim2.new(0,-4,0.5,0),AnchorPoint=Vector2.new(1,0.5),ThemeTag={TextColor3='SubText'}})local o=ai('Frame',{Size=UDim2.new(1,0,0,4),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),BackgroundTransparency=0.4,Parent=j.Frame,ThemeTag={BackgroundColor3='SliderRail'}},{ai('UICorner',{CornerRadius=UDim.new(1,0)}),ai('UISizeConstraint',{MaxSize=Vector2.new(150,math.huge)}),n,m,l})ah.AddSignal(k.InputBegan,function(p)if p.UserInputType==Enum.UserInputType.MouseButton1 or p.UserInputType==Enum.UserInputType.Touch then if not i then i=true sliderInput=p end end end)ah.AddSignal(k.InputEnded,function(p)if p.UserInputType==Enum.UserInputType.MouseButton1 or p.UserInputType==Enum.UserInputType.Touch then if p==sliderInput or p.UserInputType==Enum.UserInputType.MouseButton1 then i=false sliderInput=nil end end end)ah.AddSignal(af.InputChanged,function(p)if i and(p.UserInputType==Enum.UserInputType.MouseMovement or p.UserInputType==Enum.UserInputType.Touch)then if sliderInput and sliderInput.UserInputType==Enum.UserInputType.Touch and p~=sliderInput then return end if not g.Window.Root.Visible or not j.Frame.Parent then i=false sliderInput=nil return end local s=math.clamp((p.Position.X-l.AbsolutePosition.X)/l.AbsoluteSize.X,0,1)h:SetValue(h.Min+((h.Max-h.Min)*s))end end)ah.AddSignal(af.WindowFocusReleased,function()i=false sliderInput=nil end)ah.AddSignal(g.Window.Root:GetPropertyChangedSignal'Visible',function()i=false sliderInput=nil end)function h.OnChanged(p,s)h.Changed=s s(h.Value)end function h.SetValue(p,s)p.Value=g:Round(math.clamp(s,h.Min,h.Max),h.Rounding)k.Position=UDim2.new((p.Value-h.Min)/(h.Max-h.Min),-7,0.5,0)m.Size=UDim2.fromScale((p.Value-h.Min)/(h.Max-h.Min),1)n.Text=tostring(p.Value)g:SafeCallback(h.Callback,p.Value)g:SafeCallback(h.Changed,p.Value)end function h.Destroy(p)j:Destroy()g.Options[e]=nil end h:SetValue(f.Default)g.Options[e]=h return h end return c end,[27]=function()local aa,ab,ac,ad,ae=b(27)local af,ag=game:GetService'TweenService',ab.Parent.Parent local ah=ac(ag.Creator)local ai,aj,c=ah.New,ag.Components,{}c.__index=c c.__type='Toggle'function c.New(d,e,f)local g=d.Library assert(f.Title,'Toggle - Missing Title')local h,i={Value=f.Default or false,Callback=f.Callback or function(h)end,Type='Toggle'},ac(aj.Element)(f.Title,f.Description,d.Container,true)i.DescLabel.Size=UDim2.new(1,-54,0,14)h.SetTitle=i.SetTitle h.SetDesc=i.SetDesc local j,k=ai('ImageLabel',{AnchorPoint=Vector2.new(0,0.5),Size=UDim2.fromOffset(14,14),Position=UDim2.new(0,2,0.5,0),Image='http://www.roblox.com/asset/?id=12266946128',ImageTransparency=0.5,ThemeTag={ImageColor3='ToggleSlider'}}),ai('UIStroke',{Transparency=0.5,ThemeTag={Color='ToggleSlider'}})local l=ai('Frame',{Size=UDim2.fromOffset(36,18),AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-10,0.5,0),Parent=i.Frame,BackgroundTransparency=1,ThemeTag={BackgroundColor3='Accent'}},{ai('UICorner',{CornerRadius=UDim.new(0,9)}),k,j})function h.OnChanged(m,n)h.Changed=n n(h.Value)end function h.SetValue(m,n)n=not not n h.Value=n ah.OverrideTag(k,{Color=h.Value and'Accent'or'ToggleSlider'})ah.OverrideTag(j,{ImageColor3=h.Value and'ToggleToggled'or'ToggleSlider'})af:Create(j,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.new(0,h.Value and 19 or 2,0.5,0)}):Play()af:Create(l,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundTransparency=h.Value and 0 or 1}):Play()j.ImageTransparency=h.Value and 0 or 0.5 g:SafeCallback(h.Callback,h.Value)g:SafeCallback(h.Changed,h.Value)end function h.Destroy(m)i:Destroy()g.Options[e]=nil end ah.AddSignal(i.Frame.MouseButton1Click,function()h:SetValue(not h.Value)end)h:SetValue(h.Value)g.Options[e]=h return h end return c end,[28]=function()local aa,ab,ac,ad,ae=b(28)return{assets={['lucide-accessibility']='rbxassetid://10709751939',['lucide-activity']='rbxassetid://10709752035',['lucide-air-vent']='rbxassetid://10709752131',['lucide-airplay']='rbxassetid://10709752254',['lucide-alarm-check']='rbxassetid://10709752405',['lucide-alarm-clock']='rbxassetid://10709752630',['lucide-alarm-clock-off']='rbxassetid://10709752508',['lucide-alarm-minus']='rbxassetid://10709752732',['lucide-alarm-plus']='rbxassetid://10709752825',['lucide-album']='rbxassetid://10709752906',['lucide-alert-circle']='rbxassetid://10709752996',['lucide-alert-octagon']='rbxassetid://10709753064',['lucide-alert-triangle']='rbxassetid://10709753149',['lucide-align-center']='rbxassetid://10709753570',['lucide-align-center-horizontal']='rbxassetid://10709753272',['lucide-align-center-vertical']='rbxassetid://10709753421',['lucide-align-end-horizontal']='rbxassetid://10709753692',['lucide-align-end-vertical']='rbxassetid://10709753808',['lucide-align-horizontal-distribute-center']='rbxassetid://10747779791',['lucide-align-horizontal-distribute-end']='rbxassetid://10747784534',['lucide-align-horizontal-distribute-start']='rbxassetid://10709754118',['lucide-align-horizontal-justify-center']='rbxassetid://10709754204',['lucide-align-horizontal-justify-end']='rbxassetid://10709754317',['lucide-align-horizontal-justify-start']='rbxassetid://10709754436',['lucide-align-horizontal-space-around']='rbxassetid://10709754590',['lucide-align-horizontal-space-between']='rbxassetid://10709754749',['lucide-align-justify']='rbxassetid://10709759610',['lucide-align-left']='rbxassetid://10709759764',['lucide-align-right']='rbxassetid://10709759895',['lucide-align-start-horizontal']='rbxassetid://10709760051',['lucide-align-start-vertical']='rbxassetid://10709760244',['lucide-align-vertical-distribute-center']='rbxassetid://10709760351',['lucide-align-vertical-distribute-end']='rbxassetid://10709760434',['lucide-align-vertical-distribute-start']='rbxassetid://10709760612',['lucide-align-vertical-justify-center']='rbxassetid://10709760814',['lucide-align-vertical-justify-end']='rbxassetid://10709761003',['lucide-align-vertical-justify-start']='rbxassetid://10709761176',['lucide-align-vertical-space-around']='rbxassetid://10709761324',['lucide-align-vertical-space-between']='rbxassetid://10709761434',['lucide-anchor']='rbxassetid://10709761530',['lucide-angry']='rbxassetid://10709761629',['lucide-annoyed']='rbxassetid://10709761722',['lucide-aperture']='rbxassetid://10709761813',['lucide-apple']='rbxassetid://10709761889',['lucide-archive']='rbxassetid://10709762233',['lucide-archive-restore']='rbxassetid://10709762058',['lucide-armchair']='rbxassetid://10709762327',['lucide-arrow-big-down']='rbxassetid://10747796644',['lucide-arrow-big-left']='rbxassetid://10709762574',['lucide-arrow-big-right']='rbxassetid://10709762727',['lucide-arrow-big-up']='rbxassetid://10709762879',['lucide-arrow-down']='rbxassetid://10709767827',['lucide-arrow-down-circle']='rbxassetid://10709763034',['lucide-arrow-down-left']='rbxassetid://10709767656',['lucide-arrow-down-right']='rbxassetid://10709767750',['lucide-arrow-left']='rbxassetid://10709768114',['lucide-arrow-left-circle']='rbxassetid://10709767936',['lucide-arrow-left-right']='rbxassetid://10709768019',['lucide-arrow-right']='rbxassetid://10709768347',['lucide-arrow-right-circle']='rbxassetid://10709768226',['lucide-arrow-up']='rbxassetid://10709768939',['lucide-arrow-up-circle']='rbxassetid://10709768432',['lucide-arrow-up-down']='rbxassetid://10709768538',['lucide-arrow-up-left']='rbxassetid://10709768661',['lucide-arrow-up-right']='rbxassetid://10709768787',['lucide-asterisk']='rbxassetid://10709769095',['lucide-at-sign']='rbxassetid://10709769286',['lucide-award']='rbxassetid://10709769406',['lucide-axe']='rbxassetid://10709769508',['lucide-axis-3d']='rbxassetid://10709769598',['lucide-baby']='rbxassetid://10709769732',['lucide-backpack']='rbxassetid://10709769841',['lucide-baggage-claim']='rbxassetid://10709769935',['lucide-banana']='rbxassetid://10709770005',['lucide-banknote']='rbxassetid://10709770178',['lucide-bar-chart']='rbxassetid://10709773755',['lucide-bar-chart-2']='rbxassetid://10709770317',['lucide-bar-chart-3']='rbxassetid://10709770431',['lucide-bar-chart-4']='rbxassetid://10709770560',['lucide-bar-chart-horizontal']='rbxassetid://10709773669',['lucide-barcode']='rbxassetid://10747360675',['lucide-baseline']='rbxassetid://10709773863',['lucide-bath']='rbxassetid://10709773963',['lucide-battery']='rbxassetid://10709774640',['lucide-battery-charging']='rbxassetid://10709774068',['lucide-battery-full']='rbxassetid://10709774206',['lucide-battery-low']='rbxassetid://10709774370',['lucide-battery-medium']='rbxassetid://10709774513',['lucide-beaker']='rbxassetid://10709774756',['lucide-bed']='rbxassetid://10709775036',['lucide-bed-double']='rbxassetid://10709774864',['lucide-bed-single']='rbxassetid://10709774968',['lucide-beer']='rbxassetid://10709775167',['lucide-bell']='rbxassetid://10709775704',['lucide-bell-minus']='rbxassetid://10709775241',['lucide-bell-off']='rbxassetid://10709775320',['lucide-bell-plus']='rbxassetid://10709775448',['lucide-bell-ring']='rbxassetid://10709775560',['lucide-bike']='rbxassetid://10709775894',['lucide-binary']='rbxassetid://10709776050',['lucide-bitcoin']='rbxassetid://10709776126',['lucide-bluetooth']='rbxassetid://10709776655',['lucide-bluetooth-connected']='rbxassetid://10709776240',['lucide-bluetooth-off']='rbxassetid://10709776344',['lucide-bluetooth-searching']='rbxassetid://10709776501',['lucide-bold']='rbxassetid://10747813908',['lucide-bomb']='rbxassetid://10709781460',['lucide-bone']='rbxassetid://10709781605',['lucide-book']='rbxassetid://10709781824',['lucide-book-open']='rbxassetid://10709781717',['lucide-bookmark']='rbxassetid://10709782154',['lucide-bookmark-minus']='rbxassetid://10709781919',['lucide-bookmark-plus']='rbxassetid://10709782044',['lucide-bot']='rbxassetid://10709782230',['lucide-box']='rbxassetid://10709782497',['lucide-box-select']='rbxassetid://10709782342',['lucide-boxes']='rbxassetid://10709782582',['lucide-briefcase']='rbxassetid://10709782662',['lucide-brush']='rbxassetid://10709782758',['lucide-bug']='rbxassetid://10709782845',['lucide-building']='rbxassetid://10709783051',['lucide-building-2']='rbxassetid://10709782939',['lucide-bus']='rbxassetid://10709783137',['lucide-cake']='rbxassetid://10709783217',['lucide-calculator']='rbxassetid://10709783311',['lucide-calendar']='rbxassetid://10709789505',['lucide-calendar-check']='rbxassetid://10709783474',['lucide-calendar-check-2']='rbxassetid://10709783392',['lucide-calendar-clock']='rbxassetid://10709783577',['lucide-calendar-days']='rbxassetid://10709783673',['lucide-calendar-heart']='rbxassetid://10709783835',['lucide-calendar-minus']='rbxassetid://10709783959',['lucide-calendar-off']='rbxassetid://10709788784',['lucide-calendar-plus']='rbxassetid://10709788937',['lucide-calendar-range']='rbxassetid://10709789053',['lucide-calendar-search']='rbxassetid://10709789200',['lucide-calendar-x']='rbxassetid://10709789407',['lucide-calendar-x-2']='rbxassetid://10709789329',['lucide-camera']='rbxassetid://10709789686',['lucide-camera-off']='rbxassetid://10747822677',['lucide-car']='rbxassetid://10709789810',['lucide-carrot']='rbxassetid://10709789960',['lucide-cast']='rbxassetid://10709790097',['lucide-charge']='rbxassetid://10709790202',['lucide-check']='rbxassetid://10709790644',['lucide-check-circle']='rbxassetid://10709790387',['lucide-check-circle-2']='rbxassetid://10709790298',['lucide-check-square']='rbxassetid://10709790537',['lucide-chef-hat']='rbxassetid://10709790757',['lucide-cherry']='rbxassetid://10709790875',['lucide-chevron-down']='rbxassetid://10709790948',['lucide-chevron-first']='rbxassetid://10709791015',['lucide-chevron-last']='rbxassetid://10709791130',['lucide-chevron-left']='rbxassetid://10709791281',['lucide-chevron-right']='rbxassetid://10709791437',['lucide-chevron-up']='rbxassetid://10709791523',['lucide-chevrons-down']='rbxassetid://10709796864',['lucide-chevrons-down-up']='rbxassetid://10709791632',['lucide-chevrons-left']='rbxassetid://10709797151',['lucide-chevrons-left-right']='rbxassetid://10709797006',['lucide-chevrons-right']='rbxassetid://10709797382',['lucide-chevrons-right-left']='rbxassetid://10709797274',['lucide-chevrons-up']='rbxassetid://10709797622',['lucide-chevrons-up-down']='rbxassetid://10709797508',['lucide-chrome']='rbxassetid://10709797725',['lucide-circle']='rbxassetid://10709798174',['lucide-circle-dot']='rbxassetid://10709797837',['lucide-circle-ellipsis']='rbxassetid://10709797985',['lucide-circle-slashed']='rbxassetid://10709798100',['lucide-citrus']='rbxassetid://10709798276',['lucide-clapperboard']='rbxassetid://10709798350',['lucide-clipboard']='rbxassetid://10709799288',['lucide-clipboard-check']='rbxassetid://10709798443',['lucide-clipboard-copy']='rbxassetid://10709798574',['lucide-clipboard-edit']='rbxassetid://10709798682',['lucide-clipboard-list']='rbxassetid://10709798792',['lucide-clipboard-signature']='rbxassetid://10709798890',['lucide-clipboard-type']='rbxassetid://10709798999',['lucide-clipboard-x']='rbxassetid://10709799124',['lucide-clock']='rbxassetid://10709805144',['lucide-clock-1']='rbxassetid://10709799535',['lucide-clock-10']='rbxassetid://10709799718',['lucide-clock-11']='rbxassetid://10709799818',['lucide-clock-12']='rbxassetid://10709799962',['lucide-clock-2']='rbxassetid://10709803876',['lucide-clock-3']='rbxassetid://10709803989',['lucide-clock-4']='rbxassetid://10709804164',['lucide-clock-5']='rbxassetid://10709804291',['lucide-clock-6']='rbxassetid://10709804435',['lucide-clock-7']='rbxassetid://10709804599',['lucide-clock-8']='rbxassetid://10709804784',['lucide-clock-9']='rbxassetid://10709804996',['lucide-cloud']='rbxassetid://10709806740',['lucide-cloud-cog']='rbxassetid://10709805262',['lucide-cloud-drizzle']='rbxassetid://10709805371',['lucide-cloud-fog']='rbxassetid://10709805477',['lucide-cloud-hail']='rbxassetid://10709805596',['lucide-cloud-lightning']='rbxassetid://10709805727',['lucide-cloud-moon']='rbxassetid://10709805942',['lucide-cloud-moon-rain']='rbxassetid://10709805838',['lucide-cloud-off']='rbxassetid://10709806060',['lucide-cloud-rain']='rbxassetid://10709806277',['lucide-cloud-rain-wind']='rbxassetid://10709806166',['lucide-cloud-snow']='rbxassetid://10709806374',['lucide-cloud-sun']='rbxassetid://10709806631',['lucide-cloud-sun-rain']='rbxassetid://10709806475',['lucide-cloudy']='rbxassetid://10709806859',['lucide-clover']='rbxassetid://10709806995',['lucide-code']='rbxassetid://10709810463',['lucide-code-2']='rbxassetid://10709807111',['lucide-codepen']='rbxassetid://10709810534',['lucide-codesandbox']='rbxassetid://10709810676',['lucide-coffee']='rbxassetid://10709810814',['lucide-cog']='rbxassetid://10709810948',['lucide-coins']='rbxassetid://10709811110',['lucide-columns']='rbxassetid://10709811261',['lucide-command']='rbxassetid://10709811365',['lucide-compass']='rbxassetid://10709811445',['lucide-component']='rbxassetid://10709811595',['lucide-concierge-bell']='rbxassetid://10709811706',['lucide-connection']='rbxassetid://10747361219',['lucide-contact']='rbxassetid://10709811834',['lucide-contrast']='rbxassetid://10709811939',['lucide-cookie']='rbxassetid://10709812067',['lucide-copy']='rbxassetid://10709812159',['lucide-copyleft']='rbxassetid://10709812251',['lucide-copyright']='rbxassetid://10709812311',['lucide-corner-down-left']='rbxassetid://10709812396',['lucide-corner-down-right']='rbxassetid://10709812485',['lucide-corner-left-down']='rbxassetid://10709812632',['lucide-corner-left-up']='rbxassetid://10709812784',['lucide-corner-right-down']='rbxassetid://10709812939',['lucide-corner-right-up']='rbxassetid://10709813094',['lucide-corner-up-left']='rbxassetid://10709813185',['lucide-corner-up-right']='rbxassetid://10709813281',['lucide-cpu']='rbxassetid://10709813383',['lucide-croissant']='rbxassetid://10709818125',['lucide-crop']='rbxassetid://10709818245',['lucide-cross']='rbxassetid://10709818399',['lucide-crosshair']='rbxassetid://10709818534',['lucide-crown']='rbxassetid://10709818626',['lucide-cup-soda']='rbxassetid://10709818763',['lucide-curly-braces']='rbxassetid://10709818847',['lucide-currency']='rbxassetid://10709818931',['lucide-database']='rbxassetid://10709818996',['lucide-delete']='rbxassetid://10709819059',['lucide-diamond']='rbxassetid://10709819149',['lucide-dice-1']='rbxassetid://10709819266',['lucide-dice-2']='rbxassetid://10709819361',['lucide-dice-3']='rbxassetid://10709819508',['lucide-dice-4']='rbxassetid://10709819670',['lucide-dice-5']='rbxassetid://10709819801',['lucide-dice-6']='rbxassetid://10709819896',['lucide-dices']='rbxassetid://10723343321',['lucide-diff']='rbxassetid://10723343416',['lucide-disc']='rbxassetid://10723343537',['lucide-divide']='rbxassetid://10723343805',['lucide-divide-circle']='rbxassetid://10723343636',['lucide-divide-square']='rbxassetid://10723343737',['lucide-dollar-sign']='rbxassetid://10723343958',['lucide-download']='rbxassetid://10723344270',['lucide-download-cloud']='rbxassetid://10723344088',['lucide-droplet']='rbxassetid://10723344432',['lucide-droplets']='rbxassetid://10734883356',['lucide-drumstick']='rbxassetid://10723344737',['lucide-edit']='rbxassetid://10734883598',['lucide-edit-2']='rbxassetid://10723344885',['lucide-edit-3']='rbxassetid://10723345088',['lucide-egg']='rbxassetid://10723345518',['lucide-egg-fried']='rbxassetid://10723345347',['lucide-electricity']='rbxassetid://10723345749',['lucide-electricity-off']='rbxassetid://10723345643',['lucide-equal']='rbxassetid://10723345990',['lucide-equal-not']='rbxassetid://10723345866',['lucide-eraser']='rbxassetid://10723346158',['lucide-euro']='rbxassetid://10723346372',['lucide-expand']='rbxassetid://10723346553',['lucide-external-link']='rbxassetid://10723346684',['lucide-eye']='rbxassetid://10723346959',['lucide-eye-off']='rbxassetid://10723346871',['lucide-factory']='rbxassetid://10723347051',['lucide-fan']='rbxassetid://10723354359',['lucide-fast-forward']='rbxassetid://10723354521',['lucide-feather']='rbxassetid://10723354671',['lucide-figma']='rbxassetid://10723354801',['lucide-file']='rbxassetid://10723374641',['lucide-file-archive']='rbxassetid://10723354921',['lucide-file-audio']='rbxassetid://10723355148',['lucide-file-audio-2']='rbxassetid://10723355026',['lucide-file-axis-3d']='rbxassetid://10723355272',['lucide-file-badge']='rbxassetid://10723355622',['lucide-file-badge-2']='rbxassetid://10723355451',['lucide-file-bar-chart']='rbxassetid://10723355887',['lucide-file-bar-chart-2']='rbxassetid://10723355746',['lucide-file-box']='rbxassetid://10723355989',['lucide-file-check']='rbxassetid://10723356210',['lucide-file-check-2']='rbxassetid://10723356100',['lucide-file-clock']='rbxassetid://10723356329',['lucide-file-code']='rbxassetid://10723356507',['lucide-file-cog']='rbxassetid://10723356830',['lucide-file-cog-2']='rbxassetid://10723356676',['lucide-file-diff']='rbxassetid://10723357039',['lucide-file-digit']='rbxassetid://10723357151',['lucide-file-down']='rbxassetid://10723357322',['lucide-file-edit']='rbxassetid://10723357495',['lucide-file-heart']='rbxassetid://10723357637',['lucide-file-image']='rbxassetid://10723357790',['lucide-file-input']='rbxassetid://10723357933',['lucide-file-json']='rbxassetid://10723364435',['lucide-file-json-2']='rbxassetid://10723364361',['lucide-file-key']='rbxassetid://10723364605',['lucide-file-key-2']='rbxassetid://10723364515',['lucide-file-line-chart']='rbxassetid://10723364725',['lucide-file-lock']='rbxassetid://10723364957',['lucide-file-lock-2']='rbxassetid://10723364861',['lucide-file-minus']='rbxassetid://10723365254',['lucide-file-minus-2']='rbxassetid://10723365086',['lucide-file-output']='rbxassetid://10723365457',['lucide-file-pie-chart']='rbxassetid://10723365598',['lucide-file-plus']='rbxassetid://10723365877',['lucide-file-plus-2']='rbxassetid://10723365766',['lucide-file-question']='rbxassetid://10723365987',['lucide-file-scan']='rbxassetid://10723366167',['lucide-file-search']='rbxassetid://10723366550',['lucide-file-search-2']='rbxassetid://10723366340',['lucide-file-signature']='rbxassetid://10723366741',['lucide-file-spreadsheet']='rbxassetid://10723366962',['lucide-file-symlink']='rbxassetid://10723367098',['lucide-file-terminal']='rbxassetid://10723367244',['lucide-file-text']='rbxassetid://10723367380',['lucide-file-type']='rbxassetid://10723367606',['lucide-file-type-2']='rbxassetid://10723367509',['lucide-file-up']='rbxassetid://10723367734',['lucide-file-video']='rbxassetid://10723373884',['lucide-file-video-2']='rbxassetid://10723367834',['lucide-file-volume']='rbxassetid://10723374172',['lucide-file-volume-2']='rbxassetid://10723374030',['lucide-file-warning']='rbxassetid://10723374276',['lucide-file-x']='rbxassetid://10723374544',['lucide-file-x-2']='rbxassetid://10723374378',['lucide-files']='rbxassetid://10723374759',['lucide-film']='rbxassetid://10723374981',['lucide-filter']='rbxassetid://10723375128',['lucide-fingerprint']='rbxassetid://10723375250',['lucide-flag']='rbxassetid://10723375890',['lucide-flag-off']='rbxassetid://10723375443',['lucide-flag-triangle-left']='rbxassetid://10723375608',['lucide-flag-triangle-right']='rbxassetid://10723375727',['lucide-flame']='rbxassetid://10723376114',['lucide-flashlight']='rbxassetid://10723376471',['lucide-flashlight-off']='rbxassetid://10723376365',['lucide-flask-conical']='rbxassetid://10734883986',['lucide-flask-round']='rbxassetid://10723376614',['lucide-flip-horizontal']='rbxassetid://10723376884',['lucide-flip-horizontal-2']='rbxassetid://10723376745',['lucide-flip-vertical']='rbxassetid://10723377138',['lucide-flip-vertical-2']='rbxassetid://10723377026',['lucide-flower']='rbxassetid://10747830374',['lucide-flower-2']='rbxassetid://10723377305',['lucide-focus']='rbxassetid://10723377537',['lucide-folder']='rbxassetid://10723387563',['lucide-folder-archive']='rbxassetid://10723384478',['lucide-folder-check']='rbxassetid://10723384605',['lucide-folder-clock']='rbxassetid://10723384731',['lucide-folder-closed']='rbxassetid://10723384893',['lucide-folder-cog']='rbxassetid://10723385213',['lucide-folder-cog-2']='rbxassetid://10723385036',['lucide-folder-down']='rbxassetid://10723385338',['lucide-folder-edit']='rbxassetid://10723385445',['lucide-folder-heart']='rbxassetid://10723385545',['lucide-folder-input']='rbxassetid://10723385721',['lucide-folder-key']='rbxassetid://10723385848',['lucide-folder-lock']='rbxassetid://10723386005',['lucide-folder-minus']='rbxassetid://10723386127',['lucide-folder-open']='rbxassetid://10723386277',['lucide-folder-output']='rbxassetid://10723386386',['lucide-folder-plus']='rbxassetid://10723386531',['lucide-folder-search']='rbxassetid://10723386787',['lucide-folder-search-2']='rbxassetid://10723386674',['lucide-folder-symlink']='rbxassetid://10723386930',['lucide-folder-tree']='rbxassetid://10723387085',['lucide-folder-up']='rbxassetid://10723387265',['lucide-folder-x']='rbxassetid://10723387448',['lucide-folders']='rbxassetid://10723387721',['lucide-form-input']='rbxassetid://10723387841',['lucide-forward']='rbxassetid://10723388016',['lucide-frame']='rbxassetid://10723394389',['lucide-framer']='rbxassetid://10723394565',['lucide-frown']='rbxassetid://10723394681',['lucide-fuel']='rbxassetid://10723394846',['lucide-function-square']='rbxassetid://10723395041',['lucide-gamepad']='rbxassetid://10723395457',['lucide-gamepad-2']='rbxassetid://10723395215',['lucide-gauge']='rbxassetid://10723395708',['lucide-gavel']='rbxassetid://10723395896',['lucide-gem']='rbxassetid://10723396000',['lucide-ghost']='rbxassetid://10723396107',['lucide-gift']='rbxassetid://10723396402',['lucide-gift-card']='rbxassetid://10723396225',['lucide-git-branch']='rbxassetid://10723396676',['lucide-git-branch-plus']='rbxassetid://10723396542',['lucide-git-commit']='rbxassetid://10723396812',['lucide-git-compare']='rbxassetid://10723396954',['lucide-git-fork']='rbxassetid://10723397049',['lucide-git-merge']='rbxassetid://10723397165',['lucide-git-pull-request']='rbxassetid://10723397431',['lucide-git-pull-request-closed']='rbxassetid://10723397268',['lucide-git-pull-request-draft']='rbxassetid://10734884302',['lucide-glass']='rbxassetid://10723397788',['lucide-glass-2']='rbxassetid://10723397529',['lucide-glass-water']='rbxassetid://10723397678',['lucide-glasses']='rbxassetid://10723397895',['lucide-globe']='rbxassetid://10723404337',['lucide-globe-2']='rbxassetid://10723398002',['lucide-grab']='rbxassetid://10723404472',['lucide-graduation-cap']='rbxassetid://10723404691',['lucide-grape']='rbxassetid://10723404822',['lucide-grid']='rbxassetid://10723404936',['lucide-grip-horizontal']='rbxassetid://10723405089',['lucide-grip-vertical']='rbxassetid://10723405236',['lucide-hammer']='rbxassetid://10723405360',['lucide-hand']='rbxassetid://10723405649',['lucide-hand-metal']='rbxassetid://10723405508',['lucide-hard-drive']='rbxassetid://10723405749',['lucide-hard-hat']='rbxassetid://10723405859',['lucide-hash']='rbxassetid://10723405975',['lucide-haze']='rbxassetid://10723406078',['lucide-headphones']='rbxassetid://10723406165',['lucide-heart']='rbxassetid://10723406885',['lucide-heart-crack']='rbxassetid://10723406299',['lucide-heart-handshake']='rbxassetid://10723406480',['lucide-heart-off']='rbxassetid://10723406662',['lucide-heart-pulse']='rbxassetid://10723406795',['lucide-help-circle']='rbxassetid://10723406988',['lucide-hexagon']='rbxassetid://10723407092',['lucide-highlighter']='rbxassetid://10723407192',['lucide-history']='rbxassetid://10723407335',['lucide-home']='rbxassetid://10723407389',['lucide-hourglass']='rbxassetid://10723407498',['lucide-ice-cream']='rbxassetid://10723414308',['lucide-image']='rbxassetid://10723415040',['lucide-image-minus']='rbxassetid://10723414487',['lucide-image-off']='rbxassetid://10723414677',['lucide-image-plus']='rbxassetid://10723414827',['lucide-import']='rbxassetid://10723415205',['lucide-inbox']='rbxassetid://10723415335',['lucide-indent']='rbxassetid://10723415494',['lucide-indian-rupee']='rbxassetid://10723415642',['lucide-infinity']='rbxassetid://10723415766',['lucide-info']='rbxassetid://10723415903',['lucide-inspect']='rbxassetid://10723416057',['lucide-italic']='rbxassetid://10723416195',['lucide-japanese-yen']='rbxassetid://10723416363',['lucide-joystick']='rbxassetid://10723416527',['lucide-key']='rbxassetid://10723416652',['lucide-keyboard']='rbxassetid://10723416765',['lucide-lamp']='rbxassetid://10723417513',['lucide-lamp-ceiling']='rbxassetid://10723416922',['lucide-lamp-desk']='rbxassetid://10723417016',['lucide-lamp-floor']='rbxassetid://10723417131',['lucide-lamp-wall-down']='rbxassetid://10723417240',['lucide-lamp-wall-up']='rbxassetid://10723417356',['lucide-landmark']='rbxassetid://10723417608',['lucide-languages']='rbxassetid://10723417703',['lucide-laptop']='rbxassetid://10723423881',['lucide-laptop-2']='rbxassetid://10723417797',['lucide-lasso']='rbxassetid://10723424235',['lucide-lasso-select']='rbxassetid://10723424058',['lucide-laugh']='rbxassetid://10723424372',['lucide-layers']='rbxassetid://10723424505',['lucide-layout']='rbxassetid://10723425376',['lucide-layout-dashboard']='rbxassetid://10723424646',['lucide-layout-grid']='rbxassetid://10723424838',['lucide-layout-list']='rbxassetid://10723424963',['lucide-layout-template']='rbxassetid://10723425187',['lucide-leaf']='rbxassetid://10723425539',['lucide-library']='rbxassetid://10723425615',['lucide-life-buoy']='rbxassetid://10723425685',['lucide-lightbulb']='rbxassetid://10723425852',['lucide-lightbulb-off']='rbxassetid://10723425762',['lucide-line-chart']='rbxassetid://10723426393',['lucide-link']='rbxassetid://10723426722',['lucide-link-2']='rbxassetid://10723426595',['lucide-link-2-off']='rbxassetid://10723426513',['lucide-list']='rbxassetid://10723433811',['lucide-list-checks']='rbxassetid://10734884548',['lucide-list-end']='rbxassetid://10723426886',['lucide-list-minus']='rbxassetid://10723426986',['lucide-list-music']='rbxassetid://10723427081',['lucide-list-ordered']='rbxassetid://10723427199',['lucide-list-plus']='rbxassetid://10723427334',['lucide-list-start']='rbxassetid://10723427494',['lucide-list-video']='rbxassetid://10723427619',['lucide-list-x']='rbxassetid://10723433655',['lucide-loader']='rbxassetid://10723434070',['lucide-loader-2']='rbxassetid://10723433935',['lucide-locate']='rbxassetid://10723434557',['lucide-locate-fixed']='rbxassetid://10723434236',['lucide-locate-off']='rbxassetid://10723434379',['lucide-lock']='rbxassetid://10723434711',['lucide-log-in']='rbxassetid://10723434830',['lucide-log-out']='rbxassetid://10723434906',['lucide-luggage']='rbxassetid://10723434993',['lucide-magnet']='rbxassetid://10723435069',['lucide-mail']='rbxassetid://10734885430',['lucide-mail-check']='rbxassetid://10723435182',['lucide-mail-minus']='rbxassetid://10723435261',['lucide-mail-open']='rbxassetid://10723435342',['lucide-mail-plus']='rbxassetid://10723435443',['lucide-mail-question']='rbxassetid://10723435515',['lucide-mail-search']='rbxassetid://10734884739',['lucide-mail-warning']='rbxassetid://10734885015',['lucide-mail-x']='rbxassetid://10734885247',['lucide-mails']='rbxassetid://10734885614',['lucide-map']='rbxassetid://10734886202',['lucide-map-pin']='rbxassetid://10734886004',['lucide-map-pin-off']='rbxassetid://10734885803',['lucide-maximize']='rbxassetid://10734886735',['lucide-maximize-2']='rbxassetid://10734886496',['lucide-medal']='rbxassetid://10734887072',['lucide-megaphone']='rbxassetid://10734887454',['lucide-megaphone-off']='rbxassetid://10734887311',['lucide-meh']='rbxassetid://10734887603',['lucide-menu']='rbxassetid://10734887784',['lucide-message-circle']='rbxassetid://10734888000',['lucide-message-square']='rbxassetid://10734888228',['lucide-mic']='rbxassetid://10734888864',['lucide-mic-2']='rbxassetid://10734888430',['lucide-mic-off']='rbxassetid://10734888646',['lucide-microscope']='rbxassetid://10734889106',['lucide-microwave']='rbxassetid://10734895076',['lucide-milestone']='rbxassetid://10734895310',['lucide-minimize']='rbxassetid://10734895698',['lucide-minimize-2']='rbxassetid://10734895530',['lucide-minus']='rbxassetid://10734896206',['lucide-minus-circle']='rbxassetid://10734895856',['lucide-minus-square']='rbxassetid://10734896029',['lucide-monitor']='rbxassetid://10734896881',['lucide-monitor-off']='rbxassetid://10734896360',['lucide-monitor-speaker']='rbxassetid://10734896512',['lucide-moon']='rbxassetid://10734897102',['lucide-more-horizontal']='rbxassetid://10734897250',['lucide-more-vertical']='rbxassetid://10734897387',['lucide-mountain']='rbxassetid://10734897956',['lucide-mountain-snow']='rbxassetid://10734897665',['lucide-mouse']='rbxassetid://10734898592',['lucide-mouse-pointer']='rbxassetid://10734898476',['lucide-mouse-pointer-2']='rbxassetid://10734898194',['lucide-mouse-pointer-click']='rbxassetid://10734898355',['lucide-move']='rbxassetid://10734900011',['lucide-move-3d']='rbxassetid://10734898756',['lucide-move-diagonal']='rbxassetid://10734899164',['lucide-move-diagonal-2']='rbxassetid://10734898934',['lucide-move-horizontal']='rbxassetid://10734899414',['lucide-move-vertical']='rbxassetid://10734899821',['lucide-music']='rbxassetid://10734905958',['lucide-music-2']='rbxassetid://10734900215',['lucide-music-3']='rbxassetid://10734905665',['lucide-music-4']='rbxassetid://10734905823',['lucide-navigation']='rbxassetid://10734906744',['lucide-navigation-2']='rbxassetid://10734906332',['lucide-navigation-2-off']='rbxassetid://10734906144',['lucide-navigation-off']='rbxassetid://10734906580',['lucide-network']='rbxassetid://10734906975',['lucide-newspaper']='rbxassetid://10734907168',['lucide-octagon']='rbxassetid://10734907361',['lucide-option']='rbxassetid://10734907649',['lucide-outdent']='rbxassetid://10734907933',['lucide-package']='rbxassetid://10734909540',['lucide-package-2']='rbxassetid://10734908151',['lucide-package-check']='rbxassetid://10734908384',['lucide-package-minus']='rbxassetid://10734908626',['lucide-package-open']='rbxassetid://10734908793',['lucide-package-plus']='rbxassetid://10734909016',['lucide-package-search']='rbxassetid://10734909196',['lucide-package-x']='rbxassetid://10734909375',['lucide-paint-bucket']='rbxassetid://10734909847',['lucide-paintbrush']='rbxassetid://10734910187',['lucide-paintbrush-2']='rbxassetid://10734910030',['lucide-palette']='rbxassetid://10734910430',['lucide-palmtree']='rbxassetid://10734910680',['lucide-paperclip']='rbxassetid://10734910927',['lucide-party-popper']='rbxassetid://10734918735',['lucide-pause']='rbxassetid://10734919336',['lucide-pause-circle']='rbxassetid://10735024209',['lucide-pause-octagon']='rbxassetid://10734919143',['lucide-pen-tool']='rbxassetid://10734919503',['lucide-pencil']='rbxassetid://10734919691',['lucide-percent']='rbxassetid://10734919919',['lucide-person-standing']='rbxassetid://10734920149',['lucide-phone']='rbxassetid://10734921524',['lucide-phone-call']='rbxassetid://10734920305',['lucide-phone-forwarded']='rbxassetid://10734920508',['lucide-phone-incoming']='rbxassetid://10734920694',['lucide-phone-missed']='rbxassetid://10734920845',['lucide-phone-off']='rbxassetid://10734921077',['lucide-phone-outgoing']='rbxassetid://10734921288',['lucide-pie-chart']='rbxassetid://10734921727',['lucide-piggy-bank']='rbxassetid://10734921935',['lucide-pin']='rbxassetid://10734922324',['lucide-pin-off']='rbxassetid://10734922180',['lucide-pipette']='rbxassetid://10734922497',['lucide-pizza']='rbxassetid://10734922774',['lucide-plane']='rbxassetid://10734922971',['lucide-play']='rbxassetid://10734923549',['lucide-play-circle']='rbxassetid://10734923214',['lucide-plus']='rbxassetid://10734924532',['lucide-plus-circle']='rbxassetid://10734923868',['lucide-plus-square']='rbxassetid://10734924219',['lucide-podcast']='rbxassetid://10734929553',['lucide-pointer']='rbxassetid://10734929723',['lucide-pound-sterling']='rbxassetid://10734929981',['lucide-power']='rbxassetid://10734930466',['lucide-power-off']='rbxassetid://10734930257',['lucide-printer']='rbxassetid://10734930632',['lucide-puzzle']='rbxassetid://10734930886',['lucide-quote']='rbxassetid://10734931234',['lucide-radio']='rbxassetid://10734931596',['lucide-radio-receiver']='rbxassetid://10734931402',['lucide-rectangle-horizontal']='rbxassetid://10734931777',['lucide-rectangle-vertical']='rbxassetid://10734932081',['lucide-recycle']='rbxassetid://10734932295',['lucide-redo']='rbxassetid://10734932822',['lucide-redo-2']='rbxassetid://10734932586',['lucide-refresh-ccw']='rbxassetid://10734933056',['lucide-refresh-cw']='rbxassetid://10734933222',['lucide-refrigerator']='rbxassetid://10734933465',['lucide-regex']='rbxassetid://10734933655',['lucide-repeat']='rbxassetid://10734933966',['lucide-repeat-1']='rbxassetid://10734933826',['lucide-reply']='rbxassetid://10734934252',['lucide-reply-all']='rbxassetid://10734934132',['lucide-rewind']='rbxassetid://10734934347',['lucide-rocket']='rbxassetid://10734934585',['lucide-rocking-chair']='rbxassetid://10734939942',['lucide-rotate-3d']='rbxassetid://10734940107',['lucide-rotate-ccw']='rbxassetid://10734940376',['lucide-rotate-cw']='rbxassetid://10734940654',['lucide-rss']='rbxassetid://10734940825',['lucide-ruler']='rbxassetid://10734941018',['lucide-russian-ruble']='rbxassetid://10734941199',['lucide-sailboat']='rbxassetid://10734941354',['lucide-save']='rbxassetid://10734941499',['lucide-scale']='rbxassetid://10734941912',['lucide-scale-3d']='rbxassetid://10734941739',['lucide-scaling']='rbxassetid://10734942072',['lucide-scan']='rbxassetid://10734942565',['lucide-scan-face']='rbxassetid://10734942198',['lucide-scan-line']='rbxassetid://10734942351',['lucide-scissors']='rbxassetid://10734942778',['lucide-screen-share']='rbxassetid://10734943193',['lucide-screen-share-off']='rbxassetid://10734942967',['lucide-scroll']='rbxassetid://10734943448',['lucide-search']='rbxassetid://10734943674',['lucide-send']='rbxassetid://10734943902',['lucide-separator-horizontal']='rbxassetid://10734944115',['lucide-separator-vertical']='rbxassetid://10734944326',['lucide-server']='rbxassetid://10734949856',['lucide-server-cog']='rbxassetid://10734944444',['lucide-server-crash']='rbxassetid://10734944554',['lucide-server-off']='rbxassetid://10734944668',['lucide-settings']='rbxassetid://10734950309',['lucide-settings-2']='rbxassetid://10734950020',['lucide-share']='rbxassetid://10734950813',['lucide-share-2']='rbxassetid://10734950553',['lucide-sheet']='rbxassetid://10734951038',['lucide-shield']='rbxassetid://10734951847',['lucide-shield-alert']='rbxassetid://10734951173',['lucide-shield-check']='rbxassetid://10734951367',['lucide-shield-close']='rbxassetid://10734951535',['lucide-shield-off']='rbxassetid://10734951684',['lucide-shirt']='rbxassetid://10734952036',['lucide-shopping-bag']='rbxassetid://10734952273',['lucide-shopping-cart']='rbxassetid://10734952479',['lucide-shovel']='rbxassetid://10734952773',['lucide-shower-head']='rbxassetid://10734952942',['lucide-shrink']='rbxassetid://10734953073',['lucide-shrub']='rbxassetid://10734953241',['lucide-shuffle']='rbxassetid://10734953451',['lucide-sidebar']='rbxassetid://10734954301',['lucide-sidebar-close']='rbxassetid://10734953715',['lucide-sidebar-open']='rbxassetid://10734954000',['lucide-sigma']='rbxassetid://10734954538',['lucide-signal']='rbxassetid://10734961133',['lucide-signal-high']='rbxassetid://10734954807',['lucide-signal-low']='rbxassetid://10734955080',['lucide-signal-medium']='rbxassetid://10734955336',['lucide-signal-zero']='rbxassetid://10734960878',['lucide-siren']='rbxassetid://10734961284',['lucide-skip-back']='rbxassetid://10734961526',['lucide-skip-forward']='rbxassetid://10734961809',['lucide-skull']='rbxassetid://10734962068',['lucide-slack']='rbxassetid://10734962339',['lucide-slash']='rbxassetid://10734962600',['lucide-slice']='rbxassetid://10734963024',['lucide-sliders']='rbxassetid://10734963400',['lucide-sliders-horizontal']='rbxassetid://10734963191',['lucide-smartphone']='rbxassetid://10734963940',['lucide-smartphone-charging']='rbxassetid://10734963671',['lucide-smile']='rbxassetid://10734964441',['lucide-smile-plus']='rbxassetid://10734964188',['lucide-snowflake']='rbxassetid://10734964600',['lucide-sofa']='rbxassetid://10734964852',['lucide-sort-asc']='rbxassetid://10734965115',['lucide-sort-desc']='rbxassetid://10734965287',['lucide-speaker']='rbxassetid://10734965419',['lucide-sprout']='rbxassetid://10734965572',['lucide-square']='rbxassetid://10734965702',['lucide-star']='rbxassetid://10734966248',['lucide-star-half']='rbxassetid://10734965897',['lucide-star-off']='rbxassetid://10734966097',['lucide-stethoscope']='rbxassetid://10734966384',['lucide-sticker']='rbxassetid://10734972234',['lucide-sticky-note']='rbxassetid://10734972463',['lucide-stop-circle']='rbxassetid://10734972621',['lucide-stretch-horizontal']='rbxassetid://10734972862',['lucide-stretch-vertical']='rbxassetid://10734973130',['lucide-strikethrough']='rbxassetid://10734973290',['lucide-subscript']='rbxassetid://10734973457',['lucide-sun']='rbxassetid://10734974297',['lucide-sun-dim']='rbxassetid://10734973645',['lucide-sun-medium']='rbxassetid://10734973778',['lucide-sun-moon']='rbxassetid://10734973999',['lucide-sun-snow']='rbxassetid://10734974130',['lucide-sunrise']='rbxassetid://10734974522',['lucide-sunset']='rbxassetid://10734974689',['lucide-superscript']='rbxassetid://10734974850',['lucide-swiss-franc']='rbxassetid://10734975024',['lucide-switch-camera']='rbxassetid://10734975214',['lucide-sword']='rbxassetid://10734975486',['lucide-swords']='rbxassetid://10734975692',['lucide-syringe']='rbxassetid://10734975932',['lucide-table']='rbxassetid://10734976230',['lucide-table-2']='rbxassetid://10734976097',['lucide-tablet']='rbxassetid://10734976394',['lucide-tag']='rbxassetid://10734976528',['lucide-tags']='rbxassetid://10734976739',['lucide-target']='rbxassetid://10734977012',['lucide-tent']='rbxassetid://10734981750',['lucide-terminal']='rbxassetid://10734982144',['lucide-terminal-square']='rbxassetid://10734981995',['lucide-text-cursor']='rbxassetid://10734982395',['lucide-text-cursor-input']='rbxassetid://10734982297',['lucide-thermometer']='rbxassetid://10734983134',['lucide-thermometer-snowflake']='rbxassetid://10734982571',['lucide-thermometer-sun']='rbxassetid://10734982771',['lucide-thumbs-down']='rbxassetid://10734983359',['lucide-thumbs-up']='rbxassetid://10734983629',['lucide-ticket']='rbxassetid://10734983868',['lucide-timer']='rbxassetid://10734984606',['lucide-timer-off']='rbxassetid://10734984138',['lucide-timer-reset']='rbxassetid://10734984355',['lucide-toggle-left']='rbxassetid://10734984834',['lucide-toggle-right']='rbxassetid://10734985040',['lucide-tornado']='rbxassetid://10734985247',['lucide-toy-brick']='rbxassetid://10747361919',['lucide-train']='rbxassetid://10747362105',['lucide-trash']='rbxassetid://10747362393',['lucide-trash-2']='rbxassetid://10747362241',['lucide-tree-deciduous']='rbxassetid://10747362534',['lucide-tree-pine']='rbxassetid://10747362748',['lucide-trees']='rbxassetid://10747363016',['lucide-trending-down']='rbxassetid://10747363205',['lucide-trending-up']='rbxassetid://10747363465',['lucide-triangle']='rbxassetid://10747363621',['lucide-trophy']='rbxassetid://10747363809',['lucide-truck']='rbxassetid://10747364031',['lucide-tv']='rbxassetid://10747364593',['lucide-tv-2']='rbxassetid://10747364302',['lucide-type']='rbxassetid://10747364761',['lucide-umbrella']='rbxassetid://10747364971',['lucide-underline']='rbxassetid://10747365191',['lucide-undo']='rbxassetid://10747365484',['lucide-undo-2']='rbxassetid://10747365359',['lucide-unlink']='rbxassetid://10747365771',['lucide-unlink-2']='rbxassetid://10747397871',['lucide-unlock']='rbxassetid://10747366027',['lucide-upload']='rbxassetid://10747366434',['lucide-upload-cloud']='rbxassetid://10747366266',['lucide-usb']='rbxassetid://10747366606',['lucide-user']='rbxassetid://10747373176',['lucide-user-check']='rbxassetid://10747371901',['lucide-user-cog']='rbxassetid://10747372167',['lucide-user-minus']='rbxassetid://10747372346',['lucide-user-plus']='rbxassetid://10747372702',['lucide-user-x']='rbxassetid://10747372992',['lucide-users']='rbxassetid://10747373426',['lucide-utensils']='rbxassetid://10747373821',['lucide-utensils-crossed']='rbxassetid://10747373629',['lucide-venetian-mask']='rbxassetid://10747374003',['lucide-verified']='rbxassetid://10747374131',['lucide-vibrate']='rbxassetid://10747374489',['lucide-vibrate-off']='rbxassetid://10747374269',['lucide-video']='rbxassetid://10747374938',['lucide-video-off']='rbxassetid://10747374721',['lucide-view']='rbxassetid://10747375132',['lucide-voicemail']='rbxassetid://10747375281',['lucide-volume']='rbxassetid://10747376008',['lucide-volume-1']='rbxassetid://10747375450',['lucide-volume-2']='rbxassetid://10747375679',['lucide-volume-x']='rbxassetid://10747375880',['lucide-wallet']='rbxassetid://10747376205',['lucide-wand']='rbxassetid://10747376565',['lucide-wand-2']='rbxassetid://10747376349',['lucide-watch']='rbxassetid://10747376722',['lucide-waves']='rbxassetid://10747376931',['lucide-webcam']='rbxassetid://10747381992',['lucide-wifi']='rbxassetid://10747382504',['lucide-wifi-off']='rbxassetid://10747382268',['lucide-wind']='rbxassetid://10747382750',['lucide-wrap-text']='rbxassetid://10747383065',['lucide-wrench']='rbxassetid://10747383470',['lucide-x']='rbxassetid://10747384394',['lucide-x-circle']='rbxassetid://10747383819',['lucide-x-octagon']='rbxassetid://10747384037',['lucide-x-square']='rbxassetid://10747384217',['lucide-zoom-in']='rbxassetid://10747384552',['lucide-zoom-out']='rbxassetid://10747384679'}}end,[30]=function()local aa,ab,ac,ad,ae=b(30)local af={SingleMotor=ac(ab.SingleMotor),GroupMotor=ac(ab.GroupMotor),Instant=ac(ab.Instant),Linear=ac(ab.Linear),Spring=ac(ab.Spring),isMotor=ac(ab.isMotor)}return af end,[31]=function()local aa,ab,ac,ad,ae=b(31)local af,ag,ah,ai=game:GetService'RunService',ac(ab.Parent.Signal),function()end,{}ai.__index=ai function ai.new()return setmetatable({_onStep=ag.new(),_onStart=ag.new(),_onComplete=ag.new()},ai)end function ai.onStep(aj,c)return aj._onStep:connect(c)end function ai.onStart(aj,c)return aj._onStart:connect(c)end function ai.onComplete(aj,c)return aj._onComplete:connect(c)end function ai.start(aj)if not aj._connection then aj._connection=af.RenderStepped:Connect(function(c)aj:step(c)end)end end function ai.stop(aj)if aj._connection then aj._connection:Disconnect()aj._connection=nil end end ai.destroy=ai.stop ai.step=ah ai.getValue=ah ai.setGoal=ah function ai.__tostring(aj)return'Motor'end return ai end,[32]=function()local aa,ab,ac,ad,ae=b(32)return function()local af,ag=game:GetService'RunService',ac(ab.Parent.BaseMotor)describe('connection management',function()local ah=ag.new()it('should hook up connections on :start()',function()ah:start()expect(typeof(ah._connection)).to.equal'RBXScriptConnection'end)it('should remove connections on :stop() or :destroy()',function()ah:stop()expect(ah._connection).to.equal(nil)end)end)it('should call :step() with deltaTime',function()local ah,ai=(ag.new())function ah.step(aj,...)ai={...}ah:stop()end ah:start()local aj=af.RenderStepped:Wait()af.RenderStepped:Wait()expect(ai).to.be.ok()expect(ai[1]).to.equal(aj)end)end end,[33]=function()local aa,ab,ac,ad,ae=b(33)local af,ag,ah=ac(ab.Parent.BaseMotor),ac(ab.Parent.SingleMotor),ac(ab.Parent.isMotor)local ai=setmetatable({},af)ai.__index=ai local aj=function(aj)if ah(aj)then return aj end local c=typeof(aj)if c=='number'then return ag.new(aj,false)elseif c=='table'then return ai.new(aj,false)end error(('Unable to convert %q to motor; type %s is unsupported'):format(aj,c),2)end function ai.new(c,d)assert(c,'Missing argument #1: initialValues')assert(typeof(c)=='table','initialValues must be a table!')assert(not c.step,[[initialValues contains disallowed property "step". Did you mean to put a table of values here?]])local e=setmetatable(af.new(),ai)if d~=nil then e._useImplicitConnections=d else e._useImplicitConnections=true end e._complete=true e._motors={}for f,g in pairs(c)do e._motors[f]=aj(g)end return e end function ai.step(c,d)if c._complete then return true end local e=true for f,g in pairs(c._motors)do local h=g:step(d)if not h then e=false end end c._onStep:fire(c:getValue())if e then if c._useImplicitConnections then c:stop()end c._complete=true c._onComplete:fire()end return e end function ai.setGoal(c,d)assert(not d.step,[[goals contains disallowed property "step". Did you mean to put a table of goals here?]])c._complete=false c._onStart:fire()for e,f in pairs(d)do local g=assert(c._motors[e],('Unknown motor for key %s'):format(e))g:setGoal(f)end if c._useImplicitConnections then c:start()end end function ai.getValue(c)local d={}for e,f in pairs(c._motors)do d[e]=f:getValue()end return d end function ai.__tostring(c)return'Motor(Group)'end return ai end,[34]=function()local aa,ab,ac,ad,ae=b(34)return function()local af,ag,ah=ac(ab.Parent.GroupMotor),ac(ab.Parent.Instant),ac(ab.Parent.Spring)it('should complete when all child motors are complete',function()local ai=af.new({A=1,B=2},false)expect(ai._complete).to.equal(true)ai:setGoal{A=ag.new(3),B=ah.new(4,{frequency=7.5,dampingRatio=1})}expect(ai._complete).to.equal(false)ai:step(1.6666666666666665E-2)expect(ai._complete).to.equal(false)for aj=1,30 do ai:step(1.6666666666666665E-2)end expect(ai._complete).to.equal(true)end)it('should start when the goal is set',function()local ai,aj=af.new({A=0},false),false ai:onStart(function()aj=not aj end)ai:setGoal{A=ag.new(1)}expect(aj).to.equal(true)ai:setGoal{A=ag.new(1)}expect(aj).to.equal(false)end)it('should properly return all values',function()local ai=af.new({A=1,B=2},false)local aj=ai:getValue()expect(aj.A).to.equal(1)expect(aj.B).to.equal(2)end)it('should error when a goal is given to GroupMotor.new',function()local ai=pcall(function()af.new(ag.new(0))end)expect(ai).to.equal(false)end)it([[should error when a single goal is provided to GroupMotor:step]],function()local ai=pcall(function()af.new{a=1}:setGoal(ag.new(0))end)expect(ai).to.equal(false)end)end end,[35]=function()local aa,ab,ac,ad,ae=b(35)local af={}af.__index=af function af.new(ag)return setmetatable({_targetValue=ag},af)end function af.step(ag)return{complete=true,value=ag._targetValue}end return af end,[36]=function()local aa,ab,ac,ad,ae=b(36)return function()local af=ac(ab.Parent.Instant)it('should return a completed state with the provided value',function()local ag=af.new(1.23)local ah=ag:step(0.1,{value=0,complete=false})expect(ah.complete).to.equal(true)expect(ah.value).to.equal(1.23)end)end end,[37]=function()local aa,ab,ac,ad,ae=b(37)local af={}af.__index=af function af.new(ag,ah)assert(ag,'Missing argument #1: targetValue')ah=ah or{}return setmetatable({_targetValue=ag,_velocity=ah.velocity or 1},af)end function af.step(ag,ah,ai)local aj,c,d=ah.value,ag._velocity,ag._targetValue local e=ai*c local f=e>=math.abs(d-aj)aj=aj+e*(d>aj and 1 or-1)if f then aj=ag._targetValue c=0 end return{complete=f,value=aj,velocity=c}end return af end,[38]=function()local aa,ab,ac,ad,ae=b(38)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Linear)describe('completed state',function()local ah,ai=af.new(0,false),ag.new(1,{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(1)end)end)describe('uncompleted state',function()local ah,ai=af.new(0,false),ag.new(1,{velocity=1})ah:setGoal(ai)for aj=1,59 do ah:step(1.6666666666666665E-2)end it('should be uncomplete',function()expect(ah._state.complete).to.equal(false)end)end)describe('negative velocity',function()local ah,ai=af.new(1,false),ag.new(0,{velocity=1})ah:setGoal(ai)for aj=1,60 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(0)end)end)end end,[39]=function()local aa,ab,ac,ad,ae=b(39)local af={}af.__index=af function af.new(ag,ah)return setmetatable({signal=ag,connected=true,_handler=ah},af)end function af.disconnect(ag)if ag.connected then ag.connected=false for ah,ai in pairs(ag.signal._connections)do if ai==ag then table.remove(ag.signal._connections,ah)return end end end end local ag={}ag.__index=ag function ag.new()return setmetatable({_connections={},_threads={}},ag)end function ag.fire(ah,...)for ai,aj in pairs(ah._connections)do aj._handler(...)end for c,d in pairs(ah._threads)do coroutine.resume(d,...)end ah._threads={}end function ag.connect(ah,aj)local c=af.new(ah,aj)table.insert(ah._connections,c)return c end function ag.wait(ah)table.insert(ah._threads,coroutine.running())return coroutine.yield()end return ag end,[40]=function()local aa,ab,ac,ad,ae=b(40)return function()local af=ac(ab.Parent.Signal)it('should invoke all connections, instantly',function()local ag,ah,aj=(af.new())ag:connect(function(c)ah=c end)ag:connect(function(c)aj=c end)ag:fire'hello'expect(ah).to.equal'hello'expect(aj).to.equal'hello'end)it('should return values when :wait() is called',function()local ag=af.new()spawn(function()ag:fire(123,'hello')end)local ah,aj=ag:wait()expect(ah).to.equal(123)expect(aj).to.equal'hello'end)it('should properly handle disconnections',function()local ag,ah=af.new(),false local aj=ag:connect(function()ah=true end)aj:disconnect()ag:fire()expect(ah).to.equal(false)end)end end,[41]=function()local aa,ab,ac,ad,ae=b(41)local af=ac(ab.Parent.BaseMotor)local ag=setmetatable({},af)ag.__index=ag function ag.new(ah,aj)assert(ah,'Missing argument #1: initialValue')assert(typeof(ah)=='number','initialValue must be a number!')local c=setmetatable(af.new(),ag)if aj~=nil then c._useImplicitConnections=aj else c._useImplicitConnections=true end c._goal=nil c._state={complete=true,value=ah}return c end function ag.step(ah,aj)if ah._state.complete then return true end local c=ah._goal:step(ah._state,aj)ah._state=c ah._onStep:fire(c.value)if c.complete then if ah._useImplicitConnections then ah:stop()end ah._onComplete:fire()end return c.complete end function ag.getValue(ah)return ah._state.value end function ag.setGoal(ah,aj)ah._state.complete=false ah._goal=aj ah._onStart:fire()if ah._useImplicitConnections then ah:start()end end function ag.__tostring(ah)return'Motor(Single)'end return ag end,[42]=function()local aa,ab,ac,ad,ae=b(42)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Instant)it('should assign new state on step',function()local ah=af.new(0,false)ah:setGoal(ag.new(5))ah:step(1.6666666666666665E-2)expect(ah._state.complete).to.equal(true)expect(ah._state.value).to.equal(5)end)it([[should invoke onComplete listeners when the goal is completed]],function()local ah,aj=af.new(0,false),false ah:onComplete(function()aj=true end)ah:setGoal(ag.new(5))ah:step(1.6666666666666665E-2)expect(aj).to.equal(true)end)it('should start when the goal is set',function()local ah,aj=af.new(0,false),false ah:onStart(function()aj=not aj end)ah:setGoal(ag.new(5))expect(aj).to.equal(true)ah:setGoal(ag.new(5))expect(aj).to.equal(false)end)end end,[43]=function()local aa,ab,ac,ad,ae=b(43)local af,ag,ah,aj=0.001,0.001,0.0001,{}aj.__index=aj function aj.new(c,d)assert(c,'Missing argument #1: targetValue')d=d or{}return setmetatable({_targetValue=c,_frequency=d.frequency or 4,_dampingRatio=d.dampingRatio or 1},aj)end function aj.step(c,d,e)local f,g,h,i,j=c._dampingRatio,c._frequency*2*math.pi,c._targetValue,d.value,d.velocity or 0 local k,l,m,n=i-h,(math.exp(-f*g*e))if f==1 then m=(k*(1+g*e)+j*e)*l+h n=(j*(1-g*e)-k*(g*g*e))*l elseif f<1 then local o=math.sqrt(1-f*f)local p,s,t=math.cos(g*o*e),(math.sin(g*o*e))if o>ah then t=s/o else local u=e*g t=u+((u*u)*(o*o)*(o*o)/20-o*o)*(u*u*u)/6 end local u if g*o>ah then u=s/(g*o)else local v=g*o u=e+((e*e)*(v*v)*(v*v)/20-v*v)*(e*e*e)/6 end m=(k*(p+f*t)+j*u)*l+h n=(j*(p-t*f)-k*(t*g))*l else local o=math.sqrt(f*f-1)local p,s=-g*(f-o),-g*(f+o)local t=(j-k*p)/(2*g*o)local u=k-t local v,w=u*math.exp(p*e),t*math.exp(s*e)m=v+w+h n=v*p+w*s end local o=math.abs(n)<af and math.abs(m-h)<ag return{complete=o,value=o and h or m,velocity=n}end return aj end,[44]=function()local aa,ab,ac,ad,ae=b(44)return function()local af,ag=ac(ab.Parent.SingleMotor),ac(ab.Parent.Spring)describe('completed state',function()local ah,aj=af.new(0,false),ag.new(1,{frequency=2,dampingRatio=0.75})ah:setGoal(aj)for c=1,100 do ah:step(1.6666666666666665E-2)end it('should complete',function()expect(ah._state.complete).to.equal(true)end)it('should be exactly the goal value when completed',function()expect(ah._state.value).to.equal(1)end)end)it('should inherit velocity',function()local ah=af.new(0,false)ah._state={complete=false,value=0,velocity=-5}local aj=ag.new(1,{frequency=2,dampingRatio=1})ah:setGoal(aj)ah:step(1.6666666666666665E-2)expect(ah._state.velocity<0).to.equal(true)end)end end,[45]=function()local aa,ab,ac,ad,ae=b(45)local af=function(af)local ag=tostring(af):match'^Motor%((.+)%)$'if ag then return true,ag else return false end end return af end,[46]=function()local aa,ab,ac,ad,ae=b(46)return function()local af,ag,ah=ac(ab.Parent.isMotor),ac(ab.Parent.SingleMotor),ac(ab.Parent.GroupMotor)local aj,c=ag.new(0),ah.new{}it('should properly detect motors',function()expect(af(aj)).to.equal(true)expect(af(c)).to.equal(true)end)it("shouldn't detect things that aren't motors",function()expect(af{}).to.equal(false)end)it('should return the proper motor type',function()local d,e=af(aj)local f,g=af(c)expect(e).to.equal'Single'expect(g).to.equal'Group'end)end end,[47]=function()local aa,ab,ac,ad,ae=b(47)local af={Names={'Dark','Darker','Light','Aqua','Amethyst','Rose'}}for ag,ah in next,ab:GetChildren()do local aj=ac(ah)af[aj.Name]=aj end return af end,[48]=function()local aa,ab,ac,ad,ae=b(48)return{Name='Amethyst',Accent=Color3.fromRGB(97,62,167),AcrylicMain=Color3.fromRGB(20,20,20),AcrylicBorder=Color3.fromRGB(110,90,130),AcrylicGradient=ColorSequence.new(Color3.fromRGB(85,57,139),Color3.fromRGB(40,25,65)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(95,75,110),Tab=Color3.fromRGB(160,140,180),Element=Color3.fromRGB(140,120,160),ElementBorder=Color3.fromRGB(60,50,70),InElementBorder=Color3.fromRGB(100,90,110),ElementTransparency=0.87,ToggleSlider=Color3.fromRGB(140,120,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(140,120,160),DropdownFrame=Color3.fromRGB(170,160,200),DropdownHolder=Color3.fromRGB(60,45,80),DropdownBorder=Color3.fromRGB(50,40,65),DropdownOption=Color3.fromRGB(140,120,160),Keybind=Color3.fromRGB(140,120,160),Input=Color3.fromRGB(140,120,160),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(60,45,80),DialogHolder=Color3.fromRGB(45,30,65),DialogHolderLine=Color3.fromRGB(40,25,60),DialogButton=Color3.fromRGB(60,45,80),DialogButtonBorder=Color3.fromRGB(95,80,110),DialogBorder=Color3.fromRGB(85,70,100),DialogInput=Color3.fromRGB(70,55,85),DialogInputLine=Color3.fromRGB(175,160,190),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(140,120,160),HoverChange=0.04}end,[49]=function()local aa,ab,ac,ad,ae=b(49)return{Name='Aqua',Accent=Color3.fromRGB(60,165,165),AcrylicMain=Color3.fromRGB(20,20,20),AcrylicBorder=Color3.fromRGB(50,100,100),AcrylicGradient=ColorSequence.new(Color3.fromRGB(60,140,140),Color3.fromRGB(40,80,80)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(60,120,120),Tab=Color3.fromRGB(140,180,180),Element=Color3.fromRGB(110,160,160),ElementBorder=Color3.fromRGB(40,70,70),InElementBorder=Color3.fromRGB(80,110,110),ElementTransparency=0.84,ToggleSlider=Color3.fromRGB(110,160,160),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(110,160,160),DropdownFrame=Color3.fromRGB(160,200,200),DropdownHolder=Color3.fromRGB(40,80,80),DropdownBorder=Color3.fromRGB(40,65,65),DropdownOption=Color3.fromRGB(110,160,160),Keybind=Color3.fromRGB(110,160,160),Input=Color3.fromRGB(110,160,160),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(130,170,170),Dialog=Color3.fromRGB(40,80,80),DialogHolder=Color3.fromRGB(30,60,60),DialogHolderLine=Color3.fromRGB(25,50,50),DialogButton=Color3.fromRGB(40,80,80),DialogButtonBorder=Color3.fromRGB(80,110,110),DialogBorder=Color3.fromRGB(50,100,100),DialogInput=Color3.fromRGB(45,90,90),DialogInputLine=Color3.fromRGB(130,170,170),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(110,160,160),HoverChange=0.04}end,[50]=function()local aa,ab,ac,ad,ae=b(50)return{Name='Dark',Accent=Color3.fromRGB(96,205,255),AcrylicMain=Color3.fromRGB(60,60,60),AcrylicBorder=Color3.fromRGB(90,90,90),AcrylicGradient=ColorSequence.new(Color3.fromRGB(40,40,40),Color3.fromRGB(40,40,40)),AcrylicNoise=0.9,TitleBarLine=Color3.fromRGB(75,75,75),Tab=Color3.fromRGB(120,120,120),Element=Color3.fromRGB(120,120,120),ElementBorder=Color3.fromRGB(35,35,35),InElementBorder=Color3.fromRGB(90,90,90),ElementTransparency=0.87,ToggleSlider=Color3.fromRGB(120,120,120),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(120,120,120),DropdownFrame=Color3.fromRGB(160,160,160),DropdownHolder=Color3.fromRGB(45,45,45),DropdownBorder=Color3.fromRGB(35,35,35),DropdownOption=Color3.fromRGB(120,120,120),Keybind=Color3.fromRGB(120,120,120),Input=Color3.fromRGB(160,160,160),InputFocused=Color3.fromRGB(10,10,10),InputIndicator=Color3.fromRGB(150,150,150),Dialog=Color3.fromRGB(45,45,45),DialogHolder=Color3.fromRGB(35,35,35),DialogHolderLine=Color3.fromRGB(30,30,30),DialogButton=Color3.fromRGB(45,45,45),DialogButtonBorder=Color3.fromRGB(80,80,80),DialogBorder=Color3.fromRGB(70,70,70),DialogInput=Color3.fromRGB(55,55,55),DialogInputLine=Color3.fromRGB(160,160,160),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(120,120,120),HoverChange=0.07}end,[51]=function()local aa,ab,ac,ad,ae=b(51)return{Name='Darker',Accent=Color3.fromRGB(72,138,182),AcrylicMain=Color3.fromRGB(30,30,30),AcrylicBorder=Color3.fromRGB(60,60,60),AcrylicGradient=ColorSequence.new(Color3.fromRGB(25,25,25),Color3.fromRGB(15,15,15)),AcrylicNoise=0.94,TitleBarLine=Color3.fromRGB(65,65,65),Tab=Color3.fromRGB(100,100,100),Element=Color3.fromRGB(70,70,70),ElementBorder=Color3.fromRGB(25,25,25),InElementBorder=Color3.fromRGB(55,55,55),ElementTransparency=0.82,DropdownFrame=Color3.fromRGB(120,120,120),DropdownHolder=Color3.fromRGB(35,35,35),DropdownBorder=Color3.fromRGB(25,25,25),Dialog=Color3.fromRGB(35,35,35),DialogHolder=Color3.fromRGB(25,25,25),DialogHolderLine=Color3.fromRGB(20,20,20),DialogButton=Color3.fromRGB(35,35,35),DialogButtonBorder=Color3.fromRGB(55,55,55),DialogBorder=Color3.fromRGB(50,50,50),DialogInput=Color3.fromRGB(45,45,45),DialogInputLine=Color3.fromRGB(120,120,120)}end,[52]=function()local aa,ab,ac,ad,ae=b(52)return{Name='Light',Accent=Color3.fromRGB(0,103,192),AcrylicMain=Color3.fromRGB(200,200,200),AcrylicBorder=Color3.fromRGB(120,120,120),AcrylicGradient=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255)),AcrylicNoise=0.96,TitleBarLine=Color3.fromRGB(160,160,160),Tab=Color3.fromRGB(90,90,90),Element=Color3.fromRGB(255,255,255),ElementBorder=Color3.fromRGB(180,180,180),InElementBorder=Color3.fromRGB(150,150,150),ElementTransparency=0.65,ToggleSlider=Color3.fromRGB(40,40,40),ToggleToggled=Color3.fromRGB(255,255,255),SliderRail=Color3.fromRGB(40,40,40),DropdownFrame=Color3.fromRGB(200,200,200),DropdownHolder=Color3.fromRGB(240,240,240),DropdownBorder=Color3.fromRGB(200,200,200),DropdownOption=Color3.fromRGB(150,150,150),Keybind=Color3.fromRGB(120,120,120),Input=Color3.fromRGB(200,200,200),InputFocused=Color3.fromRGB(100,100,100),InputIndicator=Color3.fromRGB(80,80,80),Dialog=Color3.fromRGB(255,255,255),DialogHolder=Color3.fromRGB(240,240,240),DialogHolderLine=Color3.fromRGB(228,228,228),DialogButton=Color3.fromRGB(255,255,255),DialogButtonBorder=Color3.fromRGB(190,190,190),DialogBorder=Color3.fromRGB(140,140,140),DialogInput=Color3.fromRGB(250,250,250),DialogInputLine=Color3.fromRGB(160,160,160),Text=Color3.fromRGB(0,0,0),SubText=Color3.fromRGB(40,40,40),Hover=Color3.fromRGB(50,50,50),HoverChange=0.16}end,[53]=function()local aa,ab,ac,ad,ae=b(53)return{Name='Rose',Accent=Color3.fromRGB(180,55,90),AcrylicMain=Color3.fromRGB(40,40,40),AcrylicBorder=Color3.fromRGB(130,90,110),AcrylicGradient=ColorSequence.new(Color3.fromRGB(190,60,135),Color3.fromRGB(165,50,70)),AcrylicNoise=0.92,TitleBarLine=Color3.fromRGB(140,85,105),Tab=Color3.fromRGB(180,140,160),Element=Color3.fromRGB(200,120,170),ElementBorder=Color3.fromRGB(110,70,85),InElementBorder=Color3.fromRGB(120,90,90),ElementTransparency=0.86,ToggleSlider=Color3.fromRGB(200,120,170),ToggleToggled=Color3.fromRGB(0,0,0),SliderRail=Color3.fromRGB(200,120,170),DropdownFrame=Color3.fromRGB(200,160,180),DropdownHolder=Color3.fromRGB(120,50,75),DropdownBorder=Color3.fromRGB(90,40,55),DropdownOption=Color3.fromRGB(200,120,170),Keybind=Color3.fromRGB(200,120,170),Input=Color3.fromRGB(200,120,170),InputFocused=Color3.fromRGB(20,10,30),InputIndicator=Color3.fromRGB(170,150,190),Dialog=Color3.fromRGB(120,50,75),DialogHolder=Color3.fromRGB(95,40,60),DialogHolderLine=Color3.fromRGB(90,35,55),DialogButton=Color3.fromRGB(120,50,75),DialogButtonBorder=Color3.fromRGB(155,90,115),DialogBorder=Color3.fromRGB(100,70,90),DialogInput=Color3.fromRGB(135,55,80),DialogInputLine=Color3.fromRGB(190,160,180),Text=Color3.fromRGB(240,240,240),SubText=Color3.fromRGB(170,170,170),Hover=Color3.fromRGB(200,120,170),HoverChange=0.04}end}do local ab,ac,ad,ae,af,ag,ah,aj,c,e,f,g,h,i,j,k=task,setmetatable,error,newproxy,getmetatable,next,table,unpack,coroutine,script,type,require,pcall,getfenv,setfenv,rawget local l,m,n,o,p,s,t,u,v,w,x=ah.insert,ah.remove,ah.freeze or function(l)return l end,ab and ab.defer or function(l,...)local m=c.create(l)c.resume(m,...)return m end,'0.0.0-venv',{},{},{},{},{},{}local y,z={GetChildren=function(y)local z,A=x[y],{}for B in ag,z do l(A,B)end return A end,FindFirstChild=function(y,z)if not z then ad('Argument 1 missing or nil',2)end for A in ag,x[y]do if A.Name==z then return A end end return end,GetFullName=function(y)local z,A=y.Name,y.Parent while A do z=A.Name..'.'..z A=A.Parent end return'VirtualEnv.'..z end},{}for A,B in ag,y do z[A]=function(C,...)if not x[C]then ad("Expected ':' not '.' calling member function "..A,1)end return B(C,...)end end local C=function(C,D,E)local F,G,H,I,J=ac({},{__mode='k'}),function(F)ad(F..' is not a valid (virtual) member of '..C..' "'..D..'"',1)end,function(F)ad('Unable to assign (virtual) property '..F..'. Property is read only',1)end,(ae(true))local K=af(I)K.__index=function(L,M)if M=='ClassName'then return C elseif M=='Name'then return D elseif M=='Parent'then return E elseif C=='StringValue'and M=='Value'then return J else local N=z[M]if N then return N end end for N in ag,F do if N.Name==M then return N end end G(M)end K.__newindex=function(L,M,N)if M=='ClassName'then H(M)elseif M=='Name'then D=N elseif M=='Parent'then if N==I then return end if E~=nil then x[E][I]=nil end E=N if N~=nil then x[N][I]=true end elseif C=='StringValue'and M=='Value'then J=N else G(M)end end K.__tostring=function()return D end x[I]=F if E~=nil then x[E][I]=true end return I end local function D(E,F)local G,H,I,J=E[1],E[2],E[3],E[4]local K=m(I,1)local L=C(H,K,F)s[G]=L if I then for M,N in ag,I do L[M]=N end end if J then for M,N in ag,J do D(N,L)end end return L end local E={}for F,G in ag,a do l(E,D(G))end for H,I in ag,aa do local J=s[H]t[J]=I local K=J.ClassName if K=='LocalScript'or K=='Script'then l(v,J)end end local J=function(J)local K,L=J.ClassName,u[J]if L and K=='ModuleScript'then return aj(L)end local M=t[J]if not M then return end if K=='LocalScript'or K=='Script'then M()return else local N={M()}u[J]=N return aj(N)end end function b(K)local L=s[K]local M=t[L]if not M then return end local N,O,P,Q,R,S,T=false,n{Version=p,Script=e,Shared=w,GetScript=function()return e end,GetShared=function()return w end},L,function(N,...)if x[N]and N.ClassName=='ModuleScript'and t[N]then return J(N)end return g(N,...)end local U,V=function(U,...)if not N then T()end if f(U)=='number'and U>=0 then if U==0 then return S else U=U+1 local V,W=h(i,U)if V and W==R then return S end end end return i(U,...)end,function(U,V,...)if not N then T()end if f(U)=='number'and U>=0 then if U==0 then return j(S,V)else U=U+1 local W,X=h(i,U)if W and X==R then return j(S,V)end end end return j(U,V,...)end function T()R=i(0)local W={maui=O,script=P,require=Q,getfenv=U,setfenv=V}S=ac({},{__index=function(X,Y)local Z=k(S,Y)if Z~=nil then return Z end local _=W[Y]if _~=nil then return _ end return R[Y]end})j(M,S)N=true end return O,P,Q,U,V end for K,L in ag,v do o(J,L)end do local M for N,O in ag,E do if O.ClassName=='ModuleScript'and O.Name=='MainModule'then M=O break end end if M then return J(M)end end end


--[[FLUENT_VENDOR_END]]
end
if not workspace.CurrentCamera then
    local cameraDeadline=os.clock()+5
    repeat task.wait(0.1) until workspace.CurrentCamera or os.clock()>=cameraDeadline
end
if not workspace.CurrentCamera then unload();error("Fluent: câmera ainda indisponível; tente novamente ou use o backup XERECA",0) end
local vendorOk,Fluent=pcall(initFluentVendor)
if not vendorOk then
    unload()
    for _,parent in ipairs({PlayerGui,game:GetService("CoreGui")}) do
        local orphan=parent:FindFirstChild("_XerecaFluent")
        if orphan then orphan:Destroy() end
    end
    error("Fluent não iniciou; use o loadstring do backup. "..tostring(Fluent),0)
end
bind(Fluent.GUI.Destroying,unload,"fluent.destroy")
table.insert(cleanupFns,function()
    Fluent:Destroy()
    if Fluent.GUI.Parent then Fluent.GUI:Destroy() end
end)
Fluent.GUI.Name="_XerecaFluent"
Fluent.GUI.Parent=PlayerGui
Fluent.GUI.DisplayOrder=99
uiGui.DisplayOrder=100
local v=viewport()
local windowOk,FluentWindow=pcall(function() return Fluent:CreateWindow({Title="XERECA HUB",SubTitle="Fluent • prévia",TabWidth=155,
    Size=UDim2.fromOffset(math.min(700,math.max(320,v.X-32)),math.min(500,math.max(260,v.Y-60))),
    Acrylic=false,Theme="Dark",MinimizeKey=Enum.KeyCode.LeftControl}) end)
if not windowOk then unload();error("Fluent: falha ao criar janela; use o backup. "..tostring(FluentWindow),0) end
local Main=FluentWindow.Root
local isUIOpen=true
local state="normal"
local openTween,sizeTween
local cancelDrag
local function setOpen(open)
    if destroyed then return end
    Main.Visible=open==true
    FluentWindow.Minimized=not Main.Visible
    isUIOpen=Main.Visible
    state=not isUIOpen and "min" or (FluentWindow.Maximized and "max" or "normal")
    if cancelDrag then cancelDrag() end
end
local function toggleUI() setOpen(not Main.Visible) end
bind(Main:GetPropertyChangedSignal("Visible"),function()
    isUIOpen=Main.Visible
    FluentWindow.Minimized=not isUIOpen
    state=not isUIOpen and "min" or (FluentWindow.Maximized and "max" or "normal")
end,"fluent.visibility")
bind(Main.Destroying,unload,"fluent.window.destroy")
local Float=new("TextButton",{Name="FluentFloat",Text="UI",Size=UDim2.fromOffset(56,56),Position=UDim2.fromOffset(20,80),Font=Enum.Font.GothamBold,TextSize=17,AutoButtonColor=false,Theme={BackgroundColor3="Accent",TextColor3="Text"}},uiGui)
new("UICorner",{CornerRadius=UDim.new(1,0)},Float)
local fluentTabs={}
local tabIcons={Home="home",Player="user",Visual="eye",Settings="settings",Farm="swords",ESP="scan",Fruit="apple",Teleport="map-pin",Compras="shopping-cart",Raids="flame",Status="activity"}
local function addTab(name)
    local tab=FluentWindow:AddTab({Title=name,Icon=tabIcons[name] or "layers"})
    local page=tab.ContainerFrame
    fluentTabs[page]=tab
    return page
end
local Home=addTab("Home")
local PlayerT=addTab("Player")
local Visual=addTab("Visual")
local Settings=addTab("Settings")
local Farm=addTab("Farm")
local ESPtab=addTab("ESP")
local Fruit=addTab("Fruit")
local function notify(opts)
    if destroyed then return end
    opts=opts or {}
    Fluent:Notify({Title=opts.Title or "XERECA",Content=opts.Text or opts.Content or "",Duration=opts.Duration or 4})
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


-- Adapters keep the existing gameplay's Set/Get callbacks; startup never enables jobs.
local legacyBtn,legacyToggle,legacySlider,legacyLabel,legacySection,legacyTextbox=addBtn,addToggle,addSlider,addLabel,addSection,addTextbox
local controlCounter=0
local function controlId()
    controlCounter=controlCounter+1
    return "Xereca_"..tostring(controlCounter)
end
local function dispatch(label,callback,...)
    if destroyed or not callback then return end
    local args=table.pack(...)
    local ok,err=xpcall(function() callback(table.unpack(args,1,args.n)) end,function(e) return debug.traceback(tostring(e),2) end)
    if not ok then debugLog("ERROR",label,err);error(err,0) end
end
addBtn=function(parent,text,cb)
    local tab=fluentTabs[parent]
    if not tab then return legacyBtn(parent,text,cb) end
    return tab:AddButton({Title=text,Callback=function() dispatch("button."..text,cb) end})
end
addToggle=function(parent,label,default,cb)
    local tab=fluentTabs[parent]
    if not tab then return legacyToggle(parent,label,default,cb) end
    local ready=false
    local api={Value=default==true}
    local native=tab:AddToggle(controlId(),{Title=label,Default=api.Value,Callback=function(value)
        if not ready or destroyed then return end
        api.Value=value==true;dispatch("toggle."..label,cb,api.Value)
    end})
    api.Get=function() return api.Value end
    api.Set=function(value)
        if destroyed then return end
        value=value==true
        if api.Value~=value then native:SetValue(value) end
    end
    api.Destroy=function() native:Destroy() end
    ready=true
    return api
end
addSlider=function(parent,opts)
    local tab=fluentTabs[parent]
    if not tab then return legacySlider(parent,opts) end
    local step=opts.Step or 1
    local ready,normalizing=false,false
    local api={Value=opts.Default or opts.Min or 0}
    local native
    local function quantize(value)
        return math.clamp(opts.Min+math.floor((value-opts.Min)/step+0.5)*step,opts.Min,opts.Max)
    end
    native=tab:AddSlider(controlId(),{Title=opts.Name,Description=opts.Suffix or "",Min=opts.Min,Max=opts.Max,Default=api.Value,Rounding=step<1 and 2 or 0,Callback=function(value)
        if not ready or normalizing or destroyed then return end
        local nextValue=quantize(value)
        if nextValue~=value then normalizing=true;native:SetValue(nextValue);normalizing=false end
        api.Value=nextValue;dispatch("slider."..opts.Name,opts.Callback,nextValue)
    end})
    api.Get=function() return api.Value end
    api.Set=function(value) if not destroyed then native:SetValue(quantize(value)) end end
    api.Destroy=function() native:Destroy() end
    ready=true
    return api
end
addLabel=function(parent,text)
    local tab=fluentTabs[parent]
    if not tab then return legacyLabel(parent,text) end
    local element=tab:AddParagraph({Title="",Content=text})
    element.DescLabel.RichText=false
    return element.DescLabel
end
addSection=function(parent,title)
    local tab=fluentTabs[parent]
    if not tab then return legacySection(parent,title) end
    return tab:AddSection(title)
end
addTextbox=function(parent,opts)
    local tab=fluentTabs[parent]
    if not tab then return legacyTextbox(parent,opts) end
    local ready,quiet=false,false
    local native=tab:AddInput(controlId(),{Title=opts.Placeholder or "Texto",Placeholder=opts.Placeholder or "",Default="",Finished=true,Callback=function(value)
        if ready and not quiet then dispatch("input",opts.Callback,value) end
    end})
    ready=true
    return {Get=function() return native.Value end,Set=function(value) if not destroyed then quiet=true;native:SetValue(tostring(value));quiet=false end end,Destroy=function() native:Destroy() end}
end
local function fluentDropdown(page,label,values,default,callback)
    local tab=assert(fluentTabs[page],"Fluent tab missing: "..label)
    local ready,quiet=false,false
    local selected=default
    local native=tab:AddDropdown(controlId(),{Title=label,Values=values,Default=default,Multi=false,Callback=function(value)
        if not ready or destroyed then return end
        selected=value;if not quiet then dispatch("dropdown."..label,callback,value) end
    end})
    ready=true
    return {Get=function() return selected end,Set=function(value,silent)
        if destroyed then return end
        quiet=silent==true;native:SetValue(value);selected=native.Value;quiet=false
    end,Refresh=function(items)
        if destroyed then return end
        quiet=true;native:SetValues(items);selected=native.Value;quiet=false
    end}
end
local originalApplyTheme=applyTheme
applyTheme=function(updateFns)
    originalApplyTheme(updateFns)
    Fluent:SetTheme(({Midnight="Darker",Dark="Dark",Light="Light"})[activeTheme] or "Dark")
end
addLabel(Home,"Prévia Fluent do XERECA HUB. Ctrl esquerdo e botão UI abrem/ocultam a janela. KILL descarrega tudo. A versão anterior foi salva antes desta troca.")
addToggle(Settings,"Fluent: transparência",true,function(on) Fluent:ToggleTransparency(on) end)

local rollbackBusy=false
addBtn(Settings,"Voltar para interface anterior (backup)",function()
    if destroyed or rollbackBusy then return end
    rollbackBusy=true
    local ok,chunk=pcall(function()
        local source=game:HttpGet("https://raw.githubusercontent.com/danielsolzapo-dev/roblox-scripts/5af5e68a48520997dc044708e75818fffa3a0bbb/RobloxUILibrary/Standalone.client.luau")
        local compiled,err=loadstring(source)
        assert(compiled,err)
        return compiled
    end)
    rollbackBusy=false
    if destroyed then return end
    if not ok then notify({Title="Backup",Text="Falha ao preparar a versão anterior: "..tostring(chunk)});return end
    unload()
    local started,err=pcall(chunk)
    if not started then warn("[XERECA backup] "..tostring(err)) end
end)

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
    local api={Distance=100,attackMobs=true,attackPlayers=true,Running=false,ManualEnabled=false,Delay=0.15}
    local RS=game:GetService("ReplicatedStorage")
    local worker
    local combatOwners={}
    local transport={Dispatches=0}
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
        transport.Dispatches=transport.Dispatches+1
        transport.LastSentAt=os.clock();transport.Target=enemy.Name
        transport.LastTransport=leftClick and leftClick:IsA("RemoteEvent") and "left_click_remote_sent" or "remote_sent"
        return true,transport.LastTransport
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
    function api:CanAttack()
        local c=LocalPlayer.Character
        local tool=c and c:FindFirstChildOfClass("Tool")
        if not tool or tool.ToolTip=="Gun" then return false end
        local own=tool:FindFirstChild("LeftClickRemote")
        return (own and own:IsA("RemoteEvent")) or (remote("RE/RegisterAttack")~=nil and remote("RE/RegisterHit")~=nil)
    end
    local function currentCombat()
        local newest
        for owner,entry in pairs(combatOwners) do
            if os.clock()-entry.Updated>0.8 then combatOwners[owner]=nil
            elseif not newest or entry.Updated>newest.Updated then newest=entry end
        end
        return newest
    end
    local function cancelWorker()
        api.Running=false;transport.Owner=nil
        if worker and worker~=coroutine.running() then pcall(task.cancel,worker) end
        worker=nil
    end
    local function ensureWorker()
        if destroyed or worker then return end
        api.Running=true
        worker=task.defer(function()
            local failures=0
            while not destroyed do
                local combat=currentCombat()
                if not api.ManualEnabled and not combat then break end
                transport.Owner=combat and combat.Owner or "Manual"
                local ok,err=pcall(function()
                    if combat then
                        if combat.Target then
                            local sent,reason=api:AttackTarget(combat.Target)
                            if not sent then transport.LastTransport=reason end
                        else transport.LastTransport="paused_for_skills" end
                    else api:AttackNearest() end
                end)
                if not ok then
                    failures=failures+1;debugLog("ERROR","FastAttack",err)
                    if failures>=3 then api.ManualEnabled=false;table.clear(combatOwners);notify({Title="FastAttack",Text=tostring(err)});break end
                else failures=0 end
                task.wait(api.Delay)
            end
            api.Running=false;worker=nil;transport.Owner=nil
        end)
    end
    function api:Start()
        self.ManualEnabled=true;ensureWorker()
    end
    function api:Stop()
        self.ManualEnabled=false
        if not currentCombat() then cancelWorker() end
    end
    function api:SetCombatTarget(owner,target)
        if destroyed then return end
        combatOwners[owner]={Owner=owner,Target=target,Updated=os.clock()}
        ensureWorker()
    end
    function api:ReleaseCombat(owner)
        combatOwners[owner]=nil
        if not self.ManualEnabled and not currentCombat() then cancelWorker() end
    end
    function api:StopAll()
        self.ManualEnabled=false;table.clear(combatOwners);cancelWorker()
    end
    function api:GetState()
        local result=table.clone(transport)
        result.Running=self.Running;result.ManualEnabled=self.ManualEnabled
        return result
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
table.insert(cleanupFns, function() fastAttackApi:StopAll(); if _G.MatsuneFastAttack==fastAttackApi then _G.MatsuneFastAttack=nil end end)

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
    if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == Enum.KeyCode.LeftControl then toggleUI() end
end)

-- Keep viewport changes scoped to the new Fluent window and floating button.
local cameraConnection
local function refreshViewport()
    if destroyed then return end
    local vp=viewport()
    Float.Position=UDim2.fromOffset(math.clamp(Float.Position.X.Offset,0,math.max(0,vp.X-56)),math.clamp(Float.Position.Y.Offset,0,math.max(0,vp.Y-56)))
    if FluentWindow.Maximized then FluentWindow.Maximize(true,false,true) end
end
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect();cameraConnection=nil end
    local camera=workspace.CurrentCamera
    if camera then cameraConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshViewport) end
    refreshViewport()
end
bind(workspace:GetPropertyChangedSignal("CurrentCamera"),watchCamera,"fluent.camera")
table.insert(cleanupFns,function() if cameraConnection then cameraConnection:Disconnect() end end)
watchCamera()
cancelDrag=function() fd=false;touchId=nil end
bind(UserInputService.WindowFocusReleased,cancelDrag)

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
    local placeSeas={[2753915549]=1,[85211729168715]=1,[4442272183]=2,[79091703265657]=2,[7449423635]=3,[100117331123089]=3}
    local function seaIndex() return placeSeas[game.PlaceId] end
    local function sourcePlaceId() return ({2753915549,4442272183,7449423635})[seaIndex()] or game.PlaceId end
    local supported=seaIndex()~=nil
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
        for i=#(previous.Owned or {}),1,-1 do previous.Owned[i]:Destroy() end
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
    local function holdFarmPosition(target)
        local lease=motionState
        if not lease or not lease.Root.Parent then return end
        if not lease.Holding then
            lease.Owned={}
            local function own(class,name)
                local object=Instance.new(class)
                lease.Owned[#lease.Owned+1]=object
                object.Name=name;object.Parent=lease.Root
                return object
            end
            local attachment=own("Attachment","_XerecaFarmHoldAttachment")
            local position=own("AlignPosition","_XerecaFarmHoldPosition")
            position.Mode=Enum.PositionAlignmentMode.OneAttachment
            position.Attachment0=attachment
            position.ApplyAtCenterOfMass=true
            position.RigidityEnabled=false
            position.MaxForce=100000000
            position.MaxVelocity=100
            position.Responsiveness=100
            position.Position=target.Position
            local orientation=own("AlignOrientation","_XerecaFarmHoldOrientation")
            orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment
            orientation.Attachment0=attachment
            orientation.RigidityEnabled=false
            orientation.MaxTorque=100000000
            orientation.MaxAngularVelocity=50
            orientation.Responsiveness=100
            orientation.CFrame=target-target.Position
            lease.PositionHold=position;lease.OrientationHold=orientation
            lease.Holding=true
        end
        lease.PositionHold.Position=target.Position
        lease.OrientationHold.CFrame=target-target.Position
        -- Anchoring is only temporary during travel. Combat uses world-space forces.
        -- Preserve a root that the game had already anchored before our movement.
        lease.Root.Anchored=lease.Anchored
        lease.Root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        lease.Root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    end
    local function move(target, owner)
        if owner=="Manual" then
            for name in pairs(movementJobs) do if flags[name] and controls[name] then controls[name].Set(false) end end
        end
        local _,h,root=character()
        if not root or typeof(target) ~= "CFrame" then return end
        if moveRoot==root and moveOwner==owner and moveTarget and motionState
            and (moveTarget.Position-target.Position).Magnitude<0.5 then
            -- Reuse the completed world's fixed hold without re-anchoring the root.
            -- Reacquiring an identical destination every farm tick interrupts attacks.
            if owner=="Farm" or (moveTween and moveTween.PlaybackState==Enum.PlaybackState.Playing) then return end
        end
        stopMove()
        moveOwner,moveRoot,moveTarget=owner,root,target
        suspendMotion(root,h)
        local delta=(root.Position-target.Position).Magnitude
        if delta<0.1 then
            if owner=="Farm" then holdFarmPosition(target) else releaseMotion() end
            return
        end
        moveTween=TweenService:Create(root,TweenInfo.new(math.max(0.1,delta/options.Speed),Enum.EasingStyle.Linear),{CFrame=target})
        local version=moveVersion
        moveTween.Completed:Once(function(playback)
            if moveVersion~=version then return end
            if playback==Enum.PlaybackState.Completed and owner=="Farm" then
                root.CFrame=target
                holdFarmPosition(target)
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
        if motionState.Holding then
            -- Do not force Anchored=true or overwrite CFrame while fighting.
            -- Constraints hold a world point and are independent of platforms/NPC falls.
            root.Anchored=motionState.Anchored
        else
            root.Anchored=true
            root.AssemblyLinearVelocity=Vector3.new(0,0,0)
            root.AssemblyAngularVelocity=Vector3.new(0,0,0)
        end
        for _,object in ipairs(c:GetDescendants()) do
            if object:IsA("BasePart") then
                if collisionState[object]==nil then collisionState[object]=object.CanCollide end
                object.CanCollide=false
            end
        end
    end,"features.movement.physics")
    local function stopJob(name)
        fastAttackApi:ReleaseCombat(name)
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
        return fluentDropdown(page,label,values,default,callback)
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
    local attackState={Phase="idle",Method="Auto",Attempts=0}
    local inputLease
    local function releaseInput()
        local lease=inputLease
        if not lease then return true end
        local ok,err=pcall(lease.Release)
        attackState.InputRelease=ok and "released" or tostring(err)
        if ok then inputLease=nil else debugLog("WARN","combat.release",err) end
        return ok
    end
    local function heldInput(release,down)
        inputLease={Release=release}
        local lease=inputLease
        local ok,err=pcall(down)
        if not ok then releaseInput();return false,tostring(err) end
        attackState.InputRelease="holding_60ms"
        trackTask(task.delay(0.06,function() if inputLease==lease then releaseInput() end end))
        return true
    end
    local function clearClickPoint()
        local camera=workspace.CurrentCamera
        if not camera then return nil end
        local v=camera.ViewportSize
        -- Do not send a mouse click into the Library or another interactive GUI.
        for _,fraction in ipairs({Vector2.new(0.95,0.88),Vector2.new(0.05,0.88),Vector2.new(0.95,0.15),Vector2.new(0.5,0.9)}) do
            local point=Vector2.new(v.X*fraction.X,v.Y*fraction.Y)
            local ok,objects=pcall(function() return PlayerGui:GetGuiObjectsAtPosition(point.X,point.Y) end)
            if ok and type(objects)=="table" then
                local blocked=false
                for _,object in ipairs(objects) do
                    if object.Visible and (object.Active or object:IsA("TextButton") or object:IsA("ImageButton") or object:IsA("TextBox")) then blocked=true;break end
                end
                if not blocked then return point end
            end
        end
        return nil
    end
    local function inputClick(method)
        if destroyed or not active then return false,"unloaded" end
        if UserInputService:GetFocusedTextBox() then return false,"typing" end
        if inputLease and not releaseInput() then return false,"release_failed" end
        if os.clock()-lastInputClick<0.15 then return false,"cooldown" end
        lastInputClick=os.clock()
        local camera=workspace.CurrentCamera
        local function r2()
            local vim=game:GetService("VirtualInputManager")
            local ok,err=heldInput(function() vim:SendKeyEvent(false,Enum.KeyCode.ButtonR2,false,game) end,
                function() vim:SendKeyEvent(true,Enum.KeyCode.ButtonR2,false,game) end)
            return ok,ok and "button_r2_sent" or err
        end
        if method=="Hoho R2" then return r2() end
        local point=clearClickPoint()
        attackState.ClickPosition=point
        if not point then
            attackState.InputFallback="no_clear_click_position"
            return r2()
        end
        local vu
        local available,serviceErr=pcall(function() vu=game:GetService("VirtualUser") end)
        local ok,err=false,serviceErr
        if available then
            ok,err=heldInput(function() vu:Button1Up(point,camera.CFrame) end,function()
                vu:CaptureController();vu:Button1Down(point,camera.CFrame)
            end)
        end
        if ok then attackState.InputFallback=nil;return true,"virtual_user_sent" end
        attackState.InputFallback=tostring(err)
        if inputLease then return false,"release_failed" end
        local fallback,reason=r2()
        if fallback then return true,reason end
        return false,"input_unavailable: "..tostring(err).." / "..tostring(reason)
    end
    local lastAttackTarget,lastAttackHealth,lastDamageAt
    local function fight(target,owner)
        local root=part(target)
        local hp,maxHP=health(target)
        if not root or hp<=0 then fastAttackApi:ReleaseCombat(owner);return end
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
        attackState.Health=hp;attackState.MaxHealth=maxHP
        attackState.Tool=tool and tool.Name or nil
        attackState.Distance=distance(target)
        if lastAttackTarget~=target then lastAttackTarget=target;lastAttackHealth=hp;lastDamageAt=nil end
        if hp<lastAttackHealth then lastDamageAt=os.clock() end
        lastAttackHealth=hp
        attackState.LastDamageAt=lastDamageAt
        if not tool then
            fastAttackApi:ReleaseCombat(owner);attackState.Phase="missing_weapon"
        elseif attackState.Distance>100 then
            fastAttackApi:ReleaseCombat(owner);attackState.Phase="approaching"
        elseif mastery or flags.SkillSpam or owner=="SeaCombat" then
            -- Pause manual M1 while the selected mastery/skills path owns combat.
            fastAttackApi:SetCombatTarget(owner,nil)
            skillAttack();attackState.Phase="skills_sent"
        elseif fastAttackApi.ManualEnabled or (attackState.Method=="Auto" and fastAttackApi:CanAttack()) then
            releaseInput()
            fastAttackApi:SetCombatTarget(owner,target)
            attackState.Input="shared_fast_attack"
            attackState.Phase="shared_fast_attack"
            attackState.Transport=fastAttackApi:GetState().LastTransport or "worker_started"
            attackState.Attempts=attackState.Attempts+1
        else
            fastAttackApi:ReleaseCombat(owner)
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
    local L_23_, L_24_, L_25_ = sourcePlaceId() == 2753915549, sourcePlaceId() == 4442272183, sourcePlaceId() == 7449423635
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
		if sourcePlaceId() == 2753915549 then
			MMon = "Military Spy"
			MPos = CFrame.new(- 5850.2802734375, 77.28675079345703, 8848.6748046875)
		elseif sourcePlaceId() == 4442272183 then
			MMon = "Lava Pirate"
			MPos = CFrame.new(- 5234.60595703125, 51.953372955322266, - 4732.27880859375)
		end
	elseif selected == "Angel Wings" then
		MMon = "Royal Soldier"
		MPos = CFrame.new(- 7827.15625, 5606.912109375, - 1705.5833740234375)
	elseif selected == "Leather" then
		if sourcePlaceId() == 2753915549 then
			MMon = "Pirate"
			MPos = CFrame.new(- 1211.8792724609375, 4.787090301513672, 3916.83056640625)
		elseif sourcePlaceId() == 4442272183 then
			MMon = "Marine Captain"
			MPos = CFrame.new(- 2010.5059814453125, 73.00115966796875, - 3326.620849609375)
		elseif sourcePlaceId() == 7449423635 then
			MMon = "Jungle Pirate"
			MPos = CFrame.new(- 11975.78515625, 331.7734069824219, - 10620.0302734375)
		end
	elseif selected == "Scrap Metal" then
		if sourcePlaceId() == 2753915549 then
			MMon = "Brute"
			MPos = CFrame.new(- 1132.4202880859375, 14.844913482666016, 4293.30517578125)
		elseif sourcePlaceId() == 4442272183 then
			MMon = "Mercenary"
			MPos = CFrame.new(- 972.307373046875, 73.04473876953125, 1419.2901611328125)
		elseif sourcePlaceId() == 7449423635 then
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

-- Hoho preload supplies optional catalog coordinates, never combat or executable code.
local function initPreload()
-- Adapted data from acsu123/HohoV2/BloxFruit/preload; see provenance.json.
-- Generated by extract_hoho.py; embedded data only, no remote loaders.
local preloadRows={
    [1]={
        {LevelReq=0,Mob="Trainee",Name="MarineQuest",Tier=1,Boss=false,Quest=CFrame.new(-2655,30,2113),Spawns={CFrame.new(-2674.52368164,32.1167221069,2186.97265625),CFrame.new(-2728.64111328,32.9167175293,1966.21789551),CFrame.new(-2741.04101562,32.9167175293,1900.01794434),CFrame.new(-2748.03735352,30.3167190552,2152.703125),CFrame.new(-2788.25097656,30.687002182,2281.48095703),CFrame.new(-2710.5703125,30.687002182,2242.84570312),CFrame.new(-2667.44116211,32.9167175293,1900.01794434)}},
        {LevelReq=10,Mob="Monkey",Name="JungleQuest",Tier=1,Boss=false,Quest=CFrame.new(-1679.76318359,48.7400054932,175.640014648),Spawns={CFrame.new(-1637.55456543,29.977350235,19.6401367188),CFrame.new(-1866.31335449,29.9336357117,21.5892028809),CFrame.new(-1450.64160156,28.9804954529,306.12121582),CFrame.new(-1610.23974609,29.165807724,399.664489746),CFrame.new(-1758.66125488,30.8861427307,-31.8153839111),CFrame.new(-1299.42724609,17.6543960571,81.4220199585),CFrame.new(-1525.55554199,27.246963501,163.957824707)}},
        {LevelReq=15,Mob="Gorilla",Name="JungleQuest",Tier=2,Boss=false,Quest=CFrame.new(-1679.76318359,48.7400054932,175.640014648),Spawns={CFrame.new(-1401.0880127,26.4667453766,-463.957061768),CFrame.new(-1387.32824707,14.4667444229,-577.800048828),CFrame.new(-1198.41894531,17.3037509918,-689.849060059),CFrame.new(-1266.56518555,14.4667453766,-462.023651123)}},
        {LevelReq=20,Mob="The Gorilla King",Name="JungleQuest",Tier=3,Boss=true,Quest=CFrame.new(-1679.76318359,48.7400054932,175.640014648),Spawns={CFrame.new(-1193.90661621,10.7214584351,-549.847290039)}},
        {LevelReq=30,Mob="Pirate",Name="BuggyQuest1",Tier=1,Boss=false,Quest=CFrame.new(-1151.58642578,16.6152420044,3863.125),Spawns={CFrame.new(-980.980773926,30.4456329346,3966.83227539),CFrame.new(-1313.74499512,18.8687286377,3964.18530273),CFrame.new(-1122.78271484,19.9353103638,3965.88183594),CFrame.new(-1285.08447266,18.0345458984,3886.96728516),CFrame.new(-1176.76513672,19.7420425415,4027.27001953),CFrame.new(-963.942016602,27.6460914612,4043.71508789)}},
        {LevelReq=40,Mob="Brute",Name="BuggyQuest1",Tier=2,Boss=false,Quest=CFrame.new(-1151.58642578,16.6152420044,3863.125),Spawns={CFrame.new(-1085.94348145,28.1044311523,4342.671875),CFrame.new(-942.354492188,29.7292480469,4387.24414062),CFrame.new(-1350.12817383,28.1044311523,4285.10888672),CFrame.new(-1436.78369141,28.1044311523,4357.19970703),CFrame.new(-1312.80505371,28.1044311523,4402.859375),CFrame.new(-1094.93334961,28.1044311523,4442.90722656)}},
        {LevelReq=55,Mob="Chef",Name="BuggyQuest1",Tier=3,Boss=true,Quest=CFrame.new(-1151.58642578,16.6152420044,3863.125),Spawns={CFrame.new(-1120.45214844,54.7070007324,4121.15722656)}},
        {LevelReq=60,Mob="Desert Bandit",Name="DesertQuest",Tier=1,Boss=false,Quest=CFrame.new(931.377990723,4.68400001526,4198.21289062),Spawns={CFrame.new(860.54107666,7.56500244141,4539.79736328),CFrame.new(999.850463867,7.56500244141,4490.33105469),CFrame.new(902.860229492,7.56500244141,4461.42138672),CFrame.new(931.70501709,7.56500244141,4564.53320312)}},
        {LevelReq=75,Mob="Desert Officer",Name="DesertQuest",Tier=2,Boss=false,Quest=CFrame.new(931.377990723,4.68400001526,4198.21289062),Spawns={CFrame.new(1523.7845459,15.284995079,4095.42822266),CFrame.new(1543.99267578,14.1150026321,4240.97558594),CFrame.new(1615.49060059,14.2480010986,4187.38623047),CFrame.new(1608.39758301,14.1480007172,4112.2890625)}},
        {LevelReq=90,Mob="Snow Bandit",Name="SnowQuest",Tier=1,Boss=false,Quest=CFrame.new(1400.56384277,77.3909988403,-1311.28503418),Spawns={CFrame.new(1519.47265625,77.9602355957,-1510.93786621),CFrame.new(1501.95739746,77.9602355957,-1402.37207031),CFrame.new(1260.2578125,77.9602355957,-1387.61035156),CFrame.new(1364.11621094,77.9602355957,-1429.65136719),CFrame.new(1431.75073242,77.9602355957,-1444.89233398)}},
        {LevelReq=100,Mob="Snowman",Name="SnowQuest",Tier=2,Boss=false,Quest=CFrame.new(1400.56384277,77.3909988403,-1311.28503418),Spawns={CFrame.new(1121.54980469,98.1665802002,-1669.02416992),CFrame.new(1149.48852539,98.2227401733,-1540.46386719),CFrame.new(1272.36193848,98.3291625977,-1647.2545166),CFrame.new(1246.76879883,98.3291625977,-1555.6940918)}},
        {LevelReq=105,Mob="Yeti",Name="SnowQuest",Tier=3,Boss=true,Quest=CFrame.new(1400.56384277,77.3909988403,-1311.28503418),Spawns={CFrame.new(1181.66162109,104.033042908,-1616.93188477)}},
        {LevelReq=120,Mob="Chief Petty Officer",Name="MarineQuest2",Tier=1,Boss=false,Quest=CFrame.new(-4699.33105469,4.74101066589,4227.63916016),Spawns={CFrame.new(-4780.54248047,13.8792819977,4419.90722656),CFrame.new(-4828.58251953,13.126077652,4196.78662109),CFrame.new(-4763.67675781,13.3913078308,4288.84277344),CFrame.new(-4674.6328125,11.0316886902,4483.32568359),CFrame.new(-4836.43701172,16.3296909332,4465.78173828),CFrame.new(-4650.59033203,11.0316886902,4562.09765625),CFrame.new(-5002.20996094,11.0316886902,4004.73925781),CFrame.new(-4938.36132812,11.0316886902,3995.87109375)}},
        {LevelReq=130,Mob="Vice Admiral",Name="MarineQuest2",Tier=2,Boss=true,Quest=CFrame.new(-4699.33105469,4.74101066589,4227.63916016),Spawns={CFrame.new(-5010.81982422,15.0615949631,4383.72753906)}},
        {LevelReq=150,Mob="Sky Bandit",Name="SkyQuest",Tier=1,Boss=false,Quest=CFrame.new(-4750.18017578,966.066711426,-748.241455078),Spawns={CFrame.new(-4973.74316406,280.721466064,-1119.43041992),CFrame.new(-5221.64453125,280.721466064,-1068.63989258),CFrame.new(-5157.06640625,280.721466064,-916.718017578),CFrame.new(-5014.03417969,280.721466064,-972.079345703)}},
        {LevelReq=175,Mob="Dark Master",Name="SkyQuest",Tier=2,Boss=false,Quest=CFrame.new(-4750.18017578,966.066711426,-748.241455078),Spawns={CFrame.new(-5206.77197266,504.74420166,-348.463867188),CFrame.new(-5411.25439453,504.932647705,-372.778625488),CFrame.new(-5283.16601562,505.063934326,-221.014190674),CFrame.new(-5269.00634766,504.982574463,-461.116241455)}},
        {LevelReq=190,Mob="Prisoner",Name="PrisonerQuest",Tier=1,Boss=false,Quest=CFrame.new(5208.33837891,18.8711032867,736.586303711),Spawns={CFrame.new(5457.69091797,7.13356637955,507.47543335),CFrame.new(5057.80957031,7.13356637955,567.153991699),CFrame.new(5192.98535156,7.13356637955,414.304901123),CFrame.new(5278.59130859,7.13356637955,391.556884766),CFrame.new(5370.83837891,7.13356637955,459.186523438)}},
        {LevelReq=210,Mob="Dangerous Prisoner",Name="PrisonerQuest",Tier=2,Boss=false,Quest=CFrame.new(5208.33837891,18.8711032867,736.586303711),Spawns={CFrame.new(5058.26269531,9.14381217957,900.918701172),CFrame.new(5295.2734375,9.14381217957,1104.78125),CFrame.new(5122.91357422,9.14381217957,969.896240234),CFrame.new(5188.85058594,9.14381217957,1058.125),CFrame.new(5456.38525391,9.14381217957,955.961364746)}},
        {LevelReq=225,Mob="Ruthless Prisoner",Name="ImpelQuest",Tier=1,Boss=false,Quest=CFrame.new(5320.66601562,18.8855781555,856.281433105),Spawns={CFrame.new(5329.33544922,49.4212989807,819.451477051),CFrame.new(5393.91503906,16.37200737,673.581542969),CFrame.new(5272.94140625,16.37200737,673.581542969),CFrame.new(5393.91503906,16.37200737,795.263671875),CFrame.new(5271.36230469,16.37200737,799.607910156)}},
        {LevelReq=230,Mob="Warden",Name="ImpelQuest",Tier=2,Boss=true,Quest=CFrame.new(5320.66601562,18.8855781555,856.281433105),Spawns={CFrame.new(5623.16552734,1.35667848587,733.808898926)}},
        {LevelReq=250,Mob="Toga Warrior",Name="ColosseumQuest",Tier=1,Boss=false,Quest=CFrame.new(-1342.25549316,11.1514205933,-2928.58081055),Spawns={CFrame.new(-1819.48034668,9.21899795532,-2736.56494141),CFrame.new(-1533.140625,12.4893217087,-2781.29345703),CFrame.new(-1620.10302734,12.4893217087,-2672.29345703),CFrame.new(-1829.72351074,9.02930355072,-2661.5324707),CFrame.new(-1694.75183105,9.21899795532,-2633.26269531),CFrame.new(-1973.13171387,9.02927780151,-2744.93530273)}},
        {LevelReq=275,Mob="Gladiator",Name="ColosseumQuest",Tier=2,Boss=false,Quest=CFrame.new(-1342.25549316,11.1514205933,-2928.58081055),Spawns={CFrame.new(-1238.91369629,11.6225595474,-3241.15893555),CFrame.new(-1212.63024902,11.6225595474,-3378.66992188),CFrame.new(-1144.47412109,11.6225595474,-3337.35913086),CFrame.new(-1118.91369629,11.6225595474,-3014.15893555),CFrame.new(-1161.91369629,11.6225595474,-3097.15893555)}},
        {LevelReq=300,Mob="Military Soldier",Name="MagmaQuest",Tier=1,Boss=false,Quest=CFrame.new(-5308.8671875,17.0349807739,8482.69824219),Spawns={CFrame.new(-5623.79833984,17.0067863464,8314.05664062),CFrame.new(-5266.39111328,17.1308708191,8554.19335938),CFrame.new(-5694.47998047,17.0067920685,8329.20703125),CFrame.new(-5337.08789062,17.1308403015,8629.31640625),CFrame.new(-5418.47802734,18.0090122223,8421.08398438)}},
        {LevelReq=325,Mob="Military Spy",Name="MagmaQuest",Tier=2,Boss=false,Quest=CFrame.new(-5308.8671875,17.0349807739,8482.69824219),Spawns={CFrame.new(-5952.54931641,76.9223327637,8742.40332031),CFrame.new(-5714.91845703,76.5920333862,8834.85839844),CFrame.new(-5808.98339844,77.3133239746,8791.20410156),CFrame.new(-5889.96289062,76.6140213013,8723.01074219)}},
        {LevelReq=350,Mob="Magma Admiral",Name="MagmaQuest",Tier=3,Boss=true,Quest=CFrame.new(-5308.8671875,17.0349807739,8482.69824219),Spawns={CFrame.new(-5625.70996094,55.4438209534,8623.01171875)}},
        {LevelReq=375,Mob="Fishman Warrior",Name="FishmanQuest",Tier=1,Boss=false,Quest=CFrame.new(61406.1953125,24.5187358856,1626.81640625),Spawns={CFrame.new(60715.9921875,25.2567386627,1284.89025879),CFrame.new(60892.2578125,23.8054046631,1500.49523926),CFrame.new(60788.3632812,23.8040161133,1484.52636719),CFrame.new(60930.921875,23.7948055267,1393.09350586),CFrame.new(60736.8125,23.7954559326,1396.33764648),CFrame.new(60859.6601562,23.7885627747,1328.19140625),CFrame.new(60626.4101562,25.2498073578,1142.828125)}},
        {LevelReq=400,Mob="Fishman Commando",Name="FishmanQuest",Tier=2,Boss=false,Quest=CFrame.new(61406.1953125,24.5187358856,1626.81640625),Spawns={CFrame.new(61992.640625,24.549861908,1205.73803711),CFrame.new(61887.75,24.5488853455,1232.44702148),CFrame.new(62013.03125,24.5533771515,1329.94506836),CFrame.new(61808.0976562,24.5535316467,1328.58178711),CFrame.new(61994.5546875,24.5499229431,1425.44897461),CFrame.new(61872.875,24.5667133331,1464.17944336)}},
        {LevelReq=425,Mob="Fishman Lord",Name="FishmanQuest",Tier=3,Boss=true,Quest=CFrame.new(61406.1953125,24.5187358856,1626.81640625),Spawns={CFrame.new(61352.9023438,67.1670074463,1029.11096191)}},
        {LevelReq=450,Mob="God's Guard",Name="SkyExp1Quest",Tier=1,Boss=false,Quest=CFrame.new(-4882.89404297,926.177490234,-1031.05480957),Spawns={CFrame.new(-4364.76416016,1090.17175293,-383.479156494),CFrame.new(-4227.25097656,1087.96362305,-567.608886719),CFrame.new(-4130.80273438,1090.30334473,-291.206054688),CFrame.new(-4403.32763672,1088.21569824,-498.130004883),CFrame.new(-4234.55615234,1089.33435059,-267.375946045),CFrame.new(-4082.85107422,1087.26672363,-414.136230469)}},
        {LevelReq=475,Mob="Shanda",Name="SkyExp1Quest",Tier=2,Boss=false,Quest=CFrame.new(-4882.89404297,926.177490234,-1031.05480957),Spawns={CFrame.new(-5890.41210938,5468.90478516,1956.18701172),CFrame.new(-5878.78808594,5470.43847656,1864.20336914),CFrame.new(-6040.20410156,5468.01318359,1734.20947266),CFrame.new(-5956.50146484,5470.09033203,1750.6015625),CFrame.new(-6026.83642578,5469.55273438,1851.04943848)}},
        {LevelReq=500,Mob="Wysper",Name="SkyExp1Quest",Tier=3,Boss=true,Quest=CFrame.new(-4882.89404297,926.177490234,-1031.05480957),Spawns={CFrame.new(-6271.55859375,5472.77636719,1887.77050781)}},
        {LevelReq=525,Mob="Royal Squad",Name="SkyExp2Quest",Tier=1,Boss=false,Quest=CFrame.new(-7033.10058594,5590.57421875,1353.10693359),Spawns={CFrame.new(-6706.87060547,5551.41357422,1155.43017578),CFrame.new(-6804.6875,5550.37402344,1083.56115723),CFrame.new(-6690.03955078,5551.41357422,1318.30541992),CFrame.new(-6868.93896484,5554.89013672,1319.95458984),CFrame.new(-6920.73339844,5551.41357422,1191.92456055)}},
        {LevelReq=550,Mob="Royal Soldier",Name="SkyExp2Quest",Tier=2,Boss=false,Quest=CFrame.new(-7033.10058594,5590.57421875,1353.10693359),Spawns={CFrame.new(-7175.83544922,5541.05029297,947.144042969),CFrame.new(-6932.08789062,5541.05029297,842.444519043),CFrame.new(-7137.42773438,5541.05029297,892.987121582),CFrame.new(-7138.48193359,5541.05029297,1050.77429199),CFrame.new(-6938.38427734,5541.05029297,963.78125)}},
        {LevelReq=575,Mob="Thunder God",Name="SkyExp2Quest",Tier=3,Boss=true,Quest=CFrame.new(-7033.10058594,5590.57421875,1353.10693359),Spawns={CFrame.new(-7125.41455078,5596.06298828,111.518699646)}},
        {LevelReq=625,Mob="Galley Pirate",Name="FountainQuest",Tier=1,Boss=false,Quest=CFrame.new(5263.48779297,74.907989502,4087.61572266),Spawns={CFrame.new(5452.890625,78.7009429932,4112.57714844),CFrame.new(5327.61376953,76.2442779541,4014.50537109),CFrame.new(5708.22167969,80.9136810303,3928.11865234),CFrame.new(5670.65283203,79.5116882324,4074.46337891),CFrame.new(5430.41992188,77.9910812378,3953.56689453),CFrame.new(5840.02587891,76.8320617676,3975.56347656)}},
        {LevelReq=650,Mob="Galley Captain",Name="FountainQuest",Tier=2,Boss=false,Quest=CFrame.new(5263.48779297,74.907989502,4087.61572266),Spawns={CFrame.new(5409.47851562,77.674331665,4686.9921875),CFrame.new(5782.203125,79.3242416382,4868.86425781),CFrame.new(5385.47460938,78.7068862915,4851.12109375),CFrame.new(5594.93359375,78.71144104,4751.86669922),CFrame.new(5685.41601562,77.6837005615,4742.5859375),CFrame.new(5899.57617188,76.5875778198,4809.02246094),CFrame.new(5544.03564453,76.8699951172,4899.09863281),CFrame.new(5773.7265625,77.6645431519,4703.10205078)}},
        {LevelReq=675,Mob="Cyborg",Name="FountainQuest",Tier=3,Boss=true,Quest=CFrame.new(5263.48779297,74.907989502,4087.61572266),Spawns={CFrame.new(6252.39160156,9.31876659393,4941.38867188)}},
    },
    [2]={
        {LevelReq=700,Mob="Raider",Name="Area1Quest",Tier=1,Boss=false,Quest=CFrame.new(-429.544006348,71.7700042725,1836.18200684),Spawns={CFrame.new(-917.437011719,40.0079956055,2250.43505859),CFrame.new(-612.437011719,40.0079956055,2557.43505859),CFrame.new(-607.437011719,40.0079956055,2202.43505859),CFrame.new(-904.336975098,40.0079956055,2501.43505859),CFrame.new(241.56300354,40.0079956055,2195.43505859),CFrame.new(549.562988281,40.0079956055,2190.43505859),CFrame.new(265.562988281,40.0079956055,2497.43505859),CFrame.new(475.562988281,40.0079956055,2433.43505859)}},
        {LevelReq=725,Mob="Mercenary",Name="Area1Quest",Tier=2,Boss=false,Quest=CFrame.new(-429.544006348,71.7700042725,1836.18200684),Spawns={CFrame.new(-986.775024414,72.8760070801,1088.44702148),CFrame.new(-924.684020996,72.8760070801,1788.12402344),CFrame.new(-913.765014648,72.8760070801,1574.15100098),CFrame.new(-1085.15100098,72.8760070801,1696.39404297),CFrame.new(-1135.94396973,72.8760070801,1248.32702637),CFrame.new(-1209.20495605,72.8760070801,1073.0369873)}},
        {LevelReq=750,Mob="Diamond",Name="Area1Quest",Tier=3,Boss=true,Quest=CFrame.new(-429.544006348,71.7700042725,1836.18200684),Spawns={CFrame.new(-1711.37097168,206.041000366,-97.0820007324)}},
        {LevelReq=775,Mob="Swan Pirate",Name="Area2Quest",Tier=1,Boss=false,Quest=CFrame.new(638.445007324,71.7700042725,918.236022949),Spawns={CFrame.new(823.611999512,72.8079986572,1162.22094727),CFrame.new(984.630004883,72.8079986572,1401.6829834),CFrame.new(827.799987793,72.8079986572,1326.89697266),CFrame.new(1066.99401855,72.8079986572,1080.91796875),CFrame.new(967.17401123,72.9680023193,1180.75598145),CFrame.new(1063.18896484,72.8079986572,1399.76293945)}},
        {LevelReq=800,Mob="Factory Staff",Name="Area2Quest",Tier=2,Boss=false,Quest=CFrame.new(638.445007324,71.7700042725,918.236022949),Spawns={CFrame.new(-105.88999939,72.8079986572,-670.24798584),CFrame.new(-426.890014648,72.8079986572,-367.24798584),CFrame.new(-93.8899993896,72.8079986572,-34.2279968262),CFrame.new(386.109985352,72.8079986572,91.7519989014),CFrame.new(936.109985352,72.8079986572,-71.2480010986),CFrame.new(692.109985352,72.8079986572,227.751998901)}},
        {LevelReq=850,Mob="Jeremy",Name="Area2Quest",Tier=3,Boss=true,Quest=CFrame.new(638.445007324,71.7700042725,918.236022949),Spawns={CFrame.new(2338.00195312,451.425994873,700.106994629)}},
        {LevelReq=875,Mob="Marine Lieutenant",Name="MarineQuest3",Tier=1,Boss=false,Quest=CFrame.new(-2440.79589844,71.7140045166,-3216.06811523),Spawns={CFrame.new(-2766.07006836,71.0140075684,-3144.74902344),CFrame.new(-2583.94506836,71.0140075684,-3039.61791992),CFrame.new(-3012.85205078,71.0140075684,-2921.83203125),CFrame.new(-3258.55004883,71.0140075684,-2990.86694336),CFrame.new(-2932.5,71.0140075684,-2604.09594727)}},
        {LevelReq=900,Mob="Marine Captain",Name="MarineQuest3",Tier=2,Boss=false,Quest=CFrame.new(-2440.79589844,71.7140045166,-3216.06811523),Spawns={CFrame.new(-1805.36401367,73.0140075684,-3313.32495117),CFrame.new(-2030.24804688,73.0140075684,-3477.63500977),CFrame.new(-2103.93408203,73.0140075684,-3259.30297852),CFrame.new(-1928.38903809,73.0140075684,-3119.58007812),CFrame.new(-1601.3170166,73.0140075684,-3315.32495117)}},
        {LevelReq=925,Mob="Orbitus",Name="MarineQuest3",Tier=3,Boss=true,Quest=CFrame.new(-2440.79589844,71.7140045166,-3216.06811523),Spawns={CFrame.new(-2138.48388672,75.9410095215,-4326.45507812)}},
        {LevelReq=950,Mob="Zombie",Name="ZombieQuest",Tier=1,Boss=false,Quest=CFrame.new(-5497.06201172,47.5919952393,-795.236999512),Spawns={CFrame.new(-5595.60009766,49.3079986572,-524.24798584),CFrame.new(-5766.64892578,47.5010070801,-824.661987305),CFrame.new(-5512.23193359,49.3079986572,-847.978027344),CFrame.new(-5856.58886719,70.3509979248,-739.049987793),CFrame.new(-5761.9921875,49.3079986572,-654.937988281),CFrame.new(-5614.95996094,49.3079986572,-938.468994141)}},
        {LevelReq=975,Mob="Vampire",Name="ZombieQuest",Tier=2,Boss=false,Quest=CFrame.new(-5497.06201172,47.5919952393,-795.236999512),Spawns={CFrame.new(-6277.26416016,9.00799560547,-1269.44897461),CFrame.new(-5776.55175781,9.00799560547,-1373.44995117),CFrame.new(-5952.99511719,9.00799560547,-1568.52905273),CFrame.new(-6132.39501953,9.00799560547,-1466.16894531),CFrame.new(-6039.68896484,9.00799560547,-1099.15905762)}},
        {LevelReq=1000,Mob="Snow Trooper",Name="SnowMountainQuest",Tier=1,Boss=false,Quest=CFrame.new(609.859008789,400.119995117,-5372.25878906),Spawns={CFrame.new(572.692993164,400.808013916,-5605.20703125),CFrame.new(716.62701416,400.808013916,-5706.44091797),CFrame.new(642.666015625,400.808013916,-5454.48876953),CFrame.new(484.345001221,400.808013916,-5472.41601562),CFrame.new(445.944000244,442.808013916,-5553.90576172),CFrame.new(430.402008057,400.808013916,-5069.09521484),CFrame.new(392.218994141,400.808013916,-5207.68505859)}},
        {LevelReq=1050,Mob="Winter Warrior",Name="SnowMountainQuest",Tier=2,Boss=false,Quest=CFrame.new(609.859008789,400.119995117,-5372.25878906),Spawns={CFrame.new(1205.45898438,428.808013916,-5397.35888672),CFrame.new(1226.30895996,428.808013916,-5215.97607422),CFrame.new(1142.43798828,428.808013916,-5043.05322266),CFrame.new(1446.27001953,428.808013916,-5369.21484375),CFrame.new(1043.30505371,428.808013916,-5049.78613281),CFrame.new(1371.87097168,428.808013916,-5194.703125)}},
        {LevelReq=1100,Mob="Lab Subordinate",Name="IceSideQuest",Tier=1,Boss=false,Quest=CFrame.new(-6231.27197266,80.9337692261,-4851.32080078),Spawns={CFrame.new(-5897.82177734,81.699836731,-4554.62402344),CFrame.new(-5998.328125,90.0252456665,-4386.52246094),CFrame.new(-5766.35302734,81.699836731,-4249.66992188),CFrame.new(-5623.33300781,81.699836731,-4444.16064453),CFrame.new(-5693.31298828,81.699836731,-4628.29589844)}},
        {LevelReq=1125,Mob="Horned Warrior",Name="IceSideQuest",Tier=2,Boss=false,Quest=CFrame.new(-6231.27197266,80.9337692261,-4851.32080078),Spawns={CFrame.new(-6182.00976562,29.2286148071,-5914.24609375),CFrame.new(-6445.95507812,31.0095653534,-5858.28808594),CFrame.new(-6539.96435547,29.2286148071,-5717.98291016),CFrame.new(-6421.203125,29.2286148071,-5591.42773438),CFrame.new(-6331.76513672,29.2286148071,-5778.94189453),CFrame.new(-6133.45117188,29.2286148071,-6049.02441406)}},
        {LevelReq=1150,Mob="Smoke Admiral",Name="IceSideQuest",Tier=3,Boss=true,Quest=CFrame.new(-6231.27197266,80.9337692261,-4851.32080078),Spawns={CFrame.new(-4857.35839844,233.677841187,-5583.24316406)}},
        {LevelReq=1175,Mob="Magma Ninja",Name="FireSideQuest",Tier=1,Boss=false,Quest=CFrame.new(-5403.36816406,28.2776184082,-5371.70019531),Spawns={CFrame.new(-5790.07568359,28.9154415131,-5393.24707031),CFrame.new(-5885.36865234,32.641620636,-5501.19726562),CFrame.new(-5845.98583984,50.2627563477,-5670.96972656),CFrame.new(-5811.14794922,30.0477333069,-5576.53662109),CFrame.new(-5711.41113281,47.4014968872,-5658.5234375),CFrame.new(-5657.26171875,34.2040710449,-5551.61328125)}},
        {LevelReq=1200,Mob="Lava Pirate",Name="FireSideQuest",Tier=2,Boss=false,Quest=CFrame.new(-5403.36816406,28.2776184082,-5371.70019531),Spawns={CFrame.new(-5005.52148438,28.023431778,-4916.07714844),CFrame.new(-5005.39355469,28.4878692627,-5025.07617188),CFrame.new(-5082.35009766,28.9050598145,-4796.31738281),CFrame.new(-5111.28271484,32.1717300415,-5115.875),CFrame.new(-5218.38916016,29.7756690979,-4999.94921875)}},
        {LevelReq=1250,Mob="Ship Deckhand",Name="ShipQuest1",Tier=1,Boss=false,Quest=CFrame.new(1040.55541992,124.943008423,32909.1054688),Spawns={CFrame.new(580.29901123,125.577011108,33124.25),CFrame.new(719.29901123,125.577011108,33032.109375),CFrame.new(1247.2989502,125.577011108,33218.109375),CFrame.new(1176.2989502,125.577011108,33119.109375),CFrame.new(1157.2989502,125.577011108,32930.109375),CFrame.new(1259.2989502,125.577011108,33032.109375),CFrame.new(580.29901123,125.577011108,32930.109375)}},
        {LevelReq=1275,Mob="Ship Engineer",Name="ShipQuest1",Tier=2,Boss=false,Quest=CFrame.new(1040.55541992,124.943008423,32909.1054688),Spawns={CFrame.new(834.79699707,43.6930084229,32720.9257812),CFrame.new(729.229980469,43.6930084229,32950.34375),CFrame.new(1088.25195312,43.6930084229,32890.09375),CFrame.new(1016.77801514,43.6930084229,33074.1328125),CFrame.new(1025.65698242,43.6930084229,32740.8554688),CFrame.new(815.62902832,43.6930084229,33111.3398438)}},
        {LevelReq=1300,Mob="Ship Steward",Name="ShipQuest2",Tier=1,Boss=false,Quest=CFrame.new(974.075927734,124.938667297,33253.6210938),Spawns={CFrame.new(1032.45800781,125.833999634,33512.3945312),CFrame.new(801.382995605,125.833999634,33505.1796875),CFrame.new(815.000976562,125.833999634,33376.203125),CFrame.new(986.882995605,125.833999634,33366.953125),CFrame.new(918.666992188,125.833999634,33506.5039062)}},
        {LevelReq=1325,Mob="Ship Officer",Name="ShipQuest2",Tier=2,Boss=false,Quest=CFrame.new(974.075927734,124.938667297,33253.6210938),Spawns={CFrame.new(505.528991699,179.906005859,33263.6328125),CFrame.new(694.528991699,179.906005859,33112.6328125),CFrame.new(657.528991699,179.906005859,33460.6328125),CFrame.new(1144.52905273,179.906005859,33112.6015625),CFrame.new(1320.52905273,179.906005859,33294.6015625),CFrame.new(1162.52905273,179.906005859,33445.6015625)}},
        {LevelReq=1350,Mob="Arctic Warrior",Name="FrostQuest",Tier=1,Boss=false,Quest=CFrame.new(5667.65820312,26.8000030518,-6486.08984375),Spawns={CFrame.new(6095.52587891,27.5599975586,-6077.94091797),CFrame.new(6271.31689453,27.5599975586,-6151.53808594),CFrame.new(5994.58886719,27.5599975586,-6324.27880859),CFrame.new(5832.19580078,27.5599975586,-6241.29003906),CFrame.new(6167.22216797,27.5599975586,-6319.22998047)}},
        {LevelReq=1375,Mob="Snow Lurker",Name="FrostQuest",Tier=2,Boss=false,Quest=CFrame.new(5667.65820312,26.8000030518,-6486.08984375),Spawns={CFrame.new(5763.84619141,27.5599975586,-6671.04589844),CFrame.new(5443.421875,27.5599975586,-7031.28515625),CFrame.new(5567.85693359,27.5599975586,-6900.46484375),CFrame.new(5484.41796875,27.5599975586,-6733.75),CFrame.new(5524.15722656,27.5599975586,-6583.82080078)}},
        {LevelReq=1400,Mob="Awakened Ice Admiral",Name="FrostQuest",Tier=3,Boss=true,Quest=CFrame.new(5667.65820312,26.8000030518,-6486.08984375),Spawns={CFrame.new(6551.79394531,325.295013428,-6989.89892578)}},
        {LevelReq=1425,Mob="Sea Soldier",Name="ForgottenQuest",Tier=1,Boss=false,Quest=CFrame.new(-3054.44506836,238.343994141,-10142.8193359),Spawns={CFrame.new(-2550.92211914,28.4530029297,-9839.99707031),CFrame.new(-2840.09204102,27.4530029297,-9814.38085938),CFrame.new(-3499.34790039,16.0859985352,-9712.00585938),CFrame.new(-3293.05004883,5.90899658203,-9640.93164062),CFrame.new(-3459.69189453,25.6289978027,-9934.77246094),CFrame.new(-3240.33105469,27.4530029297,-9813.96582031)}},
        {LevelReq=1450,Mob="Water Fighter",Name="ForgottenQuest",Tier=2,Boss=false,Quest=CFrame.new(-3054.44506836,238.343994141,-10142.8193359),Spawns={CFrame.new(-3331.70507812,239.138000488,-10553.3564453),CFrame.new(-3511.95898438,239.138000488,-10346.9287109),CFrame.new(-3396.35888672,239.138000488,-10745.1054688),CFrame.new(-3316.75390625,239.138000488,-10323.1689453),CFrame.new(-3657.94995117,239.138000488,-10591.1474609)}},
        {LevelReq=1475,Mob="Tide Keeper",Name="ForgottenQuest",Tier=3,Boss=true,Quest=CFrame.new(-3054.44506836,238.343994141,-10142.8193359),Spawns={CFrame.new(-3760.41601562,78.3379974365,-11585.7041016)}},
    },
    [3]={
        {LevelReq=1500,Mob="Pirate Millionaire",Name="PiratePortQuest",Tier=1,Boss=false,Quest=CFrame.new(-450.105010986,107.680999756,5950.72607422),Spawns={CFrame.new(-593.177001953,55.4869995117,5511.45703125),CFrame.new(-543.814025879,56.6920013428,5653.96923828),CFrame.new(-751.570007324,55.4819946289,5637.53320312),CFrame.new(-62.6029968262,55.4869995117,5803.47119141),CFrame.new(-232.919998169,57.0429992676,5757.83300781),CFrame.new(-118.809005737,55.4869995117,5649.16992188)}},
        {LevelReq=1525,Mob="Pistol Billionaire",Name="PiratePortQuest",Tier=2,Boss=false,Quest=CFrame.new(-450.105010986,107.680999756,5950.72607422),Spawns={CFrame.new(-852.890991211,69.9970092773,6175.29589844),CFrame.new(-739.53302002,84.6340026855,5833.05712891),CFrame.new(-666.770996094,84.9440002441,6008.33789062),CFrame.new(-903.169006348,84.6340026855,5891.01123047),CFrame.new(-185.692993164,84.7089996338,6103.62695312),CFrame.new(-188.143005371,84.7089996338,6337.04101562),CFrame.new(-54.8110046387,83.7700042725,5947.84082031),CFrame.new(40.0599975586,85.2720031738,6114.29785156)}},
        {LevelReq=1550,Mob="Stone",Name="PiratePortQuest",Tier=3,Boss=true,Quest=CFrame.new(-450.105010986,107.680999756,5950.72607422),Spawns={CFrame.new(-1109.92602539,53.3789978027,6811.72509766)}},
        {LevelReq=1575,Mob="Dragon Crew Warrior",Name="DragonCrewQuest",Tier=1,Boss=false,Quest=CFrame.new(6735.11083984,126.990005493,-711.098022461),Spawns={CFrame.new(6709.76416016,52.3440093994,-1139.0300293),CFrame.new(7217.78710938,56.5700073242,-680.75),CFrame.new(6473.1640625,52.3440093994,-1231.7779541),CFrame.new(6919.08007812,57.7310028076,-940.838989258),CFrame.new(6615.23193359,52.3440093994,-978.935974121),CFrame.new(6998.79492188,53.7310028076,-519.408996582)}},
        {LevelReq=1600,Mob="Dragon Crew Archer",Name="DragonCrewQuest",Tier=2,Boss=false,Quest=CFrame.new(6735.11083984,126.990005493,-711.098022461),Spawns={CFrame.new(6582.80517578,521.322998047,505.264007568),CFrame.new(6668.76220703,481.37701416,329.122009277),CFrame.new(6948.45800781,482.878997803,185.022994995),CFrame.new(6762.49707031,481.37701416,110.770004272),CFrame.new(6818.58886719,482.878997803,512.726989746)}},
        {LevelReq=1625,Mob="Hydra Enforcer",Name="VenomCrewQuest",Tier=1,Boss=false,Quest=CFrame.new(5214.33886719,1003.46801758,759.507019043),Spawns={CFrame.new(4462.65283203,1005.10198975,551.005981445),CFrame.new(4581.51904297,1003.15197754,704.937011719),CFrame.new(4434.08007812,1005.65301514,209.520996094),CFrame.new(4671.68896484,1004.33398438,-14.5670013428),CFrame.new(4547.11523438,1003.10198975,334.195007324),CFrame.new(4456.42285156,1008.45300293,418.837005615)}},
        {LevelReq=1650,Mob="Venomous Assailant",Name="VenomCrewQuest",Tier=2,Boss=false,Quest=CFrame.new(5214.33886719,1003.46801758,759.507019043),Spawns={CFrame.new(4448.78320312,1222.02197266,540.538024902),CFrame.new(4879.91992188,1093.68896484,1104.00805664),CFrame.new(4443.046875,1237.02404785,335.859985352),CFrame.new(4637.88378906,1078.78601074,882.41998291),CFrame.new(4674.92675781,1134.82702637,996.309020996),CFrame.new(4452.81689453,1220.82104492,698.911987305)}},
        {LevelReq=1675,Mob="Hydra Leader",Name="VenomCrewQuest",Tier=3,Boss=true,Quest=CFrame.new(5214.33886719,1003.46801758,759.507019043),Spawns={CFrame.new(5888.77392578,1020.14898682,-117.815002441)}},
        {LevelReq=1700,Mob="Marine Commodore",Name="MarineTreeIsland",Tier=1,Boss=false,Quest=CFrame.new(2485.73291016,73.3460083008,-6788.625),Spawns={CFrame.new(2577.25390625,75.6100006104,-7739.87207031),CFrame.new(2995.37988281,75.6100006104,-8054.45703125),CFrame.new(2367.90795898,75.6100006104,-7794.95605469),CFrame.new(2685.39990234,75.6100006104,-8066.04980469),CFrame.new(3222.41699219,75.6100006104,-7820.55712891),CFrame.new(2497.77490234,81.8470001221,-7356.93896484)}},
        {LevelReq=1725,Mob="Marine Rear Admiral",Name="MarineTreeIsland",Tier=2,Boss=false,Quest=CFrame.new(2485.73291016,73.3460083008,-6788.625),Spawns={CFrame.new(3920.06103516,146.225997925,-7175.20605469),CFrame.new(3973.73803711,123.912002563,-6931.93701172),CFrame.new(3465.18408203,123.912002563,-7181.78417969),CFrame.new(3761.81005859,123.912002563,-6823.52197266),CFrame.new(3753.50292969,123.912002563,-7403.22021484)}},
        {LevelReq=1750,Mob="Kilo Admiral",Name="MarineTreeIsland",Tier=3,Boss=true,Quest=CFrame.new(2485.73291016,73.3460083008,-6788.625),Spawns={CFrame.new(2998.29492188,508.794006348,-7344.32177734)}},
        {LevelReq=1775,Mob="Fishman Raider",Name="DeepForestIsland3",Tier=1,Boss=false,Quest=CFrame.new(-10581.65625,330.87298584,-8761.18652344),Spawns={CFrame.new(-10523.7558594,332.602996826,-8597.58886719),CFrame.new(-10117.9472656,332.602996826,-8174.68603516),CFrame.new(-10223.1142578,332.602996826,-8482.54589844),CFrame.new(-10391.7382812,332.602996826,-8212.27636719),CFrame.new(-10853.8564453,332.602996826,-8425.24023438),CFrame.new(-10603.6445312,332.602996826,-8309.12597656)}},
        {LevelReq=1800,Mob="Fishman Captain",Name="DeepForestIsland3",Tier=2,Boss=false,Quest=CFrame.new(-10581.65625,330.87298584,-8761.18652344),Spawns={CFrame.new(-11210.2685547,331.82598877,-9072.71191406),CFrame.new(-10828.1064453,331.82598877,-9049.14648438),CFrame.new(-10736.6728516,331.82598877,-8807.57910156),CFrame.new(-11107.8535156,331.82598877,-8842.91601562),CFrame.new(-11072.5996094,331.82598877,-8610.07226562),CFrame.new(-11135.2001953,331.82598877,-9240.88671875)}},
        {LevelReq=1825,Mob="Forest Pirate",Name="DeepForestIsland",Tier=1,Boss=false,Quest=CFrame.new(-13234.0400391,331.488006592,-7625.40087891),Spawns={CFrame.new(-13345.5419922,332.226013184,-7630.7578125),CFrame.new(-13651.5429688,332.226013184,-7894.7578125),CFrame.new(-13600.5429688,332.226013184,-7741.7578125),CFrame.new(-13105.5429688,332.226013184,-7705.75683594),CFrame.new(-13513.5429688,332.226013184,-8008.7578125),CFrame.new(-13279.5429688,332.226013184,-7897.7578125)}},
        {LevelReq=1850,Mob="Mythological Pirate",Name="DeepForestIsland",Tier=2,Boss=false,Quest=CFrame.new(-13234.0400391,331.488006592,-7625.40087891),Spawns={CFrame.new(-13732.0478516,469.433013916,-6826.96484375),CFrame.new(-13456.0498047,469.433013916,-7039.96386719),CFrame.new(-13876.0478516,469.433013916,-7009.96484375),CFrame.new(-13221.0302734,519.103027344,-6902.01806641),CFrame.new(-13221.03125,519.103027344,-6689.01611328),CFrame.new(-13320.0302734,519.103027344,-6785.01806641)}},
        {LevelReq=1875,Mob="Captain Elephant",Name="DeepForestIsland",Tier=3,Boss=true,Quest=CFrame.new(-13234.0400391,331.488006592,-7625.40087891),Spawns={CFrame.new(-13365.5292969,321.230987549,-8484.99023438)}},
        {LevelReq=1900,Mob="Jungle Pirate",Name="DeepForestIsland2",Tier=1,Boss=false,Quest=CFrame.new(-12680.3818359,389.971008301,-9902.01953125),Spawns={CFrame.new(-11902.2734375,331.291992188,-10432.0673828),CFrame.new(-12142.4589844,331.602996826,-10419.9111328),CFrame.new(-11708.4316406,331.875,-10700.0517578),CFrame.new(-11918.1035156,332.518005371,-10744.0898438),CFrame.new(-11612.4667969,335.821990967,-10489.4091797),CFrame.new(-12321.3115234,331.437011719,-10669.2548828),CFrame.new(-12306.3486328,331.071990967,-10352.8779297)}},
        {LevelReq=1925,Mob="Musketeer Pirate",Name="DeepForestIsland2",Tier=2,Boss=false,Quest=CFrame.new(-12680.3818359,389.971008301,-9902.01953125),Spawns={CFrame.new(-13556.078125,391.394012451,-9735.94433594),CFrame.new(-13198.6435547,391.394012451,-9602.29589844),CFrame.new(-13075.6435547,391.394012451,-9890.29589844),CFrame.new(-13270.8818359,472.062011719,-9860.66113281),CFrame.new(-13337.8818359,472.062011719,-9698.66113281),CFrame.new(-13417.6435547,391.394012451,-9962.29589844),CFrame.new(-13514.8681641,403.403991699,-9866.51953125)}},
        {LevelReq=1950,Mob="Beautiful Pirate",Name="DeepForestIsland2",Tier=3,Boss=true,Quest=CFrame.new(-12680.3818359,389.971008301,-9902.01953125),Spawns={CFrame.new(5367.31396484,26.3950042725,-64.7010040283)}},
        {LevelReq=1975,Mob="Reborn Skeleton",Name="HauntedQuest1",Tier=1,Boss=false,Quest=CFrame.new(-9479.21679688,141.214996338,5566.09277344),Spawns={CFrame.new(-8762.65722656,141.611999512,6183.33984375),CFrame.new(-8710.1015625,140.95300293,6112.93017578),CFrame.new(-8682.1015625,140.95300293,5968.93017578),CFrame.new(-8868.1015625,140.95300293,6034.93017578),CFrame.new(-8646.1015625,140.95300293,5850.93017578),CFrame.new(-8826.1015625,140.95300293,6165.93017578),CFrame.new(-8811.56542969,143.104995728,5871.75292969)}},
        {LevelReq=2000,Mob="Living Zombie",Name="HauntedQuest1",Tier=2,Boss=false,Quest=CFrame.new(-9479.21679688,141.214996338,5566.09277344),Spawns={CFrame.new(-10184.1015625,152.95300293,5741.93017578),CFrame.new(-10293.1015625,152.95300293,5960.93017578),CFrame.new(-10170.9023438,141.175003052,6159.62695312),CFrame.new(-10061.9023438,140.175003052,6038.62695312),CFrame.new(-10205.1015625,151.95300293,5861.93017578),CFrame.new(-9956.1015625,140.95300293,5966.93017578)}},
        {LevelReq=2025,Mob="Demonic Soul",Name="HauntedQuest2",Tier=1,Boss=false,Quest=CFrame.new(-9516.99316406,172.016998291,6078.46484375),Spawns={CFrame.new(-9565.95605469,171.95300293,6235.40820312),CFrame.new(-9344.95605469,171.95300293,6201.40820312),CFrame.new(-9631.95605469,171.95300293,6053.40820312),CFrame.new(-9426.95605469,171.95300293,6048.40820312),CFrame.new(-9253.95605469,171.95300293,6050.40820312),CFrame.new(-9753.95605469,171.95300293,6166.40820312)}},
        {LevelReq=2050,Mob="Posessed Mummy",Name="HauntedQuest2",Tier=2,Boss=false,Quest=CFrame.new(-9516.99316406,172.016998291,6078.46484375),Spawns={CFrame.new(-9609.3515625,5.95300292969,6361.97412109),CFrame.new(-9759.3515625,26.9530029297,6051.97412109),CFrame.new(-9449.3515625,5.95300292969,6342.97412109),CFrame.new(-9759.3515625,26.9530029297,6368.97412109),CFrame.new(-9399.64746094,12.1979980469,6118.81103516)}},
        {LevelReq=2075,Mob="Peanut Scout",Name="NutsIslandQuest",Tier=1,Boss=false,Quest=CFrame.new(-2105.53198242,37.25,-10195.5087891),Spawns={CFrame.new(-2078.09106445,12.8549957275,-9997.10351562),CFrame.new(-1865.42700195,8.85499572754,-10086.2324219),CFrame.new(-2065.34790039,34.9519958496,-10066.8105469),CFrame.new(-1924.00097656,37.2720031738,-10199.6630859),CFrame.new(-2294.24804688,37.2369995117,-10176.1210938),CFrame.new(-2250.19091797,8.85499572754,-9948.83886719),CFrame.new(-2377.28295898,37.9519958496,-10308.21875)}},
        {LevelReq=2100,Mob="Peanut President",Name="NutsIslandQuest",Tier=2,Boss=false,Quest=CFrame.new(-2105.53198242,37.25,-10195.5087891),Spawns={CFrame.new(-2311.98706055,87.3229980469,-10609.3427734),CFrame.new(-1874.36206055,37.2220001221,-10596.5761719),CFrame.new(-1996.06994629,37.2220001221,-10496.9267578),CFrame.new(-2247.47607422,87.3229980469,-10440.8681641),CFrame.new(-2395.12402344,87.3760070801,-10456.3066406),CFrame.new(-1993.40600586,37.2220001221,-10682.9052734)}},
        {LevelReq=2125,Mob="Ice Cream Chef",Name="IceCreamIslandQuest",Tier=1,Boss=false,Quest=CFrame.new(-819.37701416,64.9260101318,-10967.2832031),Spawns={CFrame.new(-966.289001465,64.5590057373,-10973.5576172),CFrame.new(-1109.2869873,64.5590057373,-10931.265625),CFrame.new(-931.744995117,64.5590057373,-11146.7304688),CFrame.new(-797.031005859,64.5590057373,-10790.7246094),CFrame.new(-715.434020996,64.5590057373,-10920.4355469),CFrame.new(-502.410003662,64.5590057373,-10873.7949219)}},
        {LevelReq=2150,Mob="Ice Cream Commander",Name="IceCreamIslandQuest",Tier=2,Boss=false,Quest=CFrame.new(-819.37701416,64.9260101318,-10967.2832031),Spawns={CFrame.new(-366.812988281,64.6529998779,-11094.4228516),CFrame.new(-657.549987793,129.740997314,-11215.7919922),CFrame.new(-528.749023438,65.4790039062,-11348.9228516),CFrame.new(-883.630004883,70.1410064697,-11485.5253906),CFrame.new(-770.414978027,125.61100769,-11159.8408203),CFrame.new(-675.096984863,67.6670074463,-11371.7246094)}},
        {LevelReq=2175,Mob="Cake Queen",Name="IceCreamIslandQuest",Tier=3,Boss=true,Quest=CFrame.new(-819.37701416,64.9260101318,-10967.2832031),Spawns={CFrame.new(-678.478027344,381.856994629,-11114.3457031)}},
        {LevelReq=2200,Mob="Cookie Crafter",Name="CakeQuest1",Tier=1,Boss=false,Quest=CFrame.new(-2022.2989502,36.9280090332,-12030.9765625),Spawns={CFrame.new(-2321.71191406,37.0050048828,-12216.7841797),CFrame.new(-2499.16894531,37.0050048828,-12165.0185547),CFrame.new(-2464.47705078,37.0050048828,-12049.9326172),CFrame.new(-2342.87304688,37.0050048828,-12009.2382812),CFrame.new(-2212.88989258,37.0050048828,-11969.2568359),CFrame.new(-2423.39892578,37.0050048828,-12265.7666016),CFrame.new(-2246.37402344,37.0050048828,-12126.9414062)}},
        {LevelReq=2225,Mob="Cake Guard",Name="CakeQuest1",Tier=2,Boss=false,Quest=CFrame.new(-2022.2989502,36.9280090332,-12030.9765625),Spawns={CFrame.new(-1531.41101074,35.2190093994,-12132.4394531),CFrame.new(-1693.97998047,35.2190093994,-12436.84375),CFrame.new(-1736.54394531,35.2190093994,-12249.0605469),CFrame.new(-1471.12805176,35.2190093994,-12436.84375),CFrame.new(-1418.51098633,35.2190093994,-12255.71875)}},
        {LevelReq=2250,Mob="Baking Staff",Name="CakeQuest2",Tier=1,Boss=false,Quest=CFrame.new(-1928.31799316,37.7299957275,-12840.6259766),Spawns={CFrame.new(-1720.85095215,34.6650085449,-13087.125),CFrame.new(-1828.80102539,34.6650085449,-12699.4384766),CFrame.new(-1980.43701172,34.6650085449,-12983.8408203),CFrame.new(-1774.07800293,34.6650085449,-12850.4521484),CFrame.new(-1847.17797852,34.6650085449,-13132.5039062),CFrame.new(-1759.28601074,34.6650085449,-12994.8398438)}},
        {LevelReq=2275,Mob="Head Baker",Name="CakeQuest2",Tier=2,Boss=false,Quest=CFrame.new(-1928.31799316,37.7299957275,-12840.6259766),Spawns={CFrame.new(-2263.35400391,51.0099945068,-12711.3916016),CFrame.new(-2251.57592773,51.0099945068,-13033.3974609),CFrame.new(-2389.22900391,51.0099945068,-13018.3349609),CFrame.new(-2369.09008789,51.0099945068,-12807.921875),CFrame.new(-2151.37792969,51.0099945068,-13033.3974609),CFrame.new(-2100.70507812,51.0099945068,-12720.9658203)}},
        {LevelReq=2300,Mob="Cocoa Warrior",Name="ChocQuest1",Tier=1,Boss=false,Quest=CFrame.new(231.75,23.8999938965,-12200.2919922),Spawns={CFrame.new(6.33200073242,26.2250061035,-12305.2089844),CFrame.new(-125.007003784,26.2250061035,-12345.8085938),CFrame.new(167.979003906,26.2250061035,-12238.8740234),CFrame.new(-128.669998169,26.2250061035,-12249.8134766),CFrame.new(34.8440093994,26.2250061035,-12169.6630859)}},
        {LevelReq=2325,Mob="Chocolate Bar Battler",Name="ChocQuest1",Tier=2,Boss=false,Quest=CFrame.new(231.75,23.8999938965,-12200.2919922),Spawns={CFrame.new(717.515014648,25.5820007324,-12557.6708984),CFrame.new(582.828979492,25.5820007324,-12550.7041016),CFrame.new(701.312011719,25.5820007324,-12708.2148438),CFrame.new(598.833007812,25.5820007324,-12395.1210938),CFrame.new(833.197998047,25.5820007324,-12671.4042969),CFrame.new(806.958984375,25.5820007324,-12773.078125)}},
        {LevelReq=2350,Mob="Sweet Thief",Name="ChocQuest2",Tier=1,Boss=false,Quest=CFrame.new(151.197998047,23.8910064697,-12774.6171875),Spawns={CFrame.new(-140.257995605,25.5820007324,-12652.3115234),CFrame.new(5.36599731445,25.5820007324,-12537.4257812),CFrame.new(88.4720001221,25.5820007324,-12662.2070312),CFrame.new(-77.6470031738,25.5820007324,-12765.6201172),CFrame.new(143.970001221,25.5820007324,-12531.7207031)}},
        {LevelReq=2375,Mob="Candy Rebel",Name="ChocQuest2",Tier=2,Boss=false,Quest=CFrame.new(151.197998047,23.8910064697,-12774.6171875),Spawns={CFrame.new(166.820007324,25.5820007324,-13035.3457031),CFrame.new(47.9230041504,25.5820007324,-13029.2402344),CFrame.new(220.378005981,26.5820007324,-12913.9658203),CFrame.new(-72.1289978027,25.5820007324,-12940.3242188),CFrame.new(52.9980010986,26.5820007324,-12851.6757812)}},
        {LevelReq=2400,Mob="Candy Pirate",Name="CandyQuest1",Tier=1,Boss=false,Quest=CFrame.new(-1164.49804688,59.2689971924,-14492.6181641),Spawns={CFrame.new(-1378.65698242,38.0240020752,-14802.8837891),CFrame.new(-1428.1529541,36.4069976807,-14637.8964844),CFrame.new(-1332.67504883,24.3430023193,-14327.3603516),CFrame.new(-1255.7989502,33.4669952393,-14507.0966797),CFrame.new(-1226.7869873,36.300994873,-14777.5878906),CFrame.new(-1440.3260498,32.4929962158,-14435.9345703)}},
        {LevelReq=2425,Mob="Snow Demon",Name="CandyQuest1",Tier=2,Boss=false,Quest=CFrame.new(-1164.49804688,59.2689971924,-14492.6181641),Spawns={CFrame.new(-784.67199707,24.8099975586,-14631.7851562),CFrame.new(-771.226013184,14.2239990234,-14434.3037109),CFrame.new(-936.151977539,13.9960021973,-14552.4980469),CFrame.new(-813.560974121,15.3430023193,-14322.7148438),CFrame.new(-897.773010254,24.5939941406,-14733.7714844)}},
        {LevelReq=2450,Mob="Isle Outlaw",Name="TikiQuest1",Tier=1,Boss=false,Quest=CFrame.new(-16548.8164062,55.6060028076,-172.81199646),Spawns={CFrame.new(-16433.71875,57.2210083008,-195.473007202),CFrame.new(-16351.7773438,23.4940032959,-282.45401001),CFrame.new(-16122.4052734,11.779006958,-257.354003906),CFrame.new(-16289.4882812,22.8740081787,-179.444000244),CFrame.new(-16163.4248047,11.9450073242,-99.3600006104)}},
        {LevelReq=2475,Mob="Island Boy",Name="TikiQuest1",Tier=2,Boss=false,Quest=CFrame.new(-16548.8164062,55.6060028076,-172.81199646),Spawns={CFrame.new(-16991.7304688,12.766998291,-186.182998657),CFrame.new(-16736.21875,22.171005249,-131.720993042),CFrame.new(-16905.3046875,13.0939941406,-73.5070037842),CFrame.new(-16883.0488281,23.3470001221,-250.87399292),CFrame.new(-16661.5742188,57.3720092773,-252.962997437)}},
        {LevelReq=2500,Mob="Sun-kissed Warrior",Name="TikiQuest2",Tier=1,Boss=false,Quest=CFrame.new(-16541.0214844,54.7709960938,1051.46105957),Spawns={CFrame.new(-16153.3652344,14.4649963379,942.447998047),CFrame.new(-16186.4208984,25.1040039062,1098.08300781),CFrame.new(-16413.5078125,56.7109985352,1054.43603516),CFrame.new(-16052.4560547,9.81799316406,1061.91296387),CFrame.new(-16357.3134766,21.0189971924,1005.65100098)}},
        {LevelReq=2525,Mob="Isle Champion",Name="TikiQuest2",Tier=2,Boss=false,Quest=CFrame.new(-16541.0214844,54.7709960938,1051.46105957),Spawns={CFrame.new(-16940.7988281,14.1929931641,1070.8659668),CFrame.new(-16901.2304688,12.4510040283,969.968994141),CFrame.new(-16735.6757812,23.3460083008,1110.58496094),CFrame.new(-16618.7460938,58.3780059814,1099.5090332),CFrame.new(-16787.3203125,25.2050018311,992.132019043)}},
        {LevelReq=2550,Mob="Serpent Hunter",Name="TikiQuest3",Tier=1,Boss=false,Quest=CFrame.new(-16665.1914062,104.596008301,1579.69396973),Spawns={CFrame.new(-16521.0625,106.093002319,1488.78503418),CFrame.new(-16599.7070312,71.0899963379,1757.91296387),CFrame.new(-16442.8261719,71.637008667,1693.44604492),CFrame.new(-16536.0253906,106.870010376,1347.14001465),CFrame.new(-16621.4199219,121.908004761,1290.68994141)}},
        {LevelReq=2575,Mob="Skull Slayer",Name="TikiQuest3",Tier=2,Boss=false,Quest=CFrame.new(-16665.1914062,104.596008301,1579.69396973),Spawns={CFrame.new(-16855.0429688,122.457000732,1478.1529541),CFrame.new(-16812.8828125,72.1430053711,1757.16601562),CFrame.new(-16829.421875,193.199996948,1753.42199707),CFrame.new(-16948.578125,193.132003784,1643.61303711),CFrame.new(-16811.5625,86.125,1542.22900391),CFrame.new(-16985.7265625,59.2689971924,1632.82202148)}},
        {LevelReq=2600,Mob="Reef Bandit",Name="SubmergedQuest1",Tier=1,Boss=false,Quest=CFrame.new(10780.6396484,-2088.4140625,9260.453125),Spawns={CFrame.new(10899.859375,-2145.23486328,9279.29394531),CFrame.new(11039.6269531,-2156.10327148,9279.11230469),CFrame.new(11085.1894531,-2160.54052734,9129.76367188),CFrame.new(10883.5478516,-2160.20458984,9075.48339844),CFrame.new(10980.5322266,-2160.41455078,9051.94921875)}},
        {LevelReq=2625,Mob="Coral Pirate",Name="SubmergedQuest1",Tier=2,Boss=false,Quest=CFrame.new(10780.6396484,-2088.4140625,9260.453125),Spawns={CFrame.new(10703.7099609,-2087.29663086,9255.38183594),CFrame.new(10646.8447266,-2087.30175781,9304.16894531),CFrame.new(10839.4765625,-2087.29907227,9486.078125),CFrame.new(10733.1787109,-2087.29711914,9411.109375),CFrame.new(10824.5439453,-2087.29467773,9357.23144531)}},
        {LevelReq=2650,Mob="Sea Chanter",Name="SubmergedQuest2",Tier=1,Boss=false,Quest=CFrame.new(10883.5986328,-2086.88891602,10034.0195312),Spawns={CFrame.new(10625.5058594,-2087.37304688,10191.6953125),CFrame.new(10786.3867188,-2087.37304688,10105.2617188),CFrame.new(10680.0761719,-2056.67480469,9933.88964844),CFrame.new(10581.5078125,-2071.7487793,10020.6503906),CFrame.new(10466.3046875,-2087.37304688,10106.8476562)}},
        {LevelReq=2675,Mob="High Disciple",Name="SubmergedQuest3",Tier=1,Boss=false,Quest=CFrame.new(9637.29394531,-1993.13513184,9616.30175781),Spawns={CFrame.new(9854.43554688,-1995.0880127,9963.9375),CFrame.new(9835.43554688,-1995.0880127,9533.9375),CFrame.new(9778.43554688,-1995.0880127,9876.9375),CFrame.new(9778.43554688,-1995.0880127,9720.9375),CFrame.new(9886.43554688,-1995.0880127,9629.9375)}},
        {LevelReq=2675,Mob="Ocean Prophet",Name="SubmergedQuest2",Tier=2,Boss=false,Quest=CFrame.new(9637.29394531,-1993.13513184,9616.30175781),Spawns={CFrame.new(10861.9707031,-2006.61682129,10245.2148438),CFrame.new(10924.234375,-1998.92248535,10121.0537109),CFrame.new(11003.3261719,-2007.02575684,10225.0625),CFrame.new(11111.5507812,-2007.3404541,10201.5078125),CFrame.new(11129.7890625,-2007.7989502,10051.4726562)}},
        {LevelReq=2700,Mob="Grand Devotee",Name="SubmergedQuest3",Tier=2,Boss=false,Quest=CFrame.new(9637.29394531,-1993.13513184,9616.30175781),Spawns={CFrame.new(9620.51171875,-1994.39746094,9871.70898438),CFrame.new(9608.92773438,-1994.39758301,9956.375),CFrame.new(9719.8828125,-1989.86169434,10134.2207031),CFrame.new(9561.1796875,-1989.8638916,10090.4003906),CFrame.new(9559.19433594,-1994.39746094,9798.66503906),CFrame.new(9589.19726562,-1994.19165039,9704.75976562)}},
    },
}

    local function rows() return preloadRows[seaIndex()] or {} end
    local function nearestPoint(points)
        local _,_,root=character()
        local best,metric=nil,math.huge
        for _,point in ipairs(points) do
            local d=root and (root.Position-point.Position).Magnitude or 0
            if d<metric then best,metric=point,d end
        end
        return best
    end
    local function match(q)
        for _,row in ipairs(rows()) do
            if row.Name==q.Name and cleanName(row.Mob)==cleanName(q.Mob)
                and (q.Tier==nil or tostring(row.Tier)==tostring(q.Tier)) then return row end
        end
    end
    local function complement(q)
        if not q then return nil end
        local row=match(q)
        if not row then return q end
        q=table.clone(q)
        q.Spawn=q.Spawn or nearestPoint(row.Spawns)
        if not q.Quest and row.Quest then
            q.Quest=row.Quest;q.Tier=q.Tier or row.Tier
            q.Source=(q.Source or "quest_event").."+hoho_position"
        end
        return q
    end
    local function bestQuest()
        local value=path(LocalPlayer,"Data","Level")
        local level=value and tonumber(value.Value)
        if not level or level>2700 then return nil end
        local best
        for _,row in ipairs(rows()) do
            if not row.Boss and row.Name~="MarineQuest" and row.Name~="BartiloQuest" and row.LevelReq<=level and row.Quest then
                if not best or row.LevelReq>best.LevelReq then best=row end
            end
        end
        if not best then return nil end
        return {Name=best.Name,Tier=best.Tier,Mob=best.Mob,Quest=best.Quest,Spawn=nearestPoint(best.Spawns),LevelReq=best.LevelReq,Source="hoho_preload"}
    end
    local function spawn(mob)
        local points={}
        for _,row in ipairs(rows()) do
            if cleanName(row.Mob)==cleanName(mob) then
                for _,point in ipairs(row.Spawns) do points[#points+1]=point end
            end
        end
        return nearestPoint(points)
    end
    return {BestQuest=bestQuest,Complement=complement,Spawn=spawn,GetState=function()
        local data=rows();local bosses,points=0,0
        for _,r in ipairs(data) do if r.Boss then bosses=bosses+1 end;points=points+#r.Spawns end
        return {Source="HohoV2/preload",Sea=seaIndex(),Rows=#data,Bosses=bosses,Spawns=points,MaxLevel=2700}
    end}
end
local preload=initPreload()

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
        if seaIndex()==1 then level=math.min(level,699)
        elseif seaIndex()==2 then level=math.min(level,1499) end
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
    onJobStop.Farm=function() releaseInput();attackState.Phase="idle";fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil;farmProgress("idle") end
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
        if not best then best=preload.Spawn(mob);if best then source="hoho_preload" end end
        return best,source
    end
    local function levelQuest(visible)
        local current=visible and questRuntime.GetActiveQuest() or nil
        local q=current or (visible and farmQuest) or questRuntime.GetBestQuest()
        local legacy=questForLevel()
        if not q then
            if legacy then legacy.Source="legacy_data" end
            q=legacy or preload.BestQuest()
        end
        if not q then return nil end
        q=preload.Complement(q)
        -- Use old coordinates only if they identify the exact same mission/mob/stage.
        if legacy and legacy.Name==q.Name and cleanName(legacy.Mob)==cleanName(q.Mob)
            and (q.Tier==nil or tostring(legacy.Tier)==tostring(q.Tier)) then
            q.Tier=q.Tier or legacy.Tier
            q.Spawn=q.Spawn or legacy.Spawn
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
            if mode=="Level" then q=levelQuest(visible) else q=preload.Complement(farmQuest or bossForName(options.Boss)) end
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
    addLabel(Farm,"Um modo de farm por vez. Coordenadas/missões vêm das fontes; progresso e dano dependem do servidor. Missões consultadas no jogo; catálogo alternativo Hoho até nível 2700 (cobertura parcial).")
    local farmControl
    speedSlider(Farm)
    addToggle(Farm,"Manter posição fixa no farm",true,function(on)
        options.FixedFarm=on
        fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil
        stopMove("Farm")
    end)
    addLabel(Farm,"Velocidade do Tween: menor = mais lento. O ajuste também vale durante o deslocamento.")
    dropdown(Farm,"Ataque do farm",{"Auto","Matsune Click","Hoho R2","Tool"},"Auto",function(v) attackState.Method=v end)
    addLabel(Farm,"Auto: usa o mesmo motor do Fast Attack do topo, com um único loop. O toggle manual ligado também tem prioridade sobre cliques simulados. Matsune Click: VirtualUser com alternativa R2. Hoho R2: exemplo comentado do carregador Hoho. Tool: ativação normal. DEBUG distingue envio e vida observada.")
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
        local quest=questRuntime.GetBestQuest() or questForLevel() or preload.BestQuest();text=text.."\nQuest selecionada: "..(quest and quest.Mob or "sem dados")
        statusLabel.Text=text
    end
    button(pageStatus,"Atualizar status",status)
    toggleJob(pageStatus,"Atualizar status automaticamente","Status",5,status)
    bind(LocalPlayer.CharacterAdded,function()
        stopMove();fixedCombatTarget=nil;fixedCombatPoint=nil;fixedCombatOffset=nil;restoreCamera()
    end,"features.respawn")
    bind(LocalPlayer.CharacterRemoving,function()
        releaseInput()
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
        fastToggle.Set(false)
        fastAttackApi:StopAll()
        releaseInput()
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
        return {Active=active,SupportedGame=supported,Mode=options.Mode,Attack=table.clone(attackState),TweenSpeed=options.Speed,Jobs=running,Flags=table.clone(flags),Farm=table.clone(farmStatus),FastAttack=fastAttackApi:GetState(),QuestRuntime=questRuntime.GetState(),Preload=preload.GetState(),Movement={Owner=moveOwner,Suspended=motionState~=nil,Holding=motionState and motionState.Holding==true or false,Anchored=moveRoot and moveRoot.Anchored or false,Destination=moveTarget and moveTarget.Position or nil,FixedFarm=options.FixedFarm}}
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
        check("fluent",not Fluent.Unloaded and Main.Parent~=nil,"embedded Fluent UI active")
        check("visibility",Main.Visible==isUIOpen,"Ctrl esquerdo/float visibility synchronized")
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
    local sharedAttack=snapshot.FastAttack or {}
    local rows={"XERECA HUB | diagnóstico local",
        "Farm: "..tostring(farm.Phase).." | alvo: "..tostring(farm.Target or farm.ExpectedMob),
        "Ataque: "..tostring(attack.Phase).." | método: "..tostring(attack.Method).." | transporte: "..tostring(attack.Transport).." | clique: "..tostring(attack.Input),
        "FastAttack compartilhado: "..tostring(sharedAttack.Running).." | manual: "..tostring(sharedAttack.ManualEnabled).." | controle: "..tostring(sharedAttack.Owner).." | envios: "..tostring(sharedAttack.Dispatches),
        "Arma: "..tostring(attack.Tool).." | distância: "..tostring(attack.Distance).." | tentativas: "..tostring(attack.Attempts),
        "Vida do alvo: "..tostring(attack.Health).." / "..tostring(attack.MaxHealth).." | última queda de vida: "..(attack.LastDamageAt and string.format("há %.1fs",os.clock()-attack.LastDamageAt) or "não observada"),
        "Soltar clique: "..tostring(attack.InputRelease).." | alternativa: "..tostring(attack.InputFallback),
        "Movimento: "..tostring(movement.Owner).." | fixo: "..tostring(movement.Holding).." | ancorado: "..tostring(movement.Anchored),
        "Preload: "..tostring(snapshot.Preload and snapshot.Preload.Rows).." registros | mar: "..tostring(snapshot.Preload and snapshot.Preload.Sea),
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
    UIBackend = "Fluent",
    BackupCommit = "5af5e68a48520997dc044708e75818fffa3a0bbb",
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
    SetTheme = function(first, second) local name=type(first)=="table" and second or first; if not destroyed and THEMES[name] then activeTheme=name; applyTheme({}); Float.BackgroundColor3=T().Accent end end,
    Notify = notify,
    Toggle = toggleUI,
}
_G.XerecaUILib = UILib
table.insert(cleanupFns,function() if _G.XerecaUILib==UILib then _G.XerecaUILib=nil end end)
shared._UILibUnload = unload

FluentWindow:SelectTab(1)
setOpen(true)
debugLog("INFO", "startup", "UI ready; Ctrl esquerdo configured")
print("[UILib] XERECA HUB Fluent preview loaded successfully.")
return UILib




