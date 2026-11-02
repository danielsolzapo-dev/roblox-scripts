-- Pure policy; embedded in Standalone by scripts/sync_kaitun.py. No game calls.
return function(snapshot, config)
    if not snapshot.Supported then return "stop", "Jogo ou Sea não reconhecido" end
    if type(snapshot.Level) ~= "number" or snapshot.Level ~= snapshot.Level then
        return "wait", "Aguardando nível replicado"
    end
    if not snapshot.Alive then return "wait", "Aguardando personagem vivo" end
    local target = math.max(1, math.floor(config.Target))
    if config.Saber then target = math.max(target, 200) end
    if config.SecondSea then target = math.max(target, 700) end
    if snapshot.Sea == 1 and config.Saber and snapshot.Level >= 200 then
        if snapshot.Saber == nil then return "wait", "Consultando posse do Saber" end
        if not snapshot.Saber and snapshot.Level >= 200 then return "saber", "Obter Saber" end
    end
    if snapshot.Sea == 1 and config.SecondSea and snapshot.Level >= 700 then
        return "sea2", "Desbloquear Segundo Sea"
    end
    if snapshot.Level >= target then return "done", "Meta de nível e objetivos disponíveis concluídos" end
    return "level", "Level Farm até " .. tostring(target)
end
