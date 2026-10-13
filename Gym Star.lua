
if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 70906625936847 then
    warn('[PuckAFK Gym Star] Start from the Gym Star Simulator main game place.')
    return
end
local env=(type(getgenv)=='function' and getgenv()) or _G
local old=env.PuckAFK_GymStar_Instance
if old and type(old.Unload)=='function' then pcall(old.Unload) end
env.PuckAFK_GymStar_ResumeUniverse=tonumber(game.GameId)
env.PuckAFK_GymStar_ResumeMaster=false
env.PuckAFK_GymStar_ResumeSource=[===[--[[
    PuckAFK Gym Star Simulator | Smart Autofarm v1.6.4
    Place ID: 70906625936847
    Source-based implementation researched from the user's 2026-10-13 RBXL and gameplay remote log.
    NOT live tested; multiplayer/server behavior and executor support may differ.
    v1.6.4: put Unload in Settings and restore a dedicated Configs tab with saved profiles (no raw JSON).
    v1.6.2: hide the raw JSON/Configs tab; executor-aware auto resume after teleport.
    v1.6.1: clean beginner-friendly UI with Home, Autofarm and Settings.
    Preserves all v1.6.0 farming, safety, progress and persistence systems.
    Auto-saving is unchanged. A missing executor file API may limit storage to a session.

    Designed to use the existing game-defined remotes, world/gear/rebirth configuration,
    and the public PuckUI library. Avoids purchasing Robux products and auto-deleting pets.
    PuckUI auto-saves / auto-loads silently; the Configs tab exposes profiles but no raw JSON.
    Auto-resume requires a teleport queue API; automatic client injection is not guaranteed.
]]

--[[
    Auto-resume bootstrap. The one-file distribution embeds this entire core
    as PuckAFK_GymStar_ResumeSource, allowing supported executors to queue the
    exact script after a same-experience server teleport without a web host.
    Queue only during an actual teleport, never continuously.
]]
if not game:IsLoaded() then game.Loaded:Wait() end
local resumeEnv = (type(getgenv) == 'function' and getgenv()) or _G
local resumePlayers = game:GetService('Players')
local resumePlayer = resumePlayers.LocalPlayer
if not resumePlayer then
    local start = os.clock()
    while not resumePlayers.LocalPlayer and os.clock() - start < 15 do
        task.wait(0.1)
    end
    resumePlayer = resumePlayers.LocalPlayer
end
local resumeSource = resumeEnv.PuckAFK_GymStar_ResumeSource
local resumeUniverse = tonumber(resumeEnv.PuckAFK_GymStar_ResumeUniverse) or tonumber(game.GameId)
local resumeTargetPlace = 70906625936847
local resumeControl = {Enabled = true, Supported = false, Queued = false, Connection = nil}

local function findTeleportQueue()
    local env = resumeEnv
    local function take(value)
        if type(value) == 'function' then return value end
    end
    return take(env.queue_on_teleport)
        or take(env.queueonteleport)
        or take(env.queue_teleport)
        or take(queue_on_teleport)
        or take(queueonteleport)
        or (type(syn) == 'table' and take(syn.queue_on_teleport))
        or (type(fluxus) == 'table' and take(fluxus.queue_on_teleport))
end

local resumeQueue = findTeleportQueue()
resumeControl.Supported = type(resumeQueue) == 'function' and type(resumeSource) == 'string' and #resumeSource > 200

local priorInstance = resumeEnv.PuckAFK_GymStar_Instance
if priorInstance and type(priorInstance.Unload) == 'function' then
    pcall(priorInstance.Unload)
end
local priorController = resumeEnv.PuckAFK_GymStar_ResumeControl
if priorController and type(priorController.Disconnect) == 'function' then
    pcall(function() priorController:Disconnect() end)
end

function resumeControl:Disconnect()
    self.Enabled = false
    if self.Connection then
        pcall(function() self.Connection:Disconnect() end)
        self.Connection = nil
    end
end

local function makeTeleportPayload(wasFarming)
    -- Explicit universe guard prevents the script from following unrelated games.
    -- Capture source in a Lua quoted literal so the queued run works without HTTP.
    return "if not game:IsLoaded() then game.Loaded:Wait() end\n"
        .. 'if tonumber(game.GameId) ~= ' .. tostring(resumeUniverse) .. ' then return end\n'
        .. "local env=(type(getgenv)=='function' and getgenv()) or _G\n"
        .. 'env.PuckAFK_GymStar_ResumeUniverse=' .. tostring(resumeUniverse) .. '\n'
        .. 'env.PuckAFK_GymStar_ResumeMaster=' .. tostring(wasFarming == true) .. '\n'
        .. 'env.PuckAFK_GymStar_ResumeSource=' .. string.format('%q', resumeSource) .. '\n'
        .. 'local run,err=loadstring(env.PuckAFK_GymStar_ResumeSource)\n'
        .. 'if run then run() else warn("[PuckAFK Gym Star] Auto resume compile failed: "..tostring(err)) end'
end

local function scheduleAfterTeleport()
    if not resumeControl.Enabled or resumeControl.Queued or not resumeControl.Supported then return end
    if tonumber(game.GameId) ~= resumeUniverse then return end
    local instance = resumeEnv.PuckAFK_GymStar_Instance
    local wasFarming = (instance and instance.State and instance.State.Master == true)
        or (instance == nil and resumeEnv.PuckAFK_GymStar_ResumeMaster == true)
    if instance and instance.State and instance.State.AutoResume == false then return end
    if instance and instance.Window and instance.Window.Config then
        -- Best effort: flush the active profile before leaving this session.
        pcall(function() instance.Window:_WriteConfig(instance.Window.Config.Selected, false) end)
    end
    local source = makeTeleportPayload(wasFarming)
    local queued = false
    -- Use small, file-based queued bootstrap where executor file I/O is verified.
    if type(writefile) == 'function' and type(readfile) == 'function' then
        local path = 'PuckAFK_GymStar_Teleport_Resume.lua'
        local ok = pcall(writefile, path, source)
        if ok then
            local readOK, actual = pcall(readfile, path)
            if readOK and actual == source then
                local short = "local ok,code=pcall(readfile,'PuckAFK_GymStar_Teleport_Resume.lua');"
                    .. "if ok and type(code)=='string' then local f=loadstring(code);if f then f() end end"
                queued = pcall(resumeQueue, short)
            end
        end
    end
    -- No filesystem? Queue the full self-contained script directly.
    if not queued then queued = pcall(resumeQueue, source) end
    resumeControl.Queued = queued
    if not queued then resumeControl.LastFailure = 'Executor rejected queue_on_teleport' end
end

if resumePlayer then
    resumeControl.Connection = resumePlayer.OnTeleport:Connect(function(teleportState)
        if teleportState == Enum.TeleportState.Started
            or teleportState == Enum.TeleportState.InProgress then
            scheduleAfterTeleport()
        end
    end)
end
resumeEnv.PuckAFK_GymStar_ResumeControl = resumeControl

-- Intermediate places in the SAME Gym Star experience do not use Gym machines;
-- keep listening for a return teleport instead of running incompatible remotes.
if game.PlaceId ~= resumeTargetPlace then
    if tonumber(game.GameId) ~= resumeUniverse then
        resumeControl:Disconnect()
    end
    return
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local TweenService = game:GetService('TweenService')
local player = Players.LocalPlayer
if not player then return end

local shared = (type(getgenv) == 'function' and getgenv()) or _G
if shared.PuckAFK_GymStar_Instance and shared.PuckAFK_GymStar_Instance.Unload then
    pcall(shared.PuckAFK_GymStar_Instance.Unload)
end

local running = true
local state = {
    Master = (resumeEnv.PuckAFK_GymStar_ResumeMaster == true),
    Train = true,
    AutoGear = true,
    AutoResume = true,
    WeightPriority = 'Heaviest Weights',
    Balanced = 'Rebirth Needs',
    AllowFree = true,
    TrainClicksPerSecond = 10,
    StaminaTraining = true,
    StaminaMinShare = 12,
    AutoRecovery = true,
    AutoRewards = true, -- Single visible switch for the existing free reward systems.
    EnergyLowPercent = 25,
    EnergyResumePercent = 75,
    EnergyClickReserve = 3,
    EnergyCostBudgetPercent = 10,
    RecoveryTreadmillSeconds = 16,
    RecoveryRestSeconds = 18,
    ReselectSeconds = 35,
    MoveMode = 'Tween',
    TweenSpeed = 65,
    PaidSafetyRadius = 10,
    SafeRouteDetours = true,
    MachineRetrySilence = 35,
    FallbackMuscleTraining = true,
    BlockVipTravel = true,
    World = true,
    Competition = true,
    CompetitionInterval = 115,
    CompetitionClicksPerSecond = 4,
    CompeteForWorld = true,
    CompetitionPowerMargin = 145,
    CompetitionStatFloor = 70,
    CompetitionLossGrowth = 22,
    Rebirth = true,
    AutoPets = true,
    AutoEquipment = true,
    Hatch = true,
    HatchBudgetPercent = 5,
    HatchInterval = 2.5,
    HatchWorld = 'Current World',
    AutoFuse = false,
    Daily = true,
    Online = true,
    Weekly = true,
    Achievements = true,
    SeasonQuests = true,
    Coach = true,
    BuyFreeCoaches = false,
    Potion = false,
    PotionReserve = 1,
    PetMission = true,
    CollectionRewards = true,
    PetIndexRewards = true,
    Spin = true, -- Uses ONLY an already-owned free DailyToken
    Mail = true,
    EventRewards = true,
    RedeemCodes = true, -- Official creator-listed free code, once per session
    MinTrainingSession = 42,
    MaxMachineCandidates = 28,
    ChampionFirst = true,
    NoEnergyTimeoutSeconds = 110,
    VerifyTrainingStartSeconds = 1.25,
}
local cooldowns = {}
local busy = false
local travelTween = nil
local lastMachine = nil
local machineFails = {}
local hazardCache = {world = 0, time = 0, result = nil}
local noMachineStreak = 0
local fallbackTrainingStat = 0
local fallbackTrainingUntil = 0
local lastNoMachineReason = ''
local failedWorldTime = 0
local contestByUs = false
local contestStarted = false
local contestPowerAtEntry = 0
local contestWorld = 0
local contestChampionAtEntry = 0
local contestLosses = {}
local contestMinPower = {}
local lastTrainingGainAt = os.clock()
local lastTrainingValue = 0
local lastTrainingId = 0
local trainingBackoffUntil = 0
local energyRecovery = {
    active = false, phase = 'treadmill', beganAt = 0, phaseSince = 0,
    lastEnergy = 0, lastImprovedAt = 0, lastSeenAt = 0,
}
local nativeAutoWasOn = false
local nativeAutoSuppressed = false
local lastTrainClickAt = 0
local energyUnavailableWarned = false
local lastContestStartedAt = 0
local lastSeasonClaim = {}
local mailboxClaimedAttempt = {}
local codeAttempted = {}
local eventClaimAttempt = {}
local failedMachineStats = {}
local machineStartPending = nil
local movementFailures = 0
local recentProblems = {}
local gearPlanCache = setmetatable({}, {__mode = 'k'})
local lastTrainingRootCheck = 0
local lastWorldStableAt = os.clock()
local nextCompetitionAt = os.clock() + 25
local worldLast = 1
local onMachineSince = 0
local machineStarted = 0
local hatchSession = false
local hatchSessionCount = 0
local nextHatchSession = os.clock() + 60
local lastError = ''
local errors = 0
local actions = 0
local status = 'Ready; enable Smart Autofarm'
local ui, window
local statsLabel, activityLabel, worldLabel
local signals = {}

local function setStatus(message)
    message = tostring(message)
    if status ~= message then
        status = message
    end
end
local function problemOnce(code, message, seconds)
    local now = os.clock()
    if now < (recentProblems[code] or 0) then return end
    recentProblems[code] = now + (seconds or 35)
    -- Quiet operation: safety and recovery logic continue without developer console spam.
end
local function notify(title, message)
    if ui then
        pcall(function() ui:Notify({ Title = title, Content = message, Duration = 3 }) end)
    end
end
local function safe(label, fn)
    local ok, result = pcall(fn)
    if not ok then
        lastError = tostring(label) .. ': ' .. tostring(result)
        errors += 1
        return nil
    end
    return result
end
local function throttle(tag, period)
    local now = os.clock()
    if (cooldowns[tag] or 0) > now then return false end
    cooldowns[tag] = now + period
    return true
end
local function val(parent, name, default)
    local obj = parent and parent:FindFirstChild(tostring(name))
    if obj and obj:IsA('ValueBase') then return obj.Value end
    return default
end
local function item(id)
    return tonumber(val(player:FindFirstChild('Bag'), tostring(id), 0)) or 0
end
local function currency()
    return item(1)
end
local function charReady()
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass('Humanoid')
    local root = char and char:FindFirstChild('HumanoidRootPart')
    if humanoid and root and humanoid.Health > 0 then return char, humanoid, root end
    return nil
end
local function hasObject(inst)
    return typeof(inst) == 'Instance' and inst.Parent ~= nil
end
local function cancelTravel()
    if travelTween then pcall(function() travelTween:Cancel() end); travelTween = nil end
end

local Msg = RS:WaitForChild('Msg', 15)
local Tool = RS:WaitForChild('Tool', 15)
if not Msg or not Tool then warn('[PuckAFK Gym Star] Game remotes not loaded'); return end
local Ev = Msg:WaitForChild('RemoteEvent', 15)
local Fn = Msg:WaitForChild('RemoteFunction', 15)
local Click = Msg:WaitForChild('Click', 15)
local CompetitionClick = Msg:WaitForChild('CompititionClick', 15)
if not Ev or not Fn or not Click or not CompetitionClick then warn('[PuckAFK Gym Star] Missing expected remotes'); return end
local okCfg, Cfg = pcall(require, Tool:WaitForChild('CfgFind', 12))
if not okCfg then warn('[PuckAFK Gym Star] Config module unavailable:', Cfg); return end
local configs = {}
for _, key in ipairs({'equipmentConf','worldConf','eggdataConf','rebirthConf','coachConf','achievedataConf'}) do
    configs[key] = safe('Config ' .. key, function() return Cfg.GetCfgByName(key) end) or {}
end
local worldConf = configs.worldConf
local equipmentConf = configs.equipmentConf
local eggConf = configs.eggdataConf
local rebirthConf = configs.rebirthConf
local coachConf = configs.coachConf
local enemyConf = safe('Config enemyConf', function() return Cfg.GetCfgByName('enemyConf') end) or {}
local achieveConf = configs.achievedataConf or {}
local buffConf = safe('Config buffdataConf', function() return Cfg.GetCfgByName('buffdataConf') end) or {}
local eggCollectionConf = safe('Config eggCollectionConf', function() return Cfg.GetCfgByName('eggCollectionConf') end) or {}
local indexRewardConf = safe('Config indexrewardConf', function() return Cfg.GetCfgByName('indexrewardConf') end) or {}
local LocalDataModule = safe('LocalData', function()
    return require(game.StarterPlayer.StarterPlayerScripts.LocalData)
end)
local GetDataModule = safe('GetData', function() return require(Tool.GetData) end)
local EnumMgr = safe('EnumMgr', function() return require(Tool.EnumMgr) end)
local function playerSnapshot()
    return LocalDataModule and safe('Read player snapshot', function() return LocalDataModule:GetLocalData() end)
end

local function invoke(action, ...)
    if not running then return nil end
    actions += 1
    return Fn:InvokeServer(action, ...)
end
local function send(action, ...)
    if not running then return end
    actions += 1
    Ev:FireServer(action, ...)
end
local function world()
    return tonumber(val(player, 'NowWorld', 1)) or 1
end
local function isCompeting()
    local c = player:FindFirstChild('竞赛信息')
    return val(c, '是否正在竞赛', false) == true
end
local function isTraining()
    return tonumber(val(player, 'TrainEquipment', 0)) ~= 0
end
local function trainingId()
    return tonumber(val(player, 'TrainEquipment', 0)) or 0
end
-- WARNING: Bag[10] is the trained STAMINA STAT, not usable energy.
-- CurStamina / MaxStamina are replicated NumberValues used by the game's endurance bar.
local function energyValues()
    local curObj = player:FindFirstChild('CurStamina')
    local maxObj = player:FindFirstChild('MaxStamina')
    if not curObj or not maxObj or not curObj:IsA('ValueBase') or not maxObj:IsA('ValueBase') then
        return nil, nil, nil
    end
    local maximum = tonumber(maxObj.Value)
    local current = tonumber(curObj.Value)
    if not maximum or maximum <= 0 or not current then return nil, nil, nil end
    current = math.clamp(current, 0, maximum)
    return current, maximum, current / maximum
end
local function energyClickBudget()
    local _, maximum = energyValues()
    if not maximum or not state.AutoRecovery then return math.huge end
    return math.max(0.1, maximum * math.clamp((tonumber(state.EnergyCostBudgetPercent) or 10) / 100, 0.03, 0.5))
end
local function currentTrainingCost()
    local cfg = equipmentConf[trainingId()]
    if not cfg or tonumber(cfg.TrainType) == 10 then return 0 end
    local folder = workspace:FindFirstChild('Scene')
    folder = folder and folder:FindFirstChild(tostring(val(player, 'NowWorld', 1)))
    folder = folder and folder:FindFirstChild('Training equipment')
    local current = hasObject(lastMachine) and lastMachine or
        (folder and folder:FindFirstChild(tostring(val(player, 'EquipmentName', ''))))
    if cfg.EquipmentType == 2 and current then
        local idx = current:FindFirstChild('IndexVt')
        if idx then
            local cost = 0
            for i, single in ipairs(cfg.StaminaCost or {}) do
                cost += math.max(0, tonumber(val(idx, tostring(i), 0)) or 0) * (tonumber(single) or 0)
            end
            return cost
        end
    end
    local gear = tonumber(val(current, 'TrainGear', 1)) or 1
    return math.max(0, tonumber(cfg.StaminaCost and cfg.StaminaCost[gear]) or 0)
end
local function beginEnergyRecovery(reason)
    if not state.AutoRecovery or not state.Train or not state.Master then return end
    local current = energyValues()
    if current == nil then return end
    if energyRecovery.active then return end
    local now = os.clock()
    energyRecovery.active = true
    energyRecovery.phase = 'treadmill'
    energyRecovery.beganAt = now
    energyRecovery.phaseSince = now
    energyRecovery.lastEnergy = current
    energyRecovery.lastImprovedAt = now
    setStatus('Low energy - recovering on a free treadmill ('..tostring(reason or 'low stamina')..')')
end
local function energyReadyForClick()
    if not state.AutoRecovery then return true end
    if energyRecovery.active then return false end
    local current, maximum, ratio = energyValues()
    if not current then return true end -- Missing replicated values: don't deadlock.
    local cost = currentTrainingCost()
    local floor = math.max(maximum * math.clamp(state.EnergyLowPercent / 100, 0.05, 0.7),
        cost * (1 + math.clamp(tonumber(state.EnergyClickReserve) or 3, 1, 10)))
    if current <= floor or ratio <= 0.02 then
        beginEnergyRecovery(string.format('%.0f%%, cost %.2g', ratio * 100, cost))
        return false
    end
    return true
end
local function controlNativeAutoClick(suppress)
    local setting = player:FindFirstChild('Setting')
    local isAuto = setting and setting:FindFirstChild('isAutoClick')
    local msgs = RS:FindFirstChild('ServerMsg')
    local remote = msgs and msgs:FindFirstChild('Setting')
    if not isAuto or not remote or not remote:IsA('RemoteFunction') then return end
    if suppress then
        if tonumber(isAuto.Value) == 1 and throttle('nativeAutoOff', 6) then
            nativeAutoWasOn = true
            nativeAutoSuppressed = true
            safe('Turn off overlapping built-in autoclick', function()
                remote:InvokeServer('isAutoClick', 0)
            end)
        end
    elseif nativeAutoSuppressed then
        nativeAutoSuppressed = false
        if nativeAutoWasOn then
            nativeAutoWasOn = false
            safe('Restore original built-in autoclick', function()
                remote:InvokeServer('isAutoClick', 1)
            end)
        end
    end
end
local function getScene()
    local sceneRoot = workspace:FindFirstChild('Scene')
    return sceneRoot and sceneRoot:FindFirstChild(tostring(world()))
end
local function bestUnlockedWorld()
    local maxWorld = tonumber(val(player, 'MaxWorld', 1)) or 1
    return math.clamp(maxWorld, 1, #worldConf)
end
local function worldCost(id)
    return tonumber(worldConf[id] and worldConf[id].Cost) or math.huge
end
local function nextWorld()
    local candidate = bestUnlockedWorld() + 1
    return worldConf[candidate] and candidate or nil
end

-- VIP is a machine-instance property in the actual place, not an equipment type.
-- Every machine tagged IsVipMachine / VFX_VIP is permanently disallowed.
local function isVipMachine(model)
    if not model then return true end
    local flag = model:FindFirstChild('IsVipMachine')
    if flag and flag:IsA('BoolValue') and flag.Value then return true end
    if model:FindFirstChild('VFX_VIP') then return true end
    local n = string.lower(model.Name)
    if n:find('vip', 1, true) or n:find('robux', 1, true) or n:find('premium', 1, true) then return true end
    return false
end

local function hazardParts()
    local currentWorld = world()
    local now = os.clock()
    if hazardCache.world == currentWorld and hazardCache.result and now - hazardCache.time < 2.5 then
        return hazardCache.result
    end
    local scene = getScene()
    local result = {}
    if not scene then return result end
    local machines = scene:FindFirstChild('Training equipment')
    if machines then
        for _, m in ipairs(machines:GetChildren()) do
            if m:IsA('Model') and isVipMachine(m) then
                local trigger = m:FindFirstChild('TiggerPart', true)
                if trigger and trigger:IsA('BasePart') then
                    result[#result + 1] = {point = trigger.Position, radius = 11, name = 'VIP equipment'}
                end
            end
        end
    end
    local areas = scene:FindFirstChild('Function')
    if areas then
        -- Paid stores are MODELS called 付费商店 in the source place;
        -- checking BasePart names alone fails to exclude their footprint.
        for _, m in ipairs(areas:GetDescendants()) do
            local l = string.lower(m.Name)
            local protected = l:find('vip', 1, true) or l:find('robux', 1, true)
                or l:find('paid', 1, true) or l:find('purchase', 1, true)
                or l:find('付费', 1, true) or l:find('premium', 1, true)
            if protected then
                if m:IsA('BasePart') then
                    result[#result + 1] = {point = m.Position,
                        radius = math.max(11, m.Size.X * 0.5 + 8, m.Size.Z * 0.5 + 8), name = m.Name}
                elseif m:IsA('Model') then
                    local ok, center, size = pcall(function()
                        local cf, size = m:GetBoundingBox()
                        return cf.Position, size
                    end)
                    if ok and center and size then
                        result[#result + 1] = {point = center,
                            radius = math.min(75, math.max(16, size.X * 0.5 + 6, size.Z * 0.5 + 6)), name = m.Name}
                    end
                end
            end
        end
    end
    hazardCache.world, hazardCache.time, hazardCache.result = currentWorld, now, result
    return result
end
local function nearHazard(pos, hazards, allowAlreadyInside, origin)
    for _, h in ipairs(hazards) do
        local dist = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(h.point.X, 0, h.point.Z)).Magnitude
        if dist < math.max(h.radius, tonumber(state.PaidSafetyRadius) or 13) then
            local originDist = origin and (Vector3.new(origin.X, 0, origin.Z) - Vector3.new(h.point.X, 0, h.point.Z)).Magnitude or math.huge
            -- If a player manually spawned near a restricted machine, permit leaving it.
            if not (allowAlreadyInside and originDist < math.max(h.radius, tonumber(state.PaidSafetyRadius) or 13) and dist >= originDist) then
                return h.name
            end
        end
    end
    return nil
end
local function safeTravelLine(from, target)
    -- This safety exclusion is not user-toggleable.
    if not state.BlockVipTravel then state.BlockVipTravel = true end
    local hazards = hazardParts()
    local total = (from - target).Magnitude
    local steps = math.max(1, math.ceil(total / 6))
    for step = 1, steps do
        local p = from:Lerp(target, step / steps)
        local blocked = nearHazard(p, hazards, true, from)
        if blocked then return false, blocked end
    end
    return true
end

-- The old selector required ONE straight, unobstructed line from the player to
-- a training trigger. This falsely rejected valid, unoccupied free machines
-- behind VIP spots. Use safe intermediate points around hazards instead.
local function clearanceRadius(h)
    return math.max(h.radius, tonumber(state.PaidSafetyRadius) or 10)
end
local function pointToSegment2D(center, a, b)
    local ax, az = a.X - center.X, a.Z - center.Z
    local dx, dz = b.X - a.X, b.Z - a.Z
    local len2 = dx * dx + dz * dz
    local t = len2 > 0.0001 and math.clamp(-(ax * dx + az * dz) / len2, 0, 1) or 0
    local x, z = ax + t * dx, az + t * dz
    return math.sqrt(x * x + z * z), t
end
local function safeSegment2D(a, b, hazards)
    for _, h in ipairs(hazards) do
        local rad = clearanceRadius(h)
        local center = h.point
        local dx, dz = a.X - center.X, a.Z - center.Z
        local start2 = dx * dx + dz * dz
        local ex, ez = b.X - center.X, b.Z - center.Z
        local end2 = ex * ex + ez * ez
        if end2 < rad * rad then return false, h.name end
        local nearest = pointToSegment2D(center, a, b)
        if nearest < rad then
            -- Allow a player who spawned inside an exclusion to leave directly
            -- away from it, but never travel toward its interior.
            local vx, vz = b.X - a.X, b.Z - a.Z
            local exiting = start2 < rad * rad and dx * vx + dz * vz >= -0.001
            if not exiting then return false, h.name end
        end
    end
    return true
end
local function safeApproachPoint(target, origin, hazards)
    -- A free machine's prompt can itself be less than 10 studs from a VIP
    -- machine. A safe adjacent standing point still permits starting it.
    local points = {target}
    for _, dist in ipairs({2, 3, 4, 5, 6, 7, 8}) do
        for k = 0, 11 do
            local theta = math.pi * 2 * k / 12
            points[#points + 1] = target + Vector3.new(math.cos(theta)*dist, 0, math.sin(theta)*dist)
        end
    end
    local best, score = nil, math.huge
    for _, p in ipairs(points) do
        if not nearHazard(p, hazards, false) then
            local s = (origin - p).Magnitude * 0.16 + (p - target).Magnitude * 5
            if s < score then best, score = p, s end
        end
    end
    return best
end
local function planSafeRoute(startPoint, goalPoint, hazards)
    hazards = hazards or hazardParts()
    if nearHazard(goalPoint, hazards, false) then return nil, 'target too near premium' end
    local direct = safeSegment2D(startPoint, goalPoint, hazards)
    if direct then return {goalPoint} end
    if not state.SafeRouteDetours then return nil, 'direct route blocked and detours disabled' end

    -- Small visibility graph: eight comfortably spaced points OUTSIDE each
    -- relevant exclusion circle, plus start and destination. Dijkstra finds
    -- a route whose every segment passes the same safety filter.
    local blockers = {}
    for _, h in ipairs(hazards) do
        local d = pointToSegment2D(h.point, startPoint, goalPoint)
        if d <= clearanceRadius(h) + 28 then
            blockers[#blockers+1] = {h = h, d = d}
        end
    end
    table.sort(blockers, function(a,b) return a.d < b.d end)
    local nodes = {startPoint, goalPoint}
    local limit = math.min(#blockers, 12)
    for j = 1, limit do
        local h = blockers[j].h
        local baseR = clearanceRadius(h)
        -- 12% extra radius ensures chords between 8 ring points don't cut
        -- through a prohibited circular exclusion.
        local r = baseR + math.max(3.5, baseR * 0.13)
        for k = 0, 7 do
            local angle = math.pi * 2 * k / 8
            local point = Vector3.new(h.point.X + r * math.cos(angle),
                startPoint.Y + (goalPoint.Y - startPoint.Y) * 0.5,
                h.point.Z + r * math.sin(angle))
            if not nearHazard(point, hazards, false) then nodes[#nodes+1] = point end
        end
    end
    local n = #nodes
    local best = table.create(n, math.huge)
    local used, previous = {}, {}
    best[1] = 0
    for _ = 1, n do
        local nextNode, nextCost = nil, math.huge
        for i = 1,n do
            if not used[i] and best[i] < nextCost then nextNode, nextCost = i, best[i] end
        end
        if not nextNode or nextNode == 2 then break end
        used[nextNode] = true
        for j = 2, n do
            if not used[j] then
                local a, b = nodes[nextNode], nodes[j]
                local dist = (a - b).Magnitude
                if nextCost + dist < best[j] and safeSegment2D(a, b, hazards) then
                    best[j], previous[j] = nextCost + dist, nextNode
                end
            end
        end
    end
    if not previous[2] then return nil, 'no VIP-safe detour' end
    local indexes, idx = {}, 2
    while idx and idx ~= 1 and #indexes <= n do
        table.insert(indexes, 1, idx)
        idx = previous[idx]
    end
    if idx ~= 1 then return nil, 'route reconstruction failed' end
    local route = {}
    for _, i in ipairs(indexes) do route[#route+1] = nodes[i] end
    if #route > 28 then return nil, 'too many waypoints' end
    return route
end

-- Movement is serialized and screened against known premium targets before travel.
local function moveTo(target, proximity, preparedRoute)
    if not running or not state.Master or isCompeting() then return false end
    if typeof(target) ~= 'Vector3' then return false end
    local _, humanoid, root = charReady()
    if not root then return false end
    if busy then return false end
    if nearHazard(target, hazardParts(), false) then return false end
    if (root.Position - target).Magnitude <= (proximity or 7) then
        -- No movement needed, including for the manual/None navigation mode.
        return true
    end
    if state.MoveMode == 'None' then return false end
    local route = preparedRoute
    if not route then
        route = planSafeRoute(root.Position, target)
    end
    if not route then
        if throttle('routeFailed', 13) then setStatus('Route blocked; staying outside VIP/paid areas') end
        return false
    end
    if (root.Position - target).Magnitude > 1200 then return false end
    busy = true
    local success = true
    local initialWorld = world()
    local departure = root.Position
    local _, _, finalRoot = charReady()
    if not finalRoot then busy = false; return false end
    local segments = route
    for i, waypoint in ipairs(segments) do
        if not running or not state.Master or isCompeting() or world() ~= initialWorld then
            success = false; break
        end
        local character, hum, liveRoot = charReady()
        if not liveRoot or not hum then success = false; break end
        local verified = safeSegment2D(liveRoot.Position, waypoint, hazardParts())
        if not verified then success = false; break end
        local closeEnough = (i == #segments) and (proximity or 7) or 3
        if (liveRoot.Position - waypoint).Magnitude > closeEnough then
            cancelTravel()
            if state.MoveMode == 'Walk' then
                local finished = false
                local c = hum.MoveToFinished:Connect(function() finished = true end)
                hum:MoveTo(waypoint)
                local timeout = os.clock() + math.clamp((liveRoot.Position - waypoint).Magnitude /
                    math.max(hum.WalkSpeed, 8) * 2 + 3, 4, 28)
                local blockedOnRoute = false
                while running and state.Master and not finished and os.clock() < timeout do
                    if isCompeting() or world() ~= initialWorld or not liveRoot.Parent then break end
                    if nearHazard(liveRoot.Position, hazardParts(), true, departure) then
                        hum:MoveTo(liveRoot.Position)
                        blockedOnRoute = true
                        break
                    end
                    task.wait(0.12)
                end
                c:Disconnect()
                if blockedOnRoute then success = false; break end
            else
                local height = math.clamp(liveRoot.Position.Y, waypoint.Y + 2, waypoint.Y + 5)
                local position = Vector3.new(waypoint.X, height, waypoint.Z)
                local duration = math.clamp((position - liveRoot.Position).Magnitude /
                    math.max(tonumber(state.TweenSpeed) or 65, 10), 0.1, 13)
                local ok = pcall(function()
                    travelTween = TweenService:Create(liveRoot, TweenInfo.new(duration,
                        Enum.EasingStyle.Linear), {CFrame = CFrame.new(position)})
                    travelTween:Play()
                end)
                if not ok then success = false; break end
                local timeout = os.clock() + duration + 0.8
                while running and state.Master and os.clock() < timeout do
                    if isCompeting() or world() ~= initialWorld or not liveRoot.Parent then break end
                    if (liveRoot.Position - position).Magnitude <= 3 then break end
                    task.wait(0.07)
                end
                cancelTravel()
            end
            if not running or isCompeting() or world() ~= initialWorld or
               not hasObject(liveRoot) or (liveRoot.Position - waypoint).Magnitude > closeEnough + 7 then
                success = false; break
            end
        end
    end
    cancelTravel()
    busy = false
    local _, _, rootNow = charReady()
    local arrived = success and rootNow ~= nil and (rootNow.Position - target).Magnitude <= (proximity or 7) + 2
    if not arrived then movementFailures += 1 end
    return arrived
end

local function equipmentFolder()
    local scene = getScene()
    return scene and scene:FindFirstChild('Training equipment')
end
local function candidateTarget(model)
    if not model then return nil end
    local trigger = model:FindFirstChild('TiggerPart', true)
    if trigger and trigger:IsA('BasePart') then return trigger.Position end
    local point = model:FindFirstChild('TriggerPos')
    if point and point:IsA('CFrameValue') then return point.Value.Position end
    -- Arbitrary pivots may be metres away from the actual training prompt.
    -- Never infer the training location from an unverified pivot.
    return nil
end
local function machineConfig(model)
    local id = tonumber(val(model, 'EquipmentID', 0)) or 0
    return equipmentConf[id], id
end
-- When near a new champion, do not rebirth away the required competition power.
-- Otherwise the six-stat rebirth planner would select only stamina after the
-- next rebirth needs were met and never build enough muscle to win.
local function championTrainingGoal()
    local id = world()
    if not state.Competition or not state.CompeteForWorld then return nil end
    if (tonumber(val(player:FindFirstChild('Record'), 'GymChampion', 0)) or 0) >= id then return nil end
    local cfg = worldConf[id]
    if not cfg or type(cfg.Enemys) ~= 'table' or #cfg.Enemys == 0 then return nil end
    local maximum, ability = 0, {0,0,0,0,0}
    for _, enemyId in ipairs(cfg.Enemys) do
        local e = enemyConf[tonumber(enemyId)]
        if e and type(e.Ability) == 'table' then
            local total = 0
            for i = 1, 5 do
                local v = tonumber(e.Ability[i]) or 0
                total += v
                ability[i] = math.max(ability[i], v)
            end
            maximum = math.max(maximum, total)
        end
    end
    if maximum <= 0 then return nil end
    local penalty = math.min(130,(contestLosses[id] or 0) * state.CompetitionLossGrowth)
    local margin = (state.CompetitionPowerMargin + penalty) / 100
    return maximum * margin, ability, margin
end
local function championNearEnough()
    local goal = championTrainingGoal()
    if not goal then return false end
    local power = 0
    for i=11,15 do power += math.max(0,item(i)) end
    return power >= goal * 0.50
end
local function desiredMuscle()
    if state.Balanced == 'Stamina' then return 10 end
    if state.Balanced == 'Chest' then return 11 end
    if state.Balanced == 'Abs' then return 12 end
    if state.Balanced == 'Back' then return 13 end
    if state.Balanced == 'Arms' then return 14 end
    if state.Balanced == 'Legs' then return 15 end

    -- Champion progression has to be trained BEFORE resetting the muscles.
    -- v1.5 only considered champion stats after reaching 50% of total power;
    -- it could repeatedly target finished rebirth stats (usually stamina).
    local goal, ability, margin = championTrainingGoal()
    if state.ChampionFirst and goal then
        local totalAbility = 0
        for i = 1, 5 do totalAbility += (tonumber(ability[i]) or 0) end
        if totalAbility > 0 then
            local weakest, weakestRatio = 11, math.huge
            for i = 1, 5 do
                local enemyAbility = tonumber(ability[i]) or 0
                local required = math.max(enemyAbility * (tonumber(state.CompetitionStatFloor) or 70) / 100,
                    goal * enemyAbility / totalAbility)
                local ratio = item(i + 10) / math.max(1, required)
                if ratio < weakestRatio then weakest, weakestRatio = i + 10, ratio end
            end
            return weakest
        end
    end

    local level = (tonumber(val(player, 'rebirthCount', 0)) or 0) + 1
    local nextCfg = rebirthConf[level]
    local bestId, bestScore = 10, -math.huge
    local minShare = math.clamp((tonumber(state.StaminaMinShare) or 12) / 100, 0.02, 0.4)
    local needFound = false
    for id = 10, 15 do
        local have = math.max(0, item(id))
        local deficit
        if state.Balanced == 'Rebirth Needs' and nextCfg and type(nextCfg.need) == 'table' then
            local required = tonumber(nextCfg.need[id - 9]) or 1
            deficit = math.max(0, required - have) / math.max(required, 1)
            if deficit > 0 then needFound = true end
        else
            deficit = 1 / math.max(1, have + 1)
        end
        if id == 10 then
            if not state.StaminaTraining then deficit = -1
            elseif deficit > 0 then deficit += minShare * 0.03 end
        end
        if deficit > bestScore then bestScore, bestId = deficit, id end
    end
    if nextCfg and not needFound and not state.Competition then
        return state.StaminaTraining and 10 or 11
    end
    return bestId
end
local function availableGear(cfg)
    local gear = 1
    if not cfg or type(cfg.Require) ~= 'table' then return gear end
    local stat = item(cfg.TrainType)
    local affordableBudget = energyClickBudget()
    local anyAffordable = false
    for k, minimum in ipairs(cfg.Require) do
        local cost = tonumber(cfg.StaminaCost and cfg.StaminaCost[k]) or 0
        if tonumber(minimum) and stat >= tonumber(minimum) and
           (tonumber(cfg.TrainType) == 10 or cost <= affordableBudget) then
            gear = k
            anyAffordable = true
        end
    end
    -- Even at low energy a first-level setting may be needed to get started;
    -- other guards stop the click before the server exhausts CurStamina.
    if not anyAffordable and tonumber(cfg.TrainType) ~= 10 then return 1 end
    return gear
end
local function chooseMachine(targetStat)
    local folder = equipmentFolder()
    local _, _, root = charReady()
    if not folder or not root then return nil, nil, nil, 'world equipment folder or player root missing' end
    local hazards = hazardParts()
    local ranked, rejected = {}, {total = 0, matching = 0, vip = 0, occupied = 0,
        unsafe = 0, cooldown = 0, noTarget = 0}
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA('Model') then
            rejected.total += 1
            local cfg = machineConfig(model)
            if cfg and tonumber(cfg.TrainType) == targetStat then
                rejected.matching += 1
                if isVipMachine(model) then
                    rejected.vip += 1
                elseif not state.AllowFree and cfg.EquipmentType == 2 then
                    rejected.vip += 1
                elseif (tonumber(val(model,'OwnerID',0)) or 0) ~= 0 then
                    rejected.occupied += 1
                elseif (machineFails[model] or 0) > os.clock() then
                    rejected.cooldown += 1
                else
                    local rawTarget = candidateTarget(model)
                    if not rawTarget then
                        rejected.noTarget += 1
                    else
                        local approach = safeApproachPoint(rawTarget, root.Position, hazards)
                        if not approach then
                            rejected.unsafe += 1
                        else
                            local g = availableGear(cfg)
                            local add = tonumber(cfg.TrainAdd and cfg.TrainAdd[g]) or 0
                            if cfg.EquipmentType == 2 then add = tonumber(cfg.TrainAdd and cfg.TrainAdd[1]) or add end
                            local stamina = tonumber(cfg.StaminaCost and cfg.StaminaCost[g]) or 0
                            local budget = energyClickBudget()
                            if cfg.EquipmentType == 2 then
                                stamina = math.huge
                                for k, required in ipairs(cfg.Require or {}) do
                                    if item(cfg.TrainType) >= (tonumber(required) or math.huge) then
                                        stamina = math.min(stamina, tonumber(cfg.StaminaCost and cfg.StaminaCost[k]) or math.huge)
                                    end
                                end
                            end
                            local distance = (root.Position - approach).Magnitude
                            local score = (add + 0.01) / (1 + stamina * 0.08) * 100 - distance * 0.04
                            if tonumber(cfg.TrainType) ~= 10 and stamina > budget then score -= 5000 end
                            if model == lastMachine then score += 35 end
                            if cfg.EquipmentType == 1 then score += 50 end
                            if cfg.EquipmentType == 3 then score += 40 end
                            if cfg.EquipmentType == 2 then score -= 8 end
                            ranked[#ranked+1] = {model=model, cfg=cfg, gear=g, approach=approach, score=score,
                                distance=distance}
                        end
                    end
                end
            end
        end
    end
    table.sort(ranked, function(a,b) return a.score > b.score end)
    local candidatesTried = 0
    for _, c in ipairs(ranked) do
        candidatesTried += 1
        if c.distance < 1150 then
            local route, reason = planSafeRoute(root.Position, c.approach, hazards)
            if route then
                return c.model, c.cfg, c.gear, nil, c.approach, route
            end
            rejected.unsafe += 1
            if not rejected.pathReason then rejected.pathReason = reason end
        end
        if candidatesTried >= math.clamp(tonumber(state.MaxMachineCandidates) or 20, 8, 40) then break end
    end
    local reason = string.format('stat %d: %d machines, %d matching, %d VIP, %d occupied, %d unsafe routes, %d cooling, %d no trigger%s',
        targetStat, rejected.total, rejected.matching, rejected.vip, rejected.occupied,
        rejected.unsafe, rejected.cooldown, rejected.noTarget,
        rejected.pathReason and (', route: '..tostring(rejected.pathReason)) or '')
    return nil,nil,nil,reason
end

-- Solve the native free-weight problem: choose at most N plates maximizing the
-- game's TRAIN GAIN, subject to total REQUIRE <= our current muscle stat.
-- This is a bounded integer knapsack (8 slots in this place), not "choose largest plate".
-- The game UI separately displays TrainGear (weight) and Require (strength needed).
-- If no normal machine can train a muscle without exhausting the whole energy
-- bar, build stamina capacity on a zero-cost treadmill before attempting it.
local function needsMoreStaminaCapacity(targetStat)
    if not state.AutoRecovery or not state.StaminaTraining or targetStat == 10 then return false end
    local folder = equipmentFolder()
    local _, maxEnergy = energyValues()
    if not folder or not maxEnergy then return false end
    local budget = energyClickBudget()
    local sawMuscleMachine = false
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA('Model') and not isVipMachine(model) then
            local cfg = machineConfig(model)
            if cfg and tonumber(cfg.TrainType) == targetStat then
                sawMuscleMachine = true
                for k, cost in ipairs(cfg.StaminaCost or {}) do
                    local need = tonumber(cfg.Require and cfg.Require[k]) or math.huge
                    if item(targetStat) >= need and tonumber(cost) and tonumber(cost) <= budget then
                        return false
                    end
                end
            end
        end
    end
    return sawMuscleMachine
end
local function freePlatePlan(cfg, model)
    local idx = model and model:FindFirstChild('IndexVt')
    if not idx or type(cfg.Require) ~= 'table' or type(cfg.TrainGear) ~= 'table' then return nil end
    local globalCfg = RS:FindFirstChild('Global game configuration')
    local trainCfg = globalCfg and globalCfg:FindFirstChild('Training configuration')
    local maxN = math.clamp(tonumber(val(trainCfg, 'Max number of free instruments', 8)) or 8, 1, 12)
    local limit = math.max(0, item(cfg.TrainType))
    local costLimit = energyClickBudget()
    local cached = gearPlanCache[model]
    local now = os.clock()
    if cached and cached.limit <= limit and limit <= cached.limit * 1.04 + 1
        and cached.costLimit == costLimit and cached.priority == state.WeightPriority
        and cached.maxN == maxN and now - cached.at < 12 then
        return cached.plan
    end
    local options = {}
    for i, need in ipairs(cfg.Require) do
        need = tonumber(need)
        local weight = tonumber(cfg.TrainGear[i]) or 0
        local gain = tonumber(cfg.TrainAdd and cfg.TrainAdd[i]) or 0
        local cost = math.max(0, tonumber(cfg.StaminaCost and cfg.StaminaCost[i]) or 0)
        if need and need > 0 and need <= limit and weight > 0 and cost <= costLimit then
            options[#options+1] = {index = i, need = need, weight = weight, gain = gain, cost = cost}
        end
    end
    if #options == 0 then return nil end
    -- A search bounded to 10k-40k combinations, with optimistic train gain.
    local bestWeight, bestGain, best = -1, -1, nil
    local work = {}
    local visited = 0
    local function evaluate(totalWeight, totalGain)
        if totalWeight <= 0 then return end -- Never program zero plates.
        local heavy = state.WeightPriority == 'Heaviest Weights'
        local better = heavy
            and (totalWeight > bestWeight or (totalWeight == bestWeight and totalGain > bestGain))
            or (not heavy and (totalGain > bestGain or (totalGain == bestGain and totalWeight > bestWeight)))
        if better then
            bestWeight, bestGain = totalWeight, totalGain
            best = table.clone(work)
        end
    end
    local function solve(pos, used, totalNeed, totalWeight, totalGain, totalCost)
        visited += 1
        if visited > 12000 then return end
        if pos > #options or used >= maxN then
            evaluate(totalWeight, totalGain)
            return
        end
        local o = options[pos]
        local can = math.min(maxN - used, math.floor((limit - totalNeed) / o.need))
        if o.cost > 0 then
            can = math.min(can, math.floor((costLimit - totalCost) / o.cost))
        end
        can = math.max(0, can)
        for num = can, 0, -1 do
            work[o.index] = num
            solve(pos + 1, used + num, totalNeed + num * o.need,
                totalWeight + num * o.weight, totalGain + num * o.gain, totalCost + num * o.cost)
        end
        work[o.index] = nil
    end
    solve(1, 0, 0, 0, 0, 0)
    gearPlanCache[model] = {limit = limit, costLimit = costLimit, priority = state.WeightPriority,
        maxN = maxN, at = now, plan = best}
    return best
end
local function adjustCurrentGear()
    if not state.AutoGear or not isTraining() or not hasObject(lastMachine) or isVipMachine(lastMachine) then return end
    if os.clock() < trainingBackoffUntil then return end
    if not throttle('gear', 1.0) then return end
    if tonumber(val(player, 'WeightLocked', 0)) == 1 then return end
    if tonumber(val(lastMachine, 'OwnerID', 0)) ~= 0 and
        tonumber(val(lastMachine, 'OwnerID', 0)) ~= player.UserId then return end
    local cfg, equipId = machineConfig(lastMachine)
    if not cfg or equipId ~= trainingId() then return end
    if cfg.EquipmentType == 2 then
        local idx = lastMachine:FindFirstChild('IndexVt')
        if not idx then return end
        local plan = freePlatePlan(cfg, lastMachine)
        if not plan then return end
        local current = {}
        local total = 0
        local required = 0
        for k, need in ipairs(cfg.Require or {}) do
            local amount = tonumber(val(idx, tostring(k), 0)) or 0
            current[k] = amount
            total += amount
            required += amount * (tonumber(need) or 0)
        end
        local globalCfg = RS:FindFirstChild('Global game configuration')
        local trainCfg = globalCfg and globalCfg:FindFirstChild('Training configuration')
        local maxPlates = tonumber(val(trainCfg, 'Max number of free instruments', 8)) or 8
        -- Remove excess plates first so upgrades do not stall at full slots.
        for k = #cfg.Require, 1, -1 do
            if (current[k] or 0) > (plan[k] or 0) then
                send('设置挡位', {Index = k, Count = -1})
                setStatus('Optimizing free weights: removing inefficient plate')
                return
            end
        end
        if required > item(cfg.TrainType) or total >= maxPlates then return end
        for k = #cfg.Require, 1, -1 do
            if (current[k] or 0) < (plan[k] or 0) then
                send('设置挡位', {Index = k, Count = 1})
                setStatus('Auto-equipped improved free weight plate')
                return
            end
        end
        return
    end
    local best = availableGear(cfg)
    local current = tonumber(val(lastMachine, 'TrainGear', 1)) or 1
    if best ~= current then
        send('设置挡位', {Index = best, Count = 1})
        setStatus(string.format('Auto-equipped best machine weight %d/%d', best, #cfg.Require))
    end
end
local function chooseAndStartTrain(targetStat)
    local model, cfg, _, why, approach, preparedRoute = chooseMachine(targetStat)
    if not model or not cfg then
        lastNoMachineReason = tostring(why or 'unknown selection failure')
        noMachineStreak += 1
        if throttle('missingMachine:'..tostring(targetStat), math.max(18, tonumber(state.MachineRetrySilence) or 35)) then
            problemOnce('missingMachine:'..tostring(targetStat), 'No reachable non-VIP machine: '..lastNoMachineReason, math.max(18, tonumber(state.MachineRetrySilence) or 35))
            setStatus('Cannot train now: '..lastNoMachineReason)
        end
        return false
    end
    if isVipMachine(model) then setStatus('Blocked VIP machine'); return end
    if isTraining() then
        send('退出训练')
        task.wait(0.32)
    end
    local position = approach or candidateTarget(model)
    if not position then return false end
    setStatus('Going to ' .. tostring(cfg.ZhName or model.Name))
    if not moveTo(position, 4, preparedRoute) then
        noMachineStreak += 1
        machineFails[model] = os.clock() + 18
        failedMachineStats[model] = 'movement or safety route rejected'
        return false
    end
    if not running or not state.Master or isCompeting() or hatchSession then return false end
    local owner = tonumber(val(model, 'OwnerID', 0)) or 0
    if owner ~= 0 and owner ~= player.UserId then
        noMachineStreak += 1
        machineFails[model] = os.clock() + 15
        failedMachineStats[model] = 'occupied by a different player on arrival'
        return false
    end
    local _, _, nearRoot = charReady()
    local promptPart = model:FindFirstChild('TiggerPart', true)
    local actualPrompt = promptPart and promptPart:IsA('BasePart') and promptPart.Position or candidateTarget(model)
    local distanceToPrompt = nearRoot and actualPrompt and (nearRoot.Position - actualPrompt).Magnitude or math.huge
    -- Most games enforce proximity for equipment. Don't blind-fire StartTrain when the
    -- safe spot is too far away; find a closer legitimate machine next attempt.
    if distanceToPrompt > 10 then
        noMachineStreak += 1
        failedMachineStats[model] = string.format('prompt too far: %.1f studs', distanceToPrompt)
        machineFails[model] = os.clock() + 35
        setStatus('Machine standing position is out of range; trying another free machine')
        return false
    end
    machineStartPending = model
    local expectedId = tonumber(val(model, 'EquipmentID', 0)) or -1
    local originalId = trainingId()
    send('StartTrain', model)
    local verifyUntil = os.clock() + math.clamp(tonumber(state.VerifyTrainingStartSeconds) or 1.7, 0.5, 4)
    local confirmed = false
    while running and state.Master and os.clock() < verifyUntil do
        local id = trainingId()
        local equippedName = tostring(val(player, 'EquipmentName', ''))
        local machineOwner = tonumber(val(model, 'OwnerID', 0)) or 0
        if id == expectedId and id ~= 0 and
            (equippedName == model.Name or machineOwner == player.UserId or
                (originalId == 0 and equippedName == '')) then
            confirmed = true
            break
        end
        task.wait(0.12)
    end
    machineStartPending = nil
    if confirmed and running and state.Master then
        lastMachine = model
        noMachineStreak = 0
        movementFailures = 0
        machineStarted, onMachineSince = os.clock(), os.clock()
        lastTrainingId = expectedId
        lastTrainingValue = item(cfg.TrainType)
        lastTrainingGainAt = os.clock()
        trainingBackoffUntil = 0
        setStatus('Training ' .. tostring(cfg.ZhName or model.Name))
        cooldowns.gear = 0
        adjustCurrentGear()
        return true
    else
        lastMachine = nil
        noMachineStreak += 1
        failedMachineStats[model] = string.format('start not confirmed (id=%d, owner=%s, name=%s)',
            trainingId(), tostring(val(model,'OwnerID',-1)), tostring(val(player,'EquipmentName','')))
        setStatus('Machine rejected training start; trying another ordinary machine')
        machineFails[model] = os.clock() + 45
        cooldowns.machineRetry = os.clock() + 4
        return false
    end
end
-- The treadmill has zero StaminaCost in all world configs and trains Bag[10]
-- without the normal Click remote (see native Training Click LocalScript).
local function handleEnergyRecovery()
    if not state.AutoRecovery or not state.Train then
        energyRecovery.active = false
        return false
    end
    local cur, maximum, ratio = energyValues()
    if not cur then
        if not energyUnavailableWarned then
            energyUnavailableWarned = true
            setStatus('Waiting for replicated CurStamina and MaxStamina; recovery guard idle')
        end
        energyRecovery.active = false
        return false
    end
    local cost = currentTrainingCost()
    -- Recovery also needs to start when loading the script already exhausted,
    -- or after competition/hatching leaves us off a training machine.
    if not energyRecovery.active and ratio <= math.clamp((tonumber(state.EnergyLowPercent) or 25) / 100, 0.05, 0.7) then
        beginEnergyRecovery('energy already below safe threshold')
    end
    if not energyRecovery.active and isTraining() and tonumber(equipmentConf[trainingId()] and equipmentConf[trainingId()].TrainType) ~= 10 then
        local floor = math.max(maximum * state.EnergyLowPercent / 100,
            cost * (1 + tonumber(state.EnergyClickReserve or 3)))
        if cur <= floor then beginEnergyRecovery('below lifting reserve') end
    end
    if not energyRecovery.active then return false end
    local now = os.clock()
    if now - energyRecovery.beganAt > (tonumber(state.NoEnergyTimeoutSeconds) or 110)
        and now - energyRecovery.lastImprovedAt > 45 then
        problemOnce('energyNeverRegenerates',
            'Energy has not regenerated after treadmill/rest attempts; keeping exercise paused instead of wasting clicks. Check game stamina mechanics.', 90)
        energyRecovery.phase = 'rest'
        energyRecovery.phaseSince = now
        energyRecovery.beganAt = now
    end
    if cur > energyRecovery.lastEnergy + math.max(0.05, maximum * 0.002) then
        energyRecovery.lastImprovedAt = now
    end
    energyRecovery.lastEnergy = cur
    energyRecovery.lastSeenAt = now
    local resume = math.max(math.clamp((tonumber(state.EnergyResumePercent) or 75) / 100, 0.3, 0.97),
        math.clamp((tonumber(state.EnergyLowPercent) or 25) / 100 + 0.18, 0.3, 0.97))
    if ratio >= resume then
        energyRecovery.active = false
        energyRecovery.phase = 'treadmill'
        lastTrainingGainAt = now
        cooldowns.machineRetry = now
        setStatus(string.format('Energy restored (%.0f%%); resuming smart training', ratio * 100))
        return false
    end
    -- Exit exhausted muscle equipment promptly, before stall recovery can penalize it.
    if isTraining() then
        local cfg = equipmentConf[trainingId()]
        if not cfg or tonumber(cfg.TrainType) ~= 10 then
            send('退出训练')
            lastMachine = nil
            onMachineSince = 0
            cooldowns.machineRetry = now
            setStatus(string.format('Energy %.0f%% - stopping lifts and switching to free treadmill', ratio * 100))
            return true
        end
        -- Treadmills are free of energy cost. If stamina does not rise on one,
        -- step off temporarily to let the server's passive recovery run.
        if now - energyRecovery.phaseSince >= tonumber(state.RecoveryTreadmillSeconds or 16)
            and now - energyRecovery.lastImprovedAt >= tonumber(state.RecoveryTreadmillSeconds or 16) then
            send('退出训练')
            lastMachine = nil
            energyRecovery.phase = 'rest'
            energyRecovery.phaseSince = now
            setStatus('Treadmill energy has not increased; resting off equipment')
        else
            setStatus(string.format('Recovering on treadmill: %.0f%% current energy', ratio * 100))
        end
        return true
    end
    if energyRecovery.phase == 'rest' then
        if now - energyRecovery.phaseSince < tonumber(state.RecoveryRestSeconds or 18) then
            setStatus(string.format('Resting for stamina regeneration: %.0f%%', ratio * 100))
            return true
        end
        energyRecovery.phase = 'treadmill'
        energyRecovery.phaseSince = now
    end
    if throttle('staminaMachineRetry', 8) then
        chooseAndStartTrain(10) -- same VIP checks, same travel protection
        energyRecovery.phaseSince = os.clock()
        if not isTraining() then
            energyRecovery.phase = 'rest'
            energyRecovery.phaseSince = os.clock()
            setStatus('No reachable normal treadmill; resting for energy instead')
        end
    end
    return true
end
local function recoverStalledTraining()
    if energyRecovery.active then return end
    if not isTraining() or not hasObject(lastMachine) then return end
    if tonumber(equipmentConf[trainingId()] and equipmentConf[trainingId()].TrainType) ~= 10 and not energyReadyForClick() then return end
    local cfg, id = machineConfig(lastMachine)
    if not cfg or isVipMachine(lastMachine) or id ~= trainingId() then return end
    local current = item(cfg.TrainType)
    if lastTrainingId ~= id then
        lastTrainingId, lastTrainingValue, lastTrainingGainAt = id,current,os.clock()
        return
    end
    if current > lastTrainingValue then
        lastTrainingValue, lastTrainingGainAt = current, os.clock()
        return
    end
    local stalledFor = os.clock() - lastTrainingGainAt
    if stalledFor > 42 then
        send('退出训练')
        machineFails[lastMachine] = os.clock() + 60
        lastMachine = nil
        lastTrainingGainAt = os.clock()
        setStatus('No confirmed training gain; changing normal machine')
        return
    end
    if stalledFor > 20 and os.clock() > trainingBackoffUntil and state.AutoGear then
        local index = tonumber(val(lastMachine,'TrainGear',1)) or 1
        if cfg.EquipmentType ~= 2 and index > 1 then
            send('设置挡位', {Index = index - 1, Count = 1})
        elseif cfg.EquipmentType == 2 then
            local idx = lastMachine:FindFirstChild('IndexVt')
            if idx then
                for i=#cfg.Require,1,-1 do
                    if tonumber(val(idx,tostring(i),0)) > 0 then
                        send('设置挡位', {Index = i, Count = -1})
                        break
                    end
                end
            end
        end
        trainingBackoffUntil = os.clock() + 13
        setStatus('Training stalled; testing lighter weight and confirming gains')
    end
end
local function canAutoRebirth()
    -- Avoid depending on a potentially decompiler-damaged helper implementation.
    -- The original game's RebirthData.IsCanRebirth checks exactly these six Bag IDs.
    local nextLevel = (tonumber(val(player, 'rebirthCount', 0)) or 0) + 1
    local cfg = rebirthConf[nextLevel]
    if not cfg or type(cfg.need) ~= 'table' then return false end
    for index, required in ipairs(cfg.need) do
        if item(index + 9) < (tonumber(required) or math.huge) then
            return false
        end
    end
    return true
end
local function rebirth()
    if not throttle('rebirth', 12) or not canAutoRebirth() then return end
    cancelTravel()
    if isTraining() then send('退出训练'); task.wait(0.2) end
    setStatus('Rebirthing: all stat requirements met')
    local result = invoke('重生')
    if result == true then
        lastMachine = nil; machineStarted = 0
        energyRecovery.active = false
        onMachineSince = 0
        fallbackTrainingStat, fallbackTrainingUntil = 0, 0
        machineFails = {}
        cooldowns.machineRetry = os.clock() + 3
    else
        setStatus('Rebirth request not accepted')
    end
end
local function advanceWorld()
    if not throttle('world', 12) or isCompeting() or busy or hatchSession then return end
    local max = bestUnlockedWorld()
    local target = max + 1
    if worldConf[target] and worldConf[target].IsPublic ~= 0 and currency() >= worldCost(target) and
       (tonumber(val(player:FindFirstChild('Record'), '解锁世界', 0)) or 0) >= target then
        if isTraining() then send('退出训练'); task.wait(0.2) end
        local success = invoke('解锁世界', target)
        if success == true then
            setStatus('Unlocked world ' .. tostring(target))
            max = target
        end
    end
    if max > world() and worldConf[max] and worldConf[max].IsPublic ~= 0 and not isCompeting() then
        if isTraining() then send('退出训练'); task.wait(0.2) end
        if invoke('世界传送', max) == true then
            lastMachine = nil
            machineStarted = 0
            machineFails = {}
            worldLast = max
            fallbackTrainingStat, fallbackTrainingUntil = 0, 0
            setStatus('Travelled to world ' .. tostring(max))
        end
    end
end

local function findEggPart(id)
    local scene = getScene()
    local functionFolder = scene and scene:FindFirstChild('Function')
    local hatch = functionFolder and functionFolder:FindFirstChild('Hatch Pet')
    if not hatch then return nil end
    for _, model in ipairs(hatch:GetChildren()) do
        local eggId = tonumber(val(model, 'EggId', -1)) or -1
        if eggId == id then
            local touch = model:FindFirstChild('TouchPart', true)
            if touch and touch:IsA('BasePart') then return touch.Position end
        end
    end
    return nil
end
local function getEggChoice()
    local worldId = world()
    -- Hatching must use an egg physically present in the CURRENT scene.
    -- Best-world selection cannot silently hatch eggs from another world.
    local cfg = worldConf[worldId]
    if not cfg then return nil end
    local budget = currency() * state.HatchBudgetPercent / 100
    local nextId = nextWorld()
    if nextId and currency() < worldCost(nextId) then
        budget = math.min(budget, math.max(0, currency() - math.min(worldCost(nextId) * 0.2, currency() * 0.8)))
    end
    local bestId, bestPrice = nil, -1
    for _, id in ipairs(cfg.EggVts or {}) do
        local egg = eggConf[id]
        if egg and tonumber(egg.cost) == 1 and (tonumber(egg.Price) or math.huge) <= budget then
            if tonumber(egg.Price) > bestPrice then bestId, bestPrice = id, tonumber(egg.Price) end
        end
    end
    return bestId
end
local function hatchEgg()
    if not throttle('hatch', math.max(2.3, tonumber(state.HatchInterval) or 2.5)) or isCompeting() or busy then return end
    if isTraining() then return end
    local id = getEggChoice()
    if not id then return end
    if not eggConf[id] or tonumber(eggConf[id].cost) ~= 1 then return end
    local price = tonumber(eggConf[id].Price) or math.huge
    if currency() < price then return end
    local target = findEggPart(id)
    if not target then
        -- Don't invoke blind egg remotes from a distant or unmapped location.
        setStatus('Egg ' .. tostring(id) .. ' not found in this world')
        return
    end
    if not moveTo(target, 9) then return end
    local drawUp = Tool:FindFirstChild('DrawUp')
    local drawMsg = drawUp and drawUp:FindFirstChild('Msg')
    local drawHero = drawMsg and drawMsg:FindFirstChild('DrawHero')
    if drawHero and drawHero:IsA('RemoteFunction') then
        local before = currency()
        return safe('egg hatch', function()
            local received = drawHero:InvokeServer(id, 1)
            actions += 1
            local success = type(received) == 'table' and next(received) ~= nil
            if success then
                setStatus('Successfully hatched egg ' .. tostring(id))
            elseif currency() < before then
                success = true -- server confirmed the charge, even if result could not be decoded
                setStatus('Egg purchase acknowledged ' .. tostring(id))
            else
                setStatus('Egg hatch rejected, inventory full, or server cooldown')
            end
            return success
        end) == true
    end
    return false
end

local function equipBest()
    if state.AutoPets and throttle('petEquip', 65) then send('装备最佳宠物') end
    if state.AutoEquipment and throttle('equipmentEquip', 85) then send('装备最佳装备') end
    if state.AutoFuse and throttle('petFuse', 170) then send('FuseAllPet') end
end
local function claimRewards()
    if state.Online and throttle('online', 40) then invoke('OnlineClaimAll') end
    if state.Daily and throttle('daily', 300) then invoke('领取每日奖励') end
    if state.Weekly and throttle('weekly', 300) then
        -- Weekly UI requests a server summary with HasUnclaimed, so don't
        -- repeatedly claim when nothing was earned.
        local info = invoke('GetWeeklyRewardInfo')
        if type(info) == 'table' and info.HasUnclaimed == true then
            if invoke('ClaimWeeklyReward') then setStatus('Claimed earned weekly reward') end
        end
    end
    if state.Spin and throttle('spin', 50) then
        -- The native Daily Lottery UI checks EnumMgr.ItemID.DailyToken before
        -- calling the zero-argument Spin RemoteFunction. This must not buy turns.
        local tokenId = EnumMgr and EnumMgr.ItemID and EnumMgr.ItemID.DailyToken
        local tokens = tokenId and tonumber(val(player:FindFirstChild('Bag'), tostring(tokenId), 0)) or 0
        if tokens and tokens > 0 then
            local server = RS:FindFirstChild('ServerMsg')
            local spin = server and server:FindFirstChild('Spin')
            if spin and spin:IsA('RemoteFunction') then
                local result, awardId, awardCount = safe('free daily spin', function()
                    return spin:InvokeServer()
                end)
                -- pcall helper returns only the first value; the first value is
                -- a verified lottery slot index when native UI accepts the spin.
                if result then
                    actions += 1
                    setStatus('Redeemed an owned free daily-spin token')
                end
            end
        end
    end
end
-- The Mail UI receives account mail in LocalData.Email and asks the server to
-- claim mail by ID. Claim only earned, unclaimed non-subscription mail; never
-- follow its paid "view subscriber mail" action.
local function claimMail()
    if not state.Mail or not throttle('mail', 35) then return end
    local snapshot = playerSnapshot()
    if type(snapshot) ~= 'table' or type(snapshot.Email) ~= 'table' then return end
    local choices = {}
    for id, mail in pairs(snapshot.Email) do
        local mailId = tonumber(id)
        if mailId and type(mail) == 'table' and mail.Claimed ~= true
            and tonumber(mail.Claimed or 0) ~= 1 and mail.Des ~= 'SubscriptionGift'
            and tostring(mail.Type or '') ~= 'SubscriptionGift' then
            choices[#choices+1] = mailId
        end
    end
    table.sort(choices)
    for _, id in ipairs(choices) do
        if (mailboxClaimedAttempt[id] or 0) < os.clock() then
            mailboxClaimedAttempt[id] = os.clock() + 180
            -- Claimed once at a time so the server can update the snapshot.
            local result = invoke('领取邮件奖励', id)
            if result then setStatus('Collected free/unclaimed mailbox reward ' .. id) end
            return
        end
    end
end

-- Native Store -> Code panel invokes ServerMsg.Code(code:upper()) and returns
-- accepted + status. Only auto-try the code on the current official game page.
-- Codes are server-controlled and can expire. Never sweep guessed codes.
local function redeemOfficialCode()
    if not state.RedeemCodes or not throttle('officialCodes', 300) then return end
    local server = RS:FindFirstChild('ServerMsg')
    local remote = server and server:FindFirstChild('Code')
    if not remote or not remote:IsA('RemoteFunction') then return end
    for _, code in ipairs({'SPACEFORCE'}) do
        if not codeAttempted[code] then
            codeAttempted[code] = true
            local ok, accepted, reason = pcall(function() return remote:InvokeServer(code) end)
            if ok then
                actions += 1
                if accepted then setStatus('Redeemed free official code ' .. code)
                end
            else
                -- Retry once on a later run when network/remote is healthy.
                codeAttempted[code] = nil
            end
            return
        end
    end
end

-- Time-limited event rewards. Never auto-enter event rooms, skip tasks,
-- purchase event-shop items or attempt a paid reward. Only free milestones
-- already recorded as COMPLETED and UNCLAIMED are claimed.
local function claimFreeEventRewards()
    if not state.EventRewards or not throttle('freeEvents', 40) then return end
    local now = os.time()
    local cfgRoot = RS:FindFirstChild('Global game configuration')
    local crossoverRoot = cfgRoot and cfgRoot:FindFirstChild('CrossoverEvent')
    local crossover = crossoverRoot and crossoverRoot:FindFirstChild('CrossoverEventConfig')
    if crossover and crossover:IsA('ModuleScript') then
        local conf = safe('crossover event config', function() return require(crossover) end)
        if type(conf) == 'table' and type(conf.EVENT_NAME) == 'string'
            and now >= (tonumber(conf.START_UNIX_TIMESTAMP) or math.huge)
            and now <= (tonumber(conf.END_UNIX_TIMESTAMP) or -1) then
            local tracker = player:FindFirstChild(conf.EVENT_NAME)
            for _, kind in ipairs({'BadgeTask', 'GYMTask'}) do
                local finished = tonumber(val(tracker, kind .. '_Complete', 0)) or 0
                local claimed = tonumber(val(tracker, kind .. '_Claimed', 0)) or 0
                local tag = conf.EVENT_NAME .. '_' .. kind
                if finished == 1 and claimed ~= 1 and (eventClaimAttempt[tag] or 0) < os.clock() then
                    eventClaimAttempt[tag] = os.clock() + 130
                    if invoke('CrossoverEventClaim', kind) then
                        setStatus('Claimed completed free crossover task ' .. kind)
                    end
                    return
                end
            end
        end
    end
    local halloween = cfgRoot and cfgRoot:FindFirstChild('Halloween Event')
    local start = tonumber(val(halloween, 'StartTime', math.huge)) or math.huge
    local finish = tonumber(val(halloween, 'EndTime', -1)) or -1
    if not halloween or now < start or now > finish then return end
    local online = tonumber(val(player, 'ChristmasEventOnline', 0)) or 0
    local snapshot = playerSnapshot()
    local claimed = type(snapshot) == 'table' and type(snapshot.HalloweenEvent) == 'table'
        and snapshot.HalloweenEvent.OnlineRecord or {}
    local rewards = safe('halloween online reward config',function()
        return Cfg.GetCfgByName('halloweeneventonlineConf')
    end)
    if type(rewards) ~= 'table' then return end
    for id, conf in pairs(rewards) do
        local n = tonumber(id)
        if n and type(conf) == 'table' and online >= (tonumber(conf.OnlinTime) or math.huge)
            and tonumber(claimed[tostring(n)] or claimed[n] or 0) ~= 1 then
            local tag = 'halloweenOnline_' .. n
            if (eventClaimAttempt[tag] or 0) < os.clock() then
                eventClaimAttempt[tag] = os.clock() + 200
                if invoke('领取万圣节活动在线奖励', n) == true then
                    setStatus('Claimed earned Halloween online milestone ' .. n)
                end
                return
            end
        end
    end
end

local function claimSeason()
    if not state.SeasonQuests or not throttle('season', 26) then return end
    local global = RS:FindFirstChild('Global game configuration')
    local event = global and global:FindFirstChild('Event')
    local season = event and event:FindFirstChild('SeasonQuest')
    local quests = season and season:FindFirstChild('Quests')
    local trackers = player:FindFirstChild('SeasonQuestTrackers')
    local claimed = trackers and trackers:FindFirstChild('ClaimedRewards')
    local remoteFolder = RS:FindFirstChild('Remotes')
    local questRemote = remoteFolder and remoteFolder:FindFirstChild('TryToClaimSeasonQuestReward')
    if not (quests and trackers and claimed and questRemote and val(season, 'IsActive', false) == true) then return end
    local seen = {}
    for id in tostring(claimed.Value or ''):gmatch('[^,]+') do seen[tonumber(id)] = true end
    local ids = {}
    for _, quest in ipairs(quests:GetChildren()) do
        local id = tonumber(quest.Name)
        local objective = val(quest, 'Objective', '')
        local name = val(quest, 'QuestName', '')
        local goal = tonumber(val(quest, 'Requirement', math.huge)) or math.huge
        local progress = tonumber(val(trackers, objective, -1)) or -1
        if id and goal > 0 and name ~= '' and not seen[id] and progress >= goal then
            ids[#ids+1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if not lastSeasonClaim[id] or os.clock() > lastSeasonClaim[id] then
            lastSeasonClaim[id] = os.clock() + 150
            local success = safe('claim season quest', function() return questRemote:InvokeServer(id) end)
            if success then actions += 1; setStatus('Claimed completed season quest '..id) end
            return -- one verified completed quest per cycle
        end
    end
end
local function claimAchievement()
    if not state.Achievements or not throttle('achievements', 35) then return end
    local snapshot = playerSnapshot()
    if type(snapshot) ~= 'table' or type(snapshot.Record) ~= 'table' or type(snapshot.Achieve) ~= 'table' then return end
    local ids = {}
    for id, cfg in pairs(achieveConf) do
        local metric = cfg.taskID and cfg.taskID[1]
        local requirement = cfg.taskCount and tonumber(cfg.taskCount[1])
        local progress = metric and tonumber(snapshot.Record[metric])
        local already = snapshot.Achieve[tostring(id)]
        if requirement and progress and progress >= requirement and already ~= 1 and already ~= true then
            ids[#ids+1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if throttle('achievement_' .. tostring(id), 165) then
            local result = invoke('领取成就奖励', id)
            if result == true then setStatus('Claimed achievement '..id) end
            return
        end
    end
end
local function claimPetMission()
    if not state.PetMission or not throttle('petMission', 45) then return end
    local global = RS:FindFirstChild('Global game configuration')
    local mission = global and global:FindFirstChild('Pet mission')
    local progress = player:FindFirstChild('宠物任务')
    if not (mission and progress) then return end
    local reqOnline = tonumber(val(mission, 'online time', math.huge)) or math.huge
    local missions = mission:FindFirstChild('Quests')
    local questName = val(player, 'CurrentPetQuest', '')
    local reqTraining = tonumber(val(missions, questName, math.huge)) or math.huge
    if tonumber(val(progress, 'online time', 0)) >= reqOnline
        and tonumber(val(progress, 'Training', 0)) >= reqTraining then
        local success = invoke('领取宠物任务奖励')
        if success == true then setStatus('Claimed completed pet mission reward') end
    end
end
local function claimPetIndexRewards()
    if not state.PetIndexRewards or not throttle('petIndexReward', 120) then return end
    local snapshot = playerSnapshot()
    if not snapshot or type(snapshot.IndexClaimed) ~= 'table' then return end
    local unlocked = tonumber(val(player, 'UnLockHeroNum', 0)) or 0
    for tier, cfg in ipairs(indexRewardConf) do
        if unlocked >= (tonumber(cfg.Need) or math.huge)
            and snapshot.IndexClaimed[tier] ~= 1
            and snapshot.IndexClaimed[tostring(tier)] ~= 1 then
            send('领取图鉴奖励')
            setStatus('Claiming earned pet index milestone(s)')
            return
        end
    end
end
local function claimCollectionRewards()
    if not state.CollectionRewards or not throttle('petCollectionReward', 38) then return end
    local snapshot = playerSnapshot()
    if not snapshot or type(snapshot.Record) ~= 'table' then return end
    local record = snapshot.Record
    local already = {}
    for _, entry in ipairs(record.ClaimedCollections or {}) do
        if type(entry) == 'table' then
            local collection = tonumber(entry[1]); local level = tonumber(entry[2])
            if collection and level then
                already[collection] = already[collection] or {}
                already[collection][level] = true
            end
        end
    end
    local remotes = RS:FindFirstChild('Remotes')
    local remote = remotes and remotes:FindFirstChild('TryClaimingCollectionReward')
    if not remote or not remote:IsA('RemoteFunction') then return end
    local ids = {}
    for _, config in pairs(eggCollectionConf) do
        if type(config) == 'table' and tonumber(config.EggId) then
            ids[#ids+1] = tonumber(config.EggId)
        end
    end
    table.sort(ids)
    local eligibleEggs = {}
    for _, wc in pairs(worldConf) do
        for _, eggId in ipairs(wc.EggVts or {}) do eligibleEggs[eggId] = true end
    end
    for _, eggId in ipairs(ids) do
        local egg = eggConf[eggId]
        if eligibleEggs[eggId] and egg and tonumber(egg.cost) == 1 then
            local petIds = egg.ItemIDVt
            if type(petIds) == 'table' and #petIds > 0 then
                for level = 1, 4 do
                    if not (already[eggId] and already[eggId][level]) then
                        local complete = true
                        for _, base in ipairs(petIds) do
                            local petId = (tonumber(base) or -1000000) + (level - 1) * 100000
                            if record[tostring(petId)] == nil and record[petId] == nil then
                                complete = false
                                break
                            end
                        end
                        if complete and throttle('collection_'..eggId..'_'..level, 180) then
                            local success = safe('pet collection', function()
                                return remote:InvokeServer(eggId, level)
                            end)
                            if success then
                                actions += 1
                                setStatus('Claimed completed free-egg collection '..eggId..' tier '..level)
                            end
                            return
                        end
                        break -- claim sequentially, never skip an earlier unclaimed tier
                    end
                end
            end
        end
    end
end
local function ownedCoaches()
    local snapshot = playerSnapshot()
    local result = {}
    if type(snapshot) ~= 'table' or type(snapshot.Bag) ~= 'table' then return result end
    for _, entry in pairs(snapshot.Bag) do
        if type(entry) == 'table' and tonumber(entry.tp) == 8 and tonumber(entry.id)
            and coachConf[tonumber(entry.id)] then
            result[tonumber(entry.id)] = entry
        end
    end
    return result
end
local function coachScore(cfg)
    local score = 0
    for i, tp in ipairs(cfg.CoachBuffType or {}) do
        local amount = tonumber(cfg.CoachBuffNumber and cfg.CoachBuffNumber[i]) or 0
        if tp == 1 then score += amount * 1.1
        elseif tp == 2 then score += amount
        elseif tp == 3 then score += amount * 0.75
        elseif tp == 6 then score += amount * 0.6
        elseif tp == 4 then score += amount * 0.2 end
    end
    return score
end
local function autoCoach()
    if not state.Coach or not throttle('coach', 80) then return end
    local owns = ownedCoaches()
    local best, bestScore, currently = nil, -math.huge, nil
    for id, entry in pairs(owns) do
        local cfg = coachConf[id]
        if cfg and cfg.IsEnabled ~= 0 then
            local score = coachScore(cfg)
            if score > bestScore then best, bestScore = id, score end
            if tonumber(entry.using) == 1 then
                currently = math.max(currently or -math.huge, score)
            end
        end
    end
    if best and (not currently or bestScore > currently) and tonumber(owns[best].using) ~= 1 then
        invoke('装备教练', best)
        setStatus('Equipping best owned free/earned coach '..best)
    end
    if not state.BuyFreeCoaches then return end
    -- Only normal-money coaches whose prerequisite is already completed.
    local bestBuy, bestGain, bestPrice = nil, 0, 0
    for id, cfg in pairs(coachConf) do
        if cfg.IsEnabled ~= 0 and not owns[id] and tonumber(cfg.UnlockCoinType) == 1 then
            local price = tonumber(cfg.UnlockCoinNumber) or math.huge
            if price > 0 and price <= currency() * 0.03 then
                local taskReady = GetDataModule and safe('coach prerequisite',function()
                    return GetDataModule.IsFinishUnlockTask(player,cfg.UnlockType,cfg.UnlockTypeNumber,false)
                end)
                local improvement = coachScore(cfg) - math.max(0,currently or 0)
                if taskReady == true and improvement > bestGain then
                    bestBuy,bestGain,bestPrice = id,improvement,price
                end
            end
        end
    end
    if bestBuy and throttle('coachBuy', 300) then
        local ok = invoke('解锁教练', bestBuy)
        if ok == true then setStatus('Unlocked earned-money coach '..bestBuy) end
    end
end
local function useOwnedPotions()
    if not state.Potion or not throttle('potions', 35) then return end
    local buffs = player:FindFirstChild('BUFF')
    if not buffs then return end
    -- Buff values store remaining duration; never waste a potion while active.
    for _, id in ipairs({101, 201, 301, 501}) do
        local count = item(id)
        if count > (tonumber(state.PotionReserve) or 1) and buffConf[id] then
            local active = tonumber(val(buffs, tostring(id), 0)) or 0
            if active <= 0 then
                send('使用药水', id)
                setStatus('Activated owned, inactive potion '..id)
                return
            end
        end
    end
end

local function championCleared()
    local r = player:FindFirstChild('Record')
    return (tonumber(val(r, 'GymChampion', 0)) or 0) >= world()
end
local function playerCompetitionPower()
    local power = 0
    for id = 11, 15 do power += math.max(0, item(id)) end
    return power
end
local function competitionReadiness()
    local worldId = world()
    local cfg = worldConf[worldId]
    if not cfg or type(cfg.Enemys) ~= 'table' or #cfg.Enemys == 0 then
        return false, 'No opponent configuration', 0, 0, 0
    end
    local strongest, opponentName, enemyArray = 0, '', nil
    for _, enemyId in ipairs(cfg.Enemys) do
        local e = enemyConf[tonumber(enemyId)]
        if not e or type(e.Ability) ~= 'table' or #e.Ability < 5 then
            return false, 'Opponent ability data missing', 0, 0, 0
        end
        local sum = 0
        for i = 1, 5 do sum += (tonumber(e.Ability[i]) or 0) end
        if sum > strongest then
            strongest, opponentName, enemyArray = sum, tostring(e.ZhName or enemyId), e.Ability
        end
    end
    if strongest <= 0 or not enemyArray then
        return false, 'Opponent has no comparable power', 0, 0, 0
    end
    local power = playerCompetitionPower()
    local lossPenalty = math.min(130, (contestLosses[worldId] or 0) * state.CompetitionLossGrowth)
    local margin = (math.clamp(tonumber(state.CompetitionPowerMargin) or 145, 105, 300) + lossPenalty)/100
    local target = math.max(strongest * margin, contestMinPower[worldId] or 0)
    local statFloor = math.clamp(tonumber(state.CompetitionStatFloor) or 70, 0, 100)/100
    local weak = {}
    -- Check all rivals, not only the rival with the greatest total. Some
    -- opponents have highly specialised muscle stats even at lower totals.
    local maxByMuscle = {0,0,0,0,0}
    for _, enemyId in ipairs(cfg.Enemys) do
        local e = enemyConf[tonumber(enemyId)]
        if e and type(e.Ability) == 'table' then
            for i = 1, 5 do
                maxByMuscle[i] = math.max(maxByMuscle[i], tonumber(e.Ability[i]) or 0)
            end
        end
    end
    for i = 1, 5 do
        if maxByMuscle[i] > 0 and item(i + 10) < maxByMuscle[i] * statFloor then
            weak[#weak+1] = i
        end
    end
    if power < target or #weak > 0 then
        return false, string.format('Need %.3g power + stats for %s (have %.3g)',target,opponentName,power),power,target,#weak
    end
    return true, string.format('Power %.3g > target %.3g vs %s',power,target,opponentName),power,target,0
end
local function competitionOutcomeTick()
    if not contestByUs then return end
    if isCompeting() then
        contestStarted = true
        return
    end
    if not contestStarted then
        if os.clock() - lastContestStartedAt > 12 then
            contestByUs = false
            nextCompetitionAt = os.clock() + 80
            setStatus('Competition entry was not accepted; training instead')
        end
        return
    end
    -- The only authoritative progress signal in the place dump is GymChampion.
    -- On a world-clear run, a missing champion update is treated conservatively
    -- as an unsuccessful attempt; we do not assume 1st place from a click count.
    if os.clock() < lastContestStartedAt + 18 then return end
    contestByUs, contestStarted = false, false
    local championNow = tonumber(val(player:FindFirstChild('Record'), 'GymChampion', 0)) or 0
    if championNow >= contestWorld and championNow > contestChampionAtEntry then
        contestLosses[contestWorld] = 0
        contestMinPower[contestWorld] = 0
        nextCompetitionAt = os.clock() + state.CompetitionInterval
        setStatus('Champion defeated! Returning to world progression')
    elseif contestChampionAtEntry < contestWorld then
        contestLosses[contestWorld] = math.min(5, (contestLosses[contestWorld] or 0) + 1)
        -- A new attempt requires MATERIAL strength growth and a stronger estimate.
        contestMinPower[contestWorld] = contestPowerAtEntry * (1 + 0.16*contestLosses[contestWorld])
        nextCompetitionAt = os.clock() + math.max(120, state.CompetitionInterval)
        setStatus('Competition did not clear champion; increasing win threshold')
    else
        nextCompetitionAt = os.clock() + state.CompetitionInterval
    end
end
local function compete()
    if isCompeting() or busy or hatchSession then return end
    if energyRecovery.active or not state.Competition or os.clock() < nextCompetitionAt or contestByUs then return end
    -- Native auto-compete can independently queue unwanted losses.
    local auto = player:FindFirstChild('是否自动比赛')
    if auto and auto:IsA('BoolValue') and auto.Value then auto.Value = false end
    if state.CompeteForWorld and championCleared() then
        nextCompetitionAt = os.clock() + 120
        return
    end
    local ready, message, power = competitionReadiness()
    if not ready then
        nextCompetitionAt = os.clock() + 22
        setStatus('Skipping risky competition: '..message)
        return
    end
    if isTraining() then send('退出训练'); task.wait(0.3) end
    if not running or not state.Master or isTraining() or isCompeting() then return end
    contestWorld = world()
    contestPowerAtEntry = power
    contestChampionAtEntry = tonumber(val(player:FindFirstChild('Record'), 'GymChampion', 0)) or 0
    contestByUs, contestStarted = true, false
    lastContestStartedAt = os.clock()
    send('参加比赛')
    cooldowns.competitionPending = os.clock() + 9
    nextCompetitionAt = os.clock() + math.max(70, tonumber(state.CompetitionInterval) or 115)
    setStatus('Entering predicted winnable competition: ' .. message)
end

local function startLoop(name, intervalFn, callback)
    task.spawn(function()
        local consecutiveFailures, nextRetry = 0, 0
        while running do
            if state.Master and os.clock() >= nextRetry then
                -- Isolate failures by loop: a broken optional rewards API must
                -- not starve training, competition, stamina recovery or the UI.
                local ok, errorMessage = pcall(callback)
                if ok then
                    consecutiveFailures = 0
                    nextRetry = 0
                else
                    errors += 1
                    lastError = tostring(name) .. ': ' .. tostring(errorMessage)
                    consecutiveFailures += 1
                    local delay = math.min(60, 2 ^ math.min(6, consecutiveFailures))
                    nextRetry = os.clock() + delay
                    problemOnce('loopError_' .. name,
                        string.format('%s loop failed (%d times); retry in %ds: %s',
                            name, consecutiveFailures, delay, tostring(errorMessage)), 35)
                end
            end
            local okInterval, desiredInterval = pcall(intervalFn)
            task.wait(math.max(0.05, okInterval and tonumber(desiredInterval) or 1))
        end
    end)
end

-- Highest-priority cadence: use the game's own normal click remotes.
startLoop('training clicks', function() return 1 / math.clamp(state.TrainClicksPerSecond, 2, 12) end, function()
    if not state.Train or isCompeting() or not isTraining() then return end
    -- Fail closed: only click a verified, ordinary machine that belongs
    -- to the current training session.
    if not lastMachine or not hasObject(lastMachine) or isVipMachine(lastMachine) then return end
    if trainingId() ~= (tonumber(val(lastMachine, 'EquipmentID', 0)) or -1) then return end
    local cfg = equipmentConf[trainingId()]
    if not cfg or tonumber(cfg.TrainType) == 10 then return end
    local _, hum = charReady()
    if not hum or val(player, 'CanClick', false) ~= true then return end
    if not energyReadyForClick() then return end
    local now = os.clock()
    local _, _, fraction = energyValues()
    -- Reduce click pressure near the recovery threshold, instead of exhausting the bar.
    local cap = math.clamp(tonumber(state.TrainClicksPerSecond) or 10, 2, 12)
    if fraction and state.AutoRecovery then
        if fraction < 0.40 then cap = math.min(cap, 2)
        elseif fraction < 0.65 then cap = math.min(cap, 5) end
    end
    if now - lastTrainClickAt < 1 / cap then return end
    lastTrainClickAt = now
    Click:FireServer()
    actions += 1
end)
startLoop('competition clicks', function() return 1 / math.clamp(state.CompetitionClicksPerSecond, 2, 10) end, function()
    if state.Competition and isCompeting() then
        local _, hum = charReady()
        -- Source-native autoplay sends while competition is active, without
        -- limiting clicks to hard-coded stage numbers (which may change).
        if hum and hum.Health > 0 then
            CompetitionClick:FireServer('常规')
            actions += 1
        end
    end
end)
startLoop('progression', function() return 2.3 end, function()
    competitionOutcomeTick()
    controlNativeAutoClick(state.Train) -- avoid overlapping native training clicks
    if state.Competition then
        local auto = player:FindFirstChild('是否自动比赛')
        if auto and auto:IsA('BoolValue') and auto.Value then auto.Value = false end
    end
    -- A previously active egg session must not trap us in recovery forever.
    if hatchSession and energyRecovery.active then
        hatchSession = false
        nextHatchSession = os.clock() + 45
    end
    if isCompeting() or contestByUs or busy or hatchSession or os.clock() < (cooldowns.competitionPending or 0) then return end
    if handleEnergyRecovery() then return end -- recovery owns movement, training and entry
    if state.World then advanceWorld() end
    recoverStalledTraining()
    if energyRecovery.active then return end
    local championPending = state.ChampionFirst and state.Competition and state.CompeteForWorld
        and not championCleared()
    if state.Rebirth and canAutoRebirth() and not championPending then rebirth(); return end
    if state.Competition and not isCompeting() and os.clock() >= nextCompetitionAt then
        compete()
        if isCompeting() then return end
    end
    if state.Train then
        local target = desiredMuscle()
        -- Keep a working fallback machine long enough to gain a useful amount.
        -- Otherwise a blocked chest machine forces a machine swap every tick.
        if fallbackTrainingStat > 0 and os.clock() < fallbackTrainingUntil then
            target = fallbackTrainingStat
        elseif fallbackTrainingStat > 0 then
            fallbackTrainingStat = 0
            fallbackTrainingUntil = 0
        end
        if needsMoreStaminaCapacity(target) then
            target = 10
            setStatus('Increasing max stamina on normal treadmill for energy-efficient lifts')
        end
        -- Stat choice always includes endurance when the next rebirth requires it.
        if isTraining() and lastMachine and hasObject(lastMachine) then
            local cfg = machineConfig(lastMachine)
            if isVipMachine(lastMachine) then
                send('退出训练')
                lastMachine = nil
                machineStarted = 0
                setStatus('Left VIP equipment; selecting normal machine')
                return
            end
            if cfg then
                local held = os.clock() - onMachineSince
                local curStat = tonumber(cfg.TrainType)
                local nextCfg = rebirthConf[(tonumber(val(player, 'rebirthCount', 0)) or 0) + 1]
                local curNeed = nextCfg and nextCfg.need and tonumber(nextCfg.need[curStat - 9])
                if curStat == target or
                   (held < math.max(state.ReselectSeconds, state.MinTrainingSession) and
                    (not curNeed or item(curStat) < curNeed)) then
                    adjustCurrentGear()
                    return
                end
            end
        elseif isTraining() and not lastMachine then
            local cfg = equipmentConf[trainingId()]
            local currentName = val(player, 'EquipmentName', '')
            local current = equipmentFolder() and equipmentFolder():FindFirstChild(tostring(currentName))
            if current and isVipMachine(current) then
                send('退出训练')
                setStatus('Exited VIP machine')
                return
            end
            if cfg and tonumber(cfg.TrainType) == target and current and not isVipMachine(current) then
                lastMachine = current
                machineStarted = os.clock()
                onMachineSince = os.clock()
                lastTrainingId = trainingId()
                lastTrainingValue = item(target)
                lastTrainingGainAt = os.clock()
                adjustCurrentGear()
                return
            end
        end
        if throttle('machineRetry', 3) then
            local trained = chooseAndStartTrain(target)
            if not trained and state.FallbackMuscleTraining and noMachineStreak >= 2 and target ~= 10 then
                -- Other required attributes can still improve. Do not accidentally
                -- choose a VIP machine to rescue a failing muscle target.
                local alternatives = {12,13,14,15,10,11}
                local nextCfg = rebirthConf[(tonumber(val(player, 'rebirthCount', 0)) or 0) + 1]
                for _, statId in ipairs(alternatives) do
                    if statId ~= target and (statId ~= 10 or state.StaminaTraining) then
                        local required = nextCfg and nextCfg.need and tonumber(nextCfg.need[statId-9])
                        if not required or item(statId) < required then
                            local _, cfg = chooseMachine(statId)
                            if cfg and chooseAndStartTrain(statId) then
                                fallbackTrainingStat = statId
                                fallbackTrainingUntil = os.clock() + math.max(48, tonumber(state.MinTrainingSession) or 42)
                                setStatus('Training alternative stat '..statId..' while ordinary stat '..target..' machines are unavailable')
                                break
                            end
                        end
                    end
                end
            end
        end
    elseif isTraining() and throttle('leaveTraining', 5) then
        send('退出训练')
    end
end)
startLoop('pet and equipment', function() return 5 end, function()
    equipBest()
    autoCoach()
end)
startLoop('rewards', function() return 8 end, function()
    if not state.AutoRewards then return end
    claimRewards()
    claimAchievement()
    claimSeason()
    claimPetMission()
    claimPetIndexRewards()
    claimCollectionRewards()
    claimMail()
    claimFreeEventRewards()
    redeemOfficialCode()
    useOwnedPotions()
end)
startLoop('eggs', function() return 1.2 end, function()
    if not state.Hatch then
        hatchSession = false
        nextHatchSession = os.clock() + 60
        return
    end
    if energyRecovery.active then
        hatchSession = false
        nextHatchSession = os.clock() + 45
        return
    end
    if isCompeting() or contestByUs or busy or os.clock() < nextHatchSession or os.clock() < (cooldowns.competitionPending or 0) then return end
    if (cooldowns.hatch or 0) > os.clock() then return end
    if not hatchSession then
        if isTraining() and (os.clock() - onMachineSince) < math.max(20, tonumber(state.MinTrainingSession) or 42) then
            nextHatchSession = os.clock() + 25
            return
        end
        if not getEggChoice() then nextHatchSession = os.clock() + 35; return end
        hatchSession = true
        hatchSessionCount = 0
    end
    if isTraining() then
        send('退出训练')
        task.wait(0.3)
    end
    local result = hatchEgg()
    if result then hatchSessionCount += 1 end
    if hatchSessionCount >= 4 or not result or not getEggChoice() then
        hatchSession = false
        nextHatchSession = os.clock() + 125
        lastMachine = nil
        machineStarted = 0
    end
end)

local PuckUILink = 'https://raw.githubusercontent.com/PuckAFK/Puck-Loader/refs/heads/main/ui/PuckUI.lua'
local okUi, uiValue = pcall(function()
    return loadstring(game:HttpGet(PuckUILink))()
end)
if not okUi or type(uiValue) ~= 'table' then
    running = false
    warn('[PuckAFK Gym Star] Unable to load PuckUI:', uiValue)
    return
end
ui = uiValue
window = ui:CreateWindow({
    Name = 'PuckAFK Gym Star',
    Title = 'Gym Star Simulator | Smart Autofarm',
    Width = 450, Height = 510,
    GuiName = 'PuckAFK_GymStar_UI',
    ConfigId = 'Gym_Star_Simulator',
    Configs = {AutoSave = true, AutoLoad = true},
    DisableBuiltInConfigs = true, -- Use our simple Configs tab; keep built-in raw JSON hidden.
})

local function tab(name)
    local t = window:CreateTab(name)
    return t
end
local function toggle(t, key, name, note)
    t:CreateToggle({Name = name, Flag = 'GymStar_' .. key, CurrentValue = state[key],
        Callback = function(value)
            state[key] = value == true
            if key == 'AutoResume' and resumeControl then
                resumeControl.Enabled = state.AutoResume
            end
            if note and value then notify('Gym Star', note) end
            if (key == 'Master' and not value) or (key == 'Train' and not value) then
                controlNativeAutoClick(false)
                energyRecovery.active = false
                cancelTravel()
                if isTraining() then send('退出训练') end
                lastMachine = nil
                setStatus('Paused and left training')
            end
        end})
end
local function slider(t, key, name, minimum, maximum, increment, suffix)
    t:CreateSlider({Name=name,Flag='GymStar_'..key,Range={minimum,maximum}, Increment=increment,
        Suffix=suffix or '',CurrentValue=state[key],Callback=function(value) state[key]=value end})
end
local function dropdown(t, key, name, options)
    t:CreateDropdown({Name=name, Flag='GymStar_'..key,Options=options,CurrentOption={state[key]},
        Callback=function(opt) state[key] = type(opt) == 'table' and opt[1] or opt end})
end
local function button(t, name, callback)
    t:CreateButton({Name=name,Callback=function() safe('button '..name, callback) end})
end

local function unload()
    if not running then return end
    if isTraining() then pcall(function() send('退出训练') end) end
    controlNativeAutoClick(false)
    energyRecovery.active = false
    if resumeControl then
        resumeControl.Enabled = false
        resumeControl:Disconnect()
    end
    -- Stop automation before tearing down UI, and discard any future teleport hook.
    running = false
    state.Master = false
    cancelTravel()
    for _, conn in ipairs(signals) do pcall(function() conn:Disconnect() end) end
    table.clear(signals)
    if shared.PuckAFK_GymStar_Instance and shared.PuckAFK_GymStar_Instance.Unload == unload then
        shared.PuckAFK_GymStar_Instance = nil
    end
    -- PuckUI:Destroy flushes pending config changes and disconnects its UI handlers.
    pcall(function()
        if window and type(window.Destroy) == 'function' then
            window:Destroy()
        elseif window and window.ScreenGui then
            window.ScreenGui:Destroy()
        end
    end)
end

-- Beginner-facing interface: only useful everyday choices are exposed.
-- The legacy individual reward/coach/safety switches remain internal so none
-- of the already-implemented systems have to be removed or rewritten.
local home = tab('Home')
home:CreateSection('Smart Autofarm')
toggle(home, 'Master', 'Enable Smart Autofarm')
activityLabel = home:CreateLabel('Status: Paused')
worldLabel = home:CreateLabel('World: loading...')
statsLabel = home:CreateLabel('Stamina: loading...')
home:CreateLabel('Trains, manages stamina, upgrades weights and progresses automatically.')
home:CreateLabel('Automatically avoids identified VIP and paid areas.')
home:CreateSection('Quick Action')
button(home, 'Equip Best Pets & Gear Now', function()
    send('装备最佳宠物')
    send('装备最佳装备')
    notify('Gym Star', 'Equipping your best available pets and equipment')
end)
button(home, 'Claim Available Free Rewards', function()
    if busy or isCompeting() then
        notify('Gym Star', 'Wait until the current activity finishes')
        return
    end
    claimRewards()
    claimAchievement()
    claimSeason()
    claimPetMission()
    claimPetIndexRewards()
    claimCollectionRewards()
    claimMail()
    claimFreeEventRewards()
    notify('Gym Star', 'Checked available free rewards')
end)

local farm = tab('Autofarm')
farm:CreateSection('Training')
toggle(farm, 'Train', 'Auto Train')
toggle(farm, 'AutoGear', 'Auto Equip Best Weights')
toggle(farm, 'AutoRecovery', 'Auto Recover Stamina')
farm:CreateSection('Progression')
toggle(farm, 'World', 'Auto Unlock Worlds')
toggle(farm, 'Competition', 'Smart Competitions')
toggle(farm, 'Rebirth', 'Auto Rebirth', 'Rebirth resets your training stats.')
farm:CreateSection('Pets & Rewards')
toggle(farm, 'AutoPets', 'Equip Best Pets')
toggle(farm, 'AutoEquipment', 'Equip Best Equipment')
toggle(farm, 'Hatch', 'Auto Hatch Eggs')
toggle(farm, 'AutoRewards', 'Claim Free Rewards')

local settings = tab('Settings')
settings:CreateSection('Preferences')
dropdown(settings, 'Balanced', 'Training Focus',
    {'Rebirth Needs','Balanced','Stamina','Chest','Abs','Back','Arms','Legs'})
toggle(settings, 'StaminaTraining', 'Train Stamina for Rebirth')
slider(settings, 'CompetitionPowerMargin', 'Competition Safety', 125, 230, 5, '%')
slider(settings, 'HatchBudgetPercent', 'Egg Spending Limit', 1, 30, 1, '%')
settings:CreateSection('Movement')
dropdown(settings, 'MoveMode', 'Movement', {'Tween','Walk','None'})
slider(settings, 'TweenSpeed', 'Tween Speed', 20, 130, 5, ' studs/s')
settings:CreateLabel('VIP and paid-area avoidance stays enabled automatically.')
settings:CreateSection('Server Rejoins')
toggle(settings, 'AutoResume', 'Auto Resume After Server Change')
if resumeControl.Supported then
    settings:CreateLabel('Resumes automatically after teleports within Gym Star.')
else
    settings:CreateLabel('Auto resume unavailable: executor has no teleport queue.')
end
settings:CreateSection('Unload')
settings:CreateLabel('Stop all farming and close PuckUI. Settings are saved first.')
button(settings, 'Unload Script', unload)
window.CloseCallback = unload -- X also stops the autofarm rather than leaving a hidden running script.

-- Simple, fully functional profile manager. The native Configs tab is disabled
-- only to hide its raw JSON import/export UI; the same PuckUI persistence API
-- handles these controls. Profile selection does NOT switch the active autosave
-- target until Load or Save is actually pressed (prevents accidental overwrite).
local configsTab = tab('Configs')
configsTab:CreateSection('Saved Profiles')
local config = window.Config
local chosenProfile = config and config.Selected or 'default'
local pendingNewProfile = ''
local deleteCandidate = nil
local deleteDeadline = 0
local configInfo = configsTab:CreateLabel('Current profile: ' .. tostring(chosenProfile))
configsTab:CreateLabel(config and config.Persistent
    and 'Profiles save to your executor files automatically.'
    or 'Your executor supports session-only configs; profiles may not survive a rejoin.')

local function profileNames()
    if window and type(window._ListConfigProfiles) == 'function' then
        return window:_ListConfigProfiles()
    end
    return { 'default' }
end

local profilePicker = configsTab:CreateDropdown({
    Name = 'Select Saved Profile', Options = profileNames(),
    CurrentOption = {chosenProfile}, NoConfig = true,
    Callback = function(option)
        local name = type(option) == 'table' and option[1] or option
        if name ~= nil and tostring(name) ~= '' then
            chosenProfile = tostring(name)
            deleteCandidate = nil
        end
    end,
})

local function refreshProfiles(selectActive)
    local list = profileNames()
    if profilePicker and profilePicker.Refresh then
        profilePicker:Refresh(list)
        local wanted = selectActive and config and config.Selected or chosenProfile
        if not table.find(list, wanted) then wanted = list[1] or 'default' end
        profilePicker:Set(wanted)
    end
    if configInfo and configInfo.Set then
        configInfo:Set('Current profile: ' .. tostring(config and config.Selected or 'default'))
    end
end

configsTab:CreateSection('Save & Load')
button(configsTab, 'Save Current Profile', function()
    if not config or type(window._WriteConfig) ~= 'function' then
        notify('Gym Star', 'Profile saving is unavailable')
        return
    end
    local saved = window:_WriteConfig(config.Selected, true)
    if not saved then notify('Gym Star', 'Could not write the current profile') end
    refreshProfiles(true)
end)
button(configsTab, 'Load Selected Profile', function()
    if not config or type(window._ReadConfig) ~= 'function' then
        notify('Gym Star', 'Profile loading is unavailable')
        return
    end
    if window:_ReadConfig(chosenProfile, true) then
        refreshProfiles(true)
    end
end)

configsTab:CreateSection('Create Profile')
configsTab:CreateInput({
    Name = 'New Profile Name', CurrentValue = '', PlaceholderText = 'e.g. My Settings',
    NoConfig = true,
    Callback = function(value) pendingNewProfile = tostring(value or '') end,
})
button(configsTab, 'Create & Save Profile', function()
    local clean = tostring(pendingNewProfile):gsub('^%s+', ''):gsub('%s+$', '')
        :gsub('[^%w_%-]', '_'):sub(1, 48)
    if clean == '' then
        notify('Gym Star', 'Enter a profile name first')
        return
    end
    if window:_WriteConfig(clean, true) then
        chosenProfile = config.Selected
        refreshProfiles(true)
    end
end)
button(configsTab, 'Refresh Profile List', function()
    refreshProfiles(false)
    notify('Gym Star', 'Profile list refreshed')
end)

configsTab:CreateSection('Automatic Saving')
configsTab:CreateToggle({
    Name = 'Auto Save Settings', NoConfig = true,
    CurrentValue = config and config.AutoSave == true,
    Callback = function(value)
        if not config then return end
        config.AutoSave = value == true
        if type(window._SaveConfigMeta) == 'function' then window:_SaveConfigMeta() end
        if config.AutoSave and config.Ready and type(window._WriteConfig) == 'function' then
            window:_WriteConfig(config.Selected, false)
        end
    end,
})
configsTab:CreateToggle({
    Name = 'Auto Load Settings', NoConfig = true,
    CurrentValue = config and config.AutoLoad == true,
    Callback = function(value)
        if not config then return end
        config.AutoLoad = value == true
        if type(window._SaveConfigMeta) == 'function' then window:_SaveConfigMeta() end
    end,
})
configsTab:CreateLabel('Auto Load applies your selected profile on the next execution.')

configsTab:CreateSection('Delete Profile')
configsTab:CreateLabel('Select a profile above. Deletion requires pressing twice.')
button(configsTab, 'Delete Selected Profile', function()
    if chosenProfile == 'default' then
        notify('Gym Star', 'Default profile cannot be deleted here')
        return
    end
    local now = os.clock()
    if deleteCandidate ~= chosenProfile or now > deleteDeadline then
        deleteCandidate = chosenProfile
        deleteDeadline = now + 8
        notify('Gym Star', 'Press Delete again within 8 seconds to confirm')
        return
    end
    deleteCandidate = nil
    if window:_DeleteConfig(chosenProfile) then
        chosenProfile = config.Selected
        refreshProfiles(true)
        notify('Gym Star', 'Profile deleted')
    else
        notify('Gym Star', 'Could not delete this profile')
    end
end)


shared.PuckAFK_GymStar_Instance = {Unload = unload, State = state, Recovery = energyRecovery, Window = window, Version = '1.6.4'}

-- Compact live information. Don't display machine IDs, errors, counters or raw debug state.
local function simpleActivity()
    if not state.Master then return 'Paused' end
    if isCompeting() then return 'Competing' end
    if energyRecovery.active then return 'Recovering stamina' end
    if hatchSession then return 'Hatching eggs' end
    if isTraining() then return 'Training' end
    if busy then return 'Moving to equipment' end
    if status:find('Cannot train', 1, true) or status:find('Route blocked', 1, true) then
        return 'Finding an available free machine'
    end
    return 'Preparing next activity'
end

task.spawn(function()
    while running do
        safe('status display', function()
            if activityLabel then activityLabel:Set('Status: ' .. simpleActivity()) end
            if worldLabel then
                worldLabel:Set(string.format('World %d | Coins %.3g | Rebirths %s',
                    world(), currency(), tostring(val(player, 'rebirthCount', 0))))
            end
            if statsLabel then
                local _, _, ratio = energyValues()
                local ready = competitionReadiness()
                statsLabel:Set(string.format('Stamina: %s | Competition: %s',
                    ratio and string.format('%.0f%%', ratio * 100) or 'N/A',
                    ready and 'Ready' or 'Not ready'))
            end
        end)
        task.wait(2)
    end
end)
notify('PuckAFK Gym Star', 'Ready. Enable Smart Autofarm in Home.')
]===]
local run,err=loadstring(env.PuckAFK_GymStar_ResumeSource)
if run then run() else warn('[PuckAFK Gym Star] Compile error: '..tostring(err)) end
