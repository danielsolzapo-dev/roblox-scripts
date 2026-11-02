-- Mocks exercise the actual embedded initKaitun, inserted at the marker by run_kaitun.py.
local now=0
local os={clock=function()return now end}
local active,destroyed=true,false
local sea,alive,level=1,true,100
local supported=true
local flags,controls,onJobStop,firstQueries={},{},{},{}
local movementJobs={Farm=true,FirstSea=true,Boat=true}
local options={Mode="Boss",AutoEquip=false}
local farmStatus={Phase="idle"}
local firstSeaState={Goal="Saber"}
local plateIndex=1
local kaitunRuntime={}
local stopLedger={Pending={}}
local inventory={{Name="Katana"}}
local tools={}
local RS,LocalPlayer={},{}
local widgets={}
local step
local function path()return {Value=level}end
local function character()if alive then return {},{}end end
local function seaIndex()return sea end
local function hasTool(name)return tools[name]end
local function cleanName(name)return string.lower(name)end
local function firstQuery(key)
    firstQueries[key]={Value=inventory,Updated=now}
    return inventory
end
local function addTab()return {}end
local function addLabel(_,text)return {Text=text}end
local function addBtn()end
local function addSlider(_,opts)widgets[opts.Name]=opts.Callback end
local function addToggle(_,name,_,callback)widgets[name]=callback end
local function worker(name)
    return {Set=function(on)
        if on and kaitunRuntime.Cancel then kaitunRuntime.Cancel("Movimento externo")end
        flags[name]=on
    end}
end
controls.Farm=worker("Farm");controls.FirstSea=worker("FirstSea");controls.Boat=worker("Boat")
controls.MasteryGoal=worker("MasteryGoal")
local farmControl=controls.Farm
local modeControl={Set=function(mode)
    if kaitunRuntime.Cancel then kaitunRuntime.Cancel("Modo alterado")end
    options.Mode=mode
end}
kaitunRuntime.AutoEquipControl={Set=function(on)options.AutoEquip=on end}
local function toggleJob(_,_,name,_,fn)
    step=fn
    local c={Set=function(on)
        flags[name]=on
        if not on then
            stopLedger.Context=stopLedger.Pending[name]or "Parada geral"
            onJobStop[name]()
            stopLedger.Context=nil
        end
    end}
    controls[name]=c
    return c
end
-- INSERT ACTUAL COORDINATOR
local kaitun=kaitunRuntime.Init()
assert(not flags.Kaitun and not options.AutoEquip, "startup must not enable automation")
widgets["Kaitun: obter Saber no First Sea"](true)
widgets["Kaitun: desbloquear Segundo Sea"](true)
flags.Boat=true
controls.Kaitun.Set(true);step()
assert(flags.Farm and not flags.Boat and options.AutoEquip, "single movement owner")
level=200;step()
assert(flags.FirstSea and not flags.Farm and firstSeaState.Goal=="Saber", "Saber stage")
inventory={{Name="Saber"}};step()
assert(flags.Farm and not flags.FirstSea, "inventory reward advances queue")
level=700;step()
assert(flags.FirstSea and firstSeaState.Goal=="Segundo Sea", "Sea 2 stage")
sea=2;step()
assert(not flags.Kaitun and not flags.FirstSea, "completion stops owned worker")
assert(kaitun.GetState().Phase=="done" and options.Mode=="Boss" and not options.AutoEquip, "restore passive settings")

sea=1;level=100
controls.Kaitun.Set(true);step()
kaitunRuntime.Cancel("Movimento manual selecionado")
assert(not flags.Kaitun and not flags.Farm, "manual takeover cancels queue")
controls.Kaitun.Set(true);step()
kaitun.Stop("Parada geral")
assert(not flags.Kaitun and not flags.Farm, "global stop clears child")
controls.Kaitun.Set(true);step()
now=now+181;step()
assert(not flags.Kaitun and not flags.Farm, "stalled level pauses")

level=200;inventory=nil
controls.Kaitun.Set(true);step()
assert(kaitun.GetState().Phase=="wait" and not flags.Farm and not flags.FirstSea, "unknown inventory does not start puzzle")
now=now+181;step()
assert(not flags.Kaitun, "unknown inventory bounded by timeout")

inventory={{Name="Saber"}};level=300
controls.Kaitun.Set(true);step()
flags.Farm=false;step()
assert(not flags.Kaitun, "failed child is not silently restarted")
controls.Kaitun.Set(true);step()
widgets["Nível alvo do Kaitun"](800)
assert(not flags.Kaitun and not flags.Farm, "configuration edit pauses")
controls.Kaitun.Set(true);step()
alive=false;step()
assert(kaitun.GetState().Phase=="wait" and not flags.Farm, "death releases worker")
alive=true;step()
assert(flags.Farm, "respawn resumes only while queue enabled")
kaitun.Stop("Script descarregado")
assert(not flags.Farm and not flags.FirstSea and not kaitun.GetState().Running, "unload cleans owned jobs")
controls.Kaitun.Set(true);step()
supported=false;step()
assert(not flags.Kaitun and not flags.Farm, "unsupported game stops")
print("Kaitun lifecycle: progression, ownership, stop, timeout, inventory, respawn passed")
