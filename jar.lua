-- FairyAutoHarvester_vNext.client.lua

--- Services
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local CoreGui = game:GetService('CoreGui')
local Workspace = game:GetService('Workspace')
local PPS = game:GetService('ProximityPromptService')
local TeleportService = game:GetService('TeleportService')
local UserInputService = game:GetService('UserInputService')
local HttpService = game:GetService('HttpService')

local LP = Players.LocalPlayer

--- Singleton guard & cleanup
local _ENVG = (getgenv and getgenv()) or _G
if rawget(_ENVG, 'FairyJar_Cleanup') then
    pcall(_ENVG.FairyJar_Cleanup)
    _ENVG.FairyJar_Cleanup = nil
end

local __FJ_CONS = {}
local __FJ_INSTS = {}
local function _trackConn(c)
    if c then table.insert(__FJ_CONS, c) end
    return c
end
local function _trackInst(i)
    if i then table.insert(__FJ_INSTS, i) end
    return i
end
local function FairyJar_Cleanup()
    
    for _, c in ipairs(__FJ_CONS) do
        pcall(function() c:Disconnect() end)
    end
    __FJ_CONS = {}
    -- destroy our UI if still around
    pcall(function()
        local g = CoreGui:FindFirstChild('FairyAutoHarvesterUI')
        if g then g:Destroy() end
    end)
    for _, inst in ipairs(__FJ_INSTS) do
        pcall(function()
            if inst and inst.Destroy then inst:Destroy() end
        end)
    end
    __FJ_INSTS = {}
end
_ENVG.FairyJar_Cleanup = FairyJar_Cleanup

--- Config
local Y_OFFSET = 3.25 -- just a few studs above the fairy
local FAIRY_OBJECTTEXT = 'fairy' -- case-insensitive
local SWING_BURST = 8 -- a few extra swings to increase reliability
local SWING_GAP = 0.08 -- slightly quicker cadence
local LOCK_SECONDS = 0.85 -- keep player pinned during swings to prevent drift/void

--- Self-reexec config (URL-first)
local SELF_FILE       = "jar.lua"  -- optional fallback (can be nil)
local SELF_URL        = "https://raw.githubusercontent.com/fazeclansuppor-source/derasdwasdwad/refs/heads/main/jar.lua"  -- ← replace with your URL
local SELF_BOOT_DELAY = 1.0

local function hasFS()
    return typeof(readfile)=="function" and typeof(isfile)=="function" and typeof(loadstring)=="function"
end

local autoTP, autoSwing, autoRejoin, autoIslandTP, autoObby = true, true, false, false, false

--- Settings persistence
local SETTINGS_FILE = "FairyJar.settings.json"
local function canSave()
    return hasFS() and typeof(writefile)=="function"
end
local function saveSettings()
    if not canSave() then return end
    local ok, json = pcall(HttpService.JSONEncode, HttpService, {
    autoTP = autoTP,
    autoSwing = autoSwing,
    autoRejoin = autoRejoin,
    autoIslandTP = autoIslandTP,
    autoObby = autoObby,
    })
    if ok then
        pcall(writefile, SETTINGS_FILE, json)
        print("[FairyJar] settings saved:", SETTINGS_FILE)
    end
end
local function loadSettings()
    if not hasFS() or not isfile(SETTINGS_FILE) then return end
    local ok, content = pcall(readfile, SETTINGS_FILE)
    if not ok or type(content)~='string' or #content==0 then return end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not ok2 or type(data)~='table' then return end
    if typeof(data.autoTP)=="boolean" then autoTP = data.autoTP end
    if typeof(data.autoSwing)=="boolean" then autoSwing = data.autoSwing end
    if typeof(data.autoRejoin)=="boolean" then autoRejoin = data.autoRejoin end
    if typeof(data.autoIslandTP)=="boolean" then autoIslandTP = data.autoIslandTP end
    if typeof(data.autoObby)=="boolean" then autoObby = data.autoObby end
    print("[FairyJar] settings loaded from:", SETTINGS_FILE)
end

local function getQOT()
    
    return (syn and syn.queue_on_teleport)
        or (queue_on_teleport)      -- KRNL / Fluxus / etc.
        or (fluxus and fluxus.queue_on_teleport)
end

--- queued loader (HTTP -> HttpGet -> local file)
local function buildLoader(url, path, delaySec)
    return ((
        [[task.spawn(function()
        local function fetch(u)
            local req = (syn and syn.request) or http_request or request or (http and http.request)
            if req then
                local r = req({Url=u, Method="GET"})
                if r and r.StatusCode==200 and r.Body then return r.Body end
            end
            local ok,body = pcall(game.HttpGet, game, u)
            if ok and type(body)=="string" and #body>0 then return body end
            return nil
        end
        repeat task.wait() until game and game:IsLoaded()
        local Players = game:GetService("Players")
        while not Players.LocalPlayer do task.wait() end
        local _d = %f; if _d and _d > 0 then task.wait(_d) end
        local src = fetch(%q)
        if not src and typeof(readfile)=="function" and typeof(isfile)=="function" and isfile(%q) then
            local ok,body = pcall(readfile, %q)
            if ok then src = body end
        end
        if src then local f = loadstring(src, "FAH_loader"); if f then pcall(f) end else warn("[FAH queued] fetch failed") end
    end)]]
    ):format(delaySec or 0.5, url, path, path))
end

--- queued loader (local file only)
local function buildLoaderLocal(path, delaySec)
    return ( [[task.spawn(function()
        repeat task.wait() until game and game:IsLoaded()
        local Players = game:GetService("Players")
        while not Players.LocalPlayer do task.wait() end
        local _d = %f; if _d and _d > 0 then task.wait(_d) end

        if typeof(readfile)=="function" and typeof(isfile)=="function" and isfile(%q) then
            local ok, src = pcall(readfile, %q)
            if ok and type(src)=="string" and #src>0 then
                local f = loadstring(src, "FAH_loader")
                if f then pcall(f) end
            else
                warn("[FAH queued] could not read %q")
            end
        else
            warn("[FAH queued] file not found: %q")
        end
    end)]] ):format(delaySec or 0.5, path, path, path, path)
end

--- Self-reexec config (URL-first)
local SELF_FILE       = "jar.lua"  -- optional fallback (can be nil)
local SELF_URL        = "https://raw.githubusercontent.com/fazeclansuppor-source/thingymajigy/refs/heads/main/jar.lua"  -- ← replace with your URL
local SELF_BOOT_DELAY = 1.0

-- Read local file now so we can embed its contents into the QOT payload
local EMBED_SRC = nil
pcall(function()
    if typeof(readfile)=="function" and typeof(isfile)=="function" and isfile(SELF_FILE) then
        local ok, body = pcall(readfile, SELF_FILE)
        if ok and type(body)=="string" and #body>0 then
            EMBED_SRC = body
        end
    end
end)

--- NEW: embed-loader that carries the entire script as a string
local function buildLoaderEmbed(src, delaySec)
    return ( [[task.spawn(function()
        repeat task.wait() until game and game:IsLoaded()
        local Players = game:GetService("Players")
        while not Players.LocalPlayer do task.wait() end
        local _d = %f; if _d and _d > 0 then task.wait(_d) end
        local src = [=[%s]=]
        local f = loadstring(src, "FAH_embed")
        if f then pcall(f) else warn("[FAH queued] embed load failed") end
    end)]] ):format(delaySec or 0.5, src)
end

local function queueSelfOnTeleport()
    local qot = getQOT()
    if not qot then
        warn("[FAH] queue_on_teleport not available; use autoexec as fallback.")
        return
    end
    qot(buildLoader(SELF_URL, SELF_FILE or "", SELF_BOOT_DELAY or 0.5))
    print("[FAH] queued reexec (URL-first)")
end

--- Pre-arm re-exec on teleport
local function armQOT()
    local qot = getQOT()
    if qot then
        qot(buildLoader(SELF_URL, SELF_FILE or "", SELF_BOOT_DELAY or 0.5))
        print("[FAH] pre-armed reexec (URL-first)")
    else
        warn("[FAH] queue_on_teleport missing; consider autoexec fallback.")
    end
end

--- Also queue when teleport starts
_trackConn(Players.LocalPlayer.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        queueSelfOnTeleport()
    end
end))

--- Pre-arm at startup
armQOT()

--- Single instance
do
    local old = CoreGui:FindFirstChild('FairyAutoHarvesterUI')
    if old then
        old:Destroy()
    end
end

--- Helpers
local function getHRP()
    local char = LP.Character or LP.CharacterAdded:Wait()
    return char:WaitForChild('HumanoidRootPart', 5),
        char:FindFirstChildOfClass('Humanoid'),
        char
end

local function toPartOrModel(x)
    if not x then
        return nil
    end
    if x:IsA('BasePart') then
        return x
    end
    if x:IsA('Model') then
        return x.PrimaryPart or x:FindFirstChildWhichIsA('BasePart')
    end
    return x:FindFirstAncestorWhichIsA('BasePart')
end

local function zeroVel(hrp, hum)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new()
        hrp.AssemblyAngularVelocity = Vector3.new()
        if hum then
            hum:Move(Vector3.new(), true)
        end
    end)
end

local function aimCameraAt(part)
    local cam = Workspace.CurrentCamera
    if not (cam and part) then
        return
    end
    local look = (part.Position - cam.CFrame.Position).Unit
    local dist = (part.Position - cam.CFrame.Position).Magnitude
    if dist > 3 then
        cam.CFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + look)
    end
end

local function lockAtTarget(part, seconds)
    local hrp, hum = getHRP()
    if not (hrp and part) then
        return
    end
    local targetCF = part.CFrame + Vector3.new(0, Y_OFFSET, 0)
    zeroVel(hrp, hum)
    hrp.CFrame = targetCF

    -- keep the character pinned in place very briefly while we swing
    local t0 = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if (os.clock() - t0) > seconds then
            if conn then
                conn:Disconnect()
            end
            return
        end
        zeroVel(hrp, hum)
        hrp.CFrame = targetCF
    end)
end

local function safeTP(target)
    local hrp, hum = getHRP()
    if not hrp or not target then
        return
    end
    local p = toPartOrModel(target)
    if not p then
        return
    end
    zeroVel(hrp, hum)
    hrp.CFrame = p.CFrame + Vector3.new(0, Y_OFFSET, 0)
end

-- Server-side Fairy Island teleport (preferred)
local function fireFairyWorldTeleport(timeout)
    timeout = timeout or 5
    local RS = game:GetService('ReplicatedStorage')
    local t0 = os.clock()
    local function remTime()
        return math.max(0, timeout - (os.clock() - t0))
    end
    local gameEvents = RS:WaitForChild('GameEvents', remTime())
    if not gameEvents then return false, 'GameEvents not found' end
    local fairyService = gameEvents:WaitForChild('FairyService', remTime())
    if not fairyService then return false, 'FairyService not found' end
    local teleportEvent = fairyService:WaitForChild('TeleportFairyWorld', remTime())
    if not teleportEvent then return false, 'TeleportFairyWorld not found' end
    local ok, err = pcall(function()
        teleportEvent:FireServer()
    end)
    if not ok then return false, err end
    return true
end

--- Auto Fairy Parkour (RewardPoint) one-shot collector
local _obbyRunning = false
local function runAutoParkourOnce()
    if _obbyRunning then return end
    _obbyRunning = true
    task.defer(function()
        local CollectionService      = game:GetService('CollectionService')
        local ProximityPromptService = game:GetService('ProximityPromptService')
        local VirtualInputManager    = game:GetService('VirtualInputManager')

        -- tune
        local TAGS               = { 'FairyParkourPt', 'RewardPoint' }
        local OBJECT_TEXT_MATCH  = 'Fairy Parkour'
        local ACTION_TEXT_MATCH  = 'Claim Reward'
        local ABOVE_Y            = 1.8
        local HORIZONTAL_OFFSET  = 0.0
        local HOLD_PAD           = 0.10
        local BETWEEN_POINTS     = 0.06  -- sped up from 0.20
        local E_PRESSES          = 3
        local E_SPAM_GAP         = 0.08
        local TAP_DURATION       = 0.05
        local TIMEOUT_PER_POINT  = 2.5

        -- Teleport tuning (lower + faster)
        local TP_SURFACE_CLEARANCE = 0.35   -- smaller = lower
        local TP_MAX_DOWNCAST      = 6
        local FREEZE_PULSE         = 0.06   -- sped up from ~0.12

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist

        local function surfaceSnap(pos, ignoreList)
            rayParams.FilterDescendantsInstances = ignoreList or {}
            local origin = pos + Vector3.new(0, TP_MAX_DOWNCAST, 0)
            local result = Workspace:Raycast(origin, Vector3.new(0, -TP_MAX_DOWNCAST*2, 0), rayParams)
            if result then
                return result.Position + Vector3.new(0, TP_SURFACE_CLEARANCE, 0)
            else
                return pos + Vector3.new(0, TP_SURFACE_CLEARANCE, 0)
            end
        end

        local function waitChar()
            local c = LP.Character or LP.CharacterAdded:Wait()
            return c, c:WaitForChild('HumanoidRootPart'), c:WaitForChild('Humanoid')
        end
        local function nearestBasePart(inst)
            if inst:IsA('BasePart') then return inst end
            local cur = inst
            for _=1,6 do
                if not cur then break end
                if cur:IsA('BasePart') then return cur end
                cur = cur.Parent
            end
            return nil
        end
        local function findPrompt(container)
            local best = nil
            for _, d in ipairs(container:GetDescendants()) do
                if d:IsA('ProximityPrompt') then
                    best = best or d
                    local ot, at = d.ObjectText or '', d.ActionText or ''
                    if tostring(ot):find(OBJECT_TEXT_MATCH) or tostring(at):find(ACTION_TEXT_MATCH) then
                        return d
                    end
                end
            end
            return best
        end
        local function collectTargets()
            local seen, list = {}, {}
            for _, tag in ipairs(TAGS) do
                for _, inst in ipairs(CollectionService:GetTagged(tag)) do
                    local bp = nearestBasePart(inst)
                    if bp and not seen[bp] then
                        seen[bp] = true
                        table.insert(list, bp)
                    end
                end
            end
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA('ProximityPrompt') then
                    local ot, at = d.ObjectText or '', d.ActionText or ''
                    if tostring(ot):find(OBJECT_TEXT_MATCH) or tostring(at):find(ACTION_TEXT_MATCH) then
                        local bp = nearestBasePart(d)
                        if bp and not seen[bp] then
                            seen[bp] = true
                            table.insert(list, bp)
                        end
                    end
                end
            end
            return list
        end
        local function tpAbove(hrp, target)
            local placePos = surfaceSnap(target.Position, {LP.Character})
            local dest = Vector3.new(target.Position.X + HORIZONTAL_OFFSET, placePos.Y, target.Position.Z)
            hrp.CFrame = CFrame.new(dest, dest + (hrp.CFrame.LookVector))
            hrp.Anchored = true
            task.wait(FREEZE_PULSE)
            hrp.Anchored = false
        end
        local function freeze(hum, hrp)
            local save = {
                WalkSpeed  = hum.WalkSpeed,
                JumpPower  = hum.JumpPower,
                AutoRotate = hum.AutoRotate,
                Anchored   = hrp.Anchored,
            }
            hum.WalkSpeed  = 0
            hum.JumpPower  = 0
            hum.AutoRotate = false
            hrp.Anchored   = true
            return save
        end
        local function unfreeze(hum, hrp, save)
            if hum and hum.Parent then
                hum.WalkSpeed  = save.WalkSpeed  or 16
                hum.JumpPower  = save.JumpPower  or 50
                hum.AutoRotate = (save.AutoRotate ~= nil) and save.AutoRotate or true
            end
            if hrp and hrp.Parent then
                hrp.Anchored = save.Anchored or false
            end
        end
        local function sendKeyPress(key, duration)
            VirtualInputManager:SendKeyEvent(true, key, false, game)
            task.wait(duration)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end
        local function tryTrigger(prompt)
            local key  = (prompt.KeyboardKeyCode ~= Enum.KeyCode.Unknown) and prompt.KeyboardKeyCode or Enum.KeyCode.E
            local hold = (prompt.HoldDuration or 0) + HOLD_PAD
            for i = 1, E_PRESSES do
                local fired =
                    ((typeof(getgenv) == 'function' and typeof(getgenv().fireproximityprompt) == 'function') and pcall(getgenv().fireproximityprompt, prompt)) or
                    ((typeof(_G.fireproximityprompt) == 'function') and pcall(_G.fireproximityprompt, prompt)) or
                    ((typeof(fireproximityprompt) == 'function') and pcall(fireproximityprompt, prompt))
                if not fired then
                    if i == 1 and (prompt.HoldDuration or 0) > 0 then
                        sendKeyPress(key, hold)
                    else
                        sendKeyPress(key, TAP_DURATION)
                    end
                end
                if i < E_PRESSES then task.wait(E_SPAM_GAP) end
            end
        end
        local function waitForPrompt(prompt, timeout)
            local done = false
            local conn
            conn = _trackConn(ProximityPromptService.PromptTriggered:Connect(function(pr, plr)
                if pr == prompt and (plr == nil or plr == LP) then
                    done = true
                end
            end))
            local t0 = time()
            while not done and (time() - t0) < timeout do
                task.wait(0.05)
            end
            if conn then pcall(function() conn:Disconnect() end) end
            return done
        end

        local _, hrp, hum = waitChar()
        local targets = collectTargets()
        if #targets == 0 then
            warn('[AutoFairyParkour] No targets found. Tweak TAGS/text.')
            _obbyRunning = false
            return
        end
        table.sort(targets, function(a, b)
            return (a.Position - hrp.Position).Magnitude < (b.Position - hrp.Position).Magnitude
        end)
        print(('[AutoFairyParkour] %d targets.'):format(#targets))
        for _, part in ipairs(targets) do
            if not part or not part.Parent then continue end
            local prompt = findPrompt(part)
            if not prompt then
                warn('[AutoFairyParkour] Skipping (no prompt found): ', part:GetFullName())
                continue
            end
            tpAbove(hrp, part)
            local ok, err = pcall(function()
                if not prompt.Enabled then task.wait(0.10) end
                if prompt.Enabled then
                    tryTrigger(prompt)
                    waitForPrompt(prompt, TIMEOUT_PER_POINT)
                end
            end)
            if not ok then
                warn('[AutoFairyParkour] Error at point: ', err)
            end
            task.wait(BETWEEN_POINTS)
        end
        print('[AutoFairyParkour] Done.')
        _obbyRunning = false
    end)
end

--- Forward declaration for Island teleport routine
local autoIslandTeleport

--- Fairy Island: auto-teleport on startup (optional)
local ISLAND_HOLD_SECONDS = 2.0 -- unused now; kept for compatibility
local ISLAND_LIFT_Y = 3         -- unused now; kept for compatibility

autoIslandTeleport = function()
    -- Preferred: ask the server to teleport us
    local ok, err = fireFairyWorldTeleport(5)
    if not ok then
        warn("[FairyJar] TeleportFairyWorld failed: " .. tostring(err))
        return false
    end
    return true
end

-- net finder / equipper
local function looksLikeFairyNet(tool)
    if not tool or not tool:IsA('Tool') then
        return false
    end
    if tool:GetAttribute('FairyNet') == true then
        return true
    end
    if tool:FindFirstChild('FairyNetV2Handler', true) then
        return true
    end
    local n = string.lower(tool.Name)
    return (n:find('fairy') ~= nil) and (n:find('net') ~= nil)
end

local function findNetToolAnywhere()
    local _, _, char = getHRP()
    local backpack = LP:FindFirstChildOfClass('Backpack')
        or LP:FindFirstChild('Backpack')
    local function scan(container)
        if not container then
            return nil
        end
        for _, t in ipairs(container:GetChildren()) do
            if looksLikeFairyNet(t) then
                return t
            end
        end
        return nil
    end
    return scan(char) or scan(backpack)
end

local function ensureNetEquipped(timeout)
    timeout = timeout or 3.0
    local hrp, hum, char = getHRP()
    local t0 = os.clock()
    repeat
        local tool = findNetToolAnywhere()
        if tool then
            if tool.Parent ~= char and hum then
                pcall(function()
                    hum:EquipTool(tool)
                end)
            end
            if tool.Parent ~= char then
                pcall(function()
                    tool.Parent = char
                end)
            end
            if tool.Parent == char then
                return tool
            end
        end
        RunService.Heartbeat:Wait()
    until (os.clock() - t0) > timeout
    return nil
end

-- prompts (we DO NOT trigger them)
local function isFairyPrompt(prompt)
    return tostring(prompt.ObjectText or ''):lower() == FAIRY_OBJECTTEXT
end

local function anchorFromPrompt(prompt)
    return (
        prompt
        and prompt.Parent
        and (prompt.Parent:FindFirstAncestorOfClass('Model') or prompt.Parent)
    )
end

local function findPromptUnder(inst)
    if not inst then
        return nil
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA('ProximityPrompt') and isFairyPrompt(d) then
            return d
        end
    end
    return nil
end

local function temporarilyDisablePrompt(anchor, dur)
    local p = findPromptUnder(anchor)
    if not p then
        return
    end
    local old = p.Enabled
    p.Enabled = false
    task.delay(dur or 1.25, function()
        if p then
            p.Enabled = old
        end
    end)
end

-- swing only (no E) — more robust via multiple inputs + aim + lock
local function swingNetAt(anchor)
    local tool = ensureNetEquipped(2.5)
    if not tool then
        return false, 'no Fairy Net found'
    end

    local part = toPartOrModel(anchor)
    if not part then
        return false, 'no target part'
    end

    temporarilyDisablePrompt(anchor, SWING_BURST * SWING_GAP + 0.5)

    -- lock and aim to improve hit registration
    aimCameraAt(part)
    lockAtTarget(part, LOCK_SECONDS)

    local vim = game:FindService('VirtualInputManager')
    local vuser = game:FindService('VirtualUser')
    local cam = Workspace.CurrentCamera

    for _ = 1, SWING_BURST do
        -- Path A: Tool:Activate
        pcall(function()
            tool:Activate()
        end)

        -- Path B: mouse click via VIM
        if vim and cam then
            local vp = cam.ViewportSize
            local x, y = math.floor(vp.X / 2), math.floor(vp.Y / 2)
            pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
                vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
        end

        -- Path C: VirtualUser fallback (some executors prefer this)
        if vuser then
            pcall(function()
                vuser:CaptureController()
                vuser:ClickButton1(Vector2.new())
            end)
        end

        RunService.Heartbeat:Wait() -- frame-accurate pacing
        task.wait(SWING_GAP)
    end
    return true
end

--- State
local Anchors = {}
local AnchorSet = setmetatable({}, { __mode = 'k' })
local AnchorCons = {}
local Queue, InQueue = {}, setmetatable({}, { __mode = 'k' })
local workerRunning = false
--- Load persisted settings
pcall(loadSettings)

--- GUI (clean layout)
local gui = Instance.new('ScreenGui')
gui.Name = 'FairyAutoHarvesterUI'
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.Parent = CoreGui
_trackInst(gui)

local card = Instance.new('Frame')
card.Name = 'Card'
card.Size = UDim2.fromOffset(520, 320)
card.Position = UDim2.new(0.5, -260, 0.22, -110)
card.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
card.Active, card.Draggable = true, true
card.Parent = gui
Instance.new('UICorner', card).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new('UIStroke')
stroke.Color = Color3.fromRGB(60, 65, 85)
stroke.Thickness = 1
stroke.Parent = card
local pad = Instance.new('UIPadding')
pad.PaddingTop = UDim.new(0, 10)
pad.PaddingBottom = UDim.new(0, 10)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = card

--- Minimized bubble (restore)
local minBubble = Instance.new('TextButton')
minBubble.Name = 'FairyJarMinBubble'
minBubble.Text = ''
minBubble.AutoButtonColor = true
minBubble.Visible = false
minBubble.Size = UDim2.fromOffset(36, 36)
minBubble.AnchorPoint = Vector2.new(0.5, 0.5)
minBubble.Position = UDim2.new(0.25, 0, 0.25, 0)
minBubble.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
minBubble.TextColor3 = Color3.fromRGB(230, 230, 230)
minBubble.Parent = gui
do
    local c = Instance.new('UICorner')
    c.CornerRadius = UDim.new(0, 18)
    c.Parent = minBubble
    local s = Instance.new('UIStroke')
    s.Color = Color3.fromRGB(60, 65, 85)
    s.Thickness = 1
    s.Parent = minBubble
end
minBubble.MouseButton1Click:Connect(function()
    card.Visible = true
    minBubble.Visible = false
end)

local vlist = Instance.new('UIListLayout')
vlist.Parent = card
vlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
vlist.VerticalAlignment = Enum.VerticalAlignment.Top
vlist.Padding = UDim.new(0, 8)
vlist.SortOrder = Enum.SortOrder.LayoutOrder

local header = Instance.new('Frame')
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 26)
header.Parent = card

local hpad = Instance.new('UIPadding')
hpad.PaddingLeft = UDim.new(0, 4)
hpad.PaddingRight = UDim.new(0, 4)
hpad.Parent = header

local title = Instance.new('TextLabel')
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = 'Fairy Jar'
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(235, 235, 245)
title.TextXAlignment = Enum.TextXAlignment.Center
title.Size = UDim2.new(1, -56, 1, 0)
title.Parent = header

--- Minimize button
local minimize = Instance.new('TextButton')
minimize.Text = '-'
minimize.Font = Enum.Font.Gotham
minimize.TextSize = 14
minimize.TextColor3 = Color3.fromRGB(230, 230, 230)
minimize.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
minimize.Size = UDim2.fromOffset(24, 24)
minimize.Position = UDim2.new(1, -52, 0.5, -12)
minimize.Parent = header
do
    local c = Instance.new('UICorner')
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = minimize
    local s = Instance.new('UIStroke')
    s.Color = Color3.fromRGB(60, 65, 85)
    s.Parent = minimize
end
minimize.MouseButton1Click:Connect(function()
    card.Visible = false
    minBubble.Visible = true
end)

local close = Instance.new('TextButton')
close.Text = 'X'
close.Font = Enum.Font.Gotham
close.TextSize = 14
close.TextColor3 = Color3.fromRGB(230, 230, 230)
close.BackgroundColor3 = Color3.fromRGB(40, 42, 54)
close.Size = UDim2.fromOffset(24, 24)
close.Position = UDim2.new(1, -24, 0.5, -12)
close.Parent = header
Instance.new('UICorner', close).CornerRadius = UDim.new(0, 6)
Instance.new('UIStroke', close).Color = Color3.fromRGB(60, 65, 85)
close.MouseButton1Click:Connect(function()
    if gui.Parent then
        gui:Destroy()
    end
end)

local statusLbl = Instance.new('TextLabel')
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.Text = 'Status: idle'
statusLbl.TextSize = 12
statusLbl.TextColor3 = Color3.fromRGB(170, 175, 190)
statusLbl.Size = UDim2.new(1, -8, 0, 18)
statusLbl.Parent = card

local countLbl = Instance.new('TextLabel')
countLbl.BackgroundTransparency = 1
countLbl.Font = Enum.Font.GothamBold
countLbl.Text = 'Detected fairies: 0'
countLbl.TextSize = 13
countLbl.TextColor3 = Color3.fromRGB(200, 230, 200)
countLbl.Size = UDim2.new(1, -8, 0, 18)
countLbl.Parent = card

--- Toggles
local row = Instance.new('Frame')
row.BackgroundTransparency = 1
row.Size = UDim2.new(1, 0, 0, 84)
row.Parent = card

local grid = Instance.new('UIGridLayout')
grid.Parent = row
grid.CellPadding = UDim2.new(0, 8, 0, 6)
grid.FillDirection = Enum.FillDirection.Horizontal
grid.FillDirectionMaxCells = 3
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Center
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.CellSize = UDim2.new(1 / 3, -8, 0, 36)

local function mkToggle(textOn, textOff, startOn, onChange)
    local b = Instance.new('TextButton')
    b.Text = startOn and textOn or textOff
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.new(1, 1, 1)
    b.BackgroundColor3 = startOn and Color3.fromRGB(65, 160, 85)
        or Color3.fromRGB(160, 90, 60)
    b.Parent = row
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 8)
    Instance.new('UIStroke', b).Color = Color3.fromRGB(60, 65, 85)
    local bpad = Instance.new('UIPadding')
    bpad.PaddingLeft = UDim.new(0, 6)
    bpad.PaddingRight = UDim.new(0, 6)
    bpad.Parent = b
    b.MouseButton1Click:Connect(function()
        local on = not (b.Text == textOn)
        b.Text = on and textOn or textOff
        b.BackgroundColor3 = on and Color3.fromRGB(65, 160, 85)
            or Color3.fromRGB(160, 90, 60)
        onChange(on)
    end)
    return b
end

mkToggle('Auto-TP: ON', 'Auto-TP: OFF', autoTP, function(on)
    autoTP = on
    print("[FairyJar] Auto-TP ->", on and "ON" or "OFF")
    saveSettings()
end)
mkToggle('Auto Collect: ON', 'Auto Collect: OFF', autoSwing, function(on)
    autoSwing = on
    print("[FairyJar] Auto Collect ->", on and "ON" or "OFF")
    saveSettings()
end)
mkToggle('Auto Rejoin: ON', 'Auto Rejoin: OFF', autoRejoin, function(on)
    autoRejoin = on
    print("[FairyJar] Auto Rejoin ->", on and "ON" or "OFF")
    saveSettings()
end)

--- Auto Island TP toggle
local islandToggleBtn = mkToggle('Island TP: ON', 'Island TP: OFF', autoIslandTP, function(on)
    autoIslandTP = on
    print("[FairyJar] Auto Island TP ->", on and "ON" or "OFF")
    saveSettings()
    if on then
        task.defer(function()
            autoIslandTeleport()
            if autoObby then
                task.wait(1.0)
                runAutoParkourOnce()
            end
        end)
    end
end)

--- Auto Obby (Parkour) toggle
local obbyToggleBtn = mkToggle('Auto Obby: ON', 'Auto Obby: OFF', autoObby, function(on)
    autoObby = on
    print("[FairyJar] Auto Obby ->", on and "ON" or "OFF")
    saveSettings()
    if on then
        task.defer(function()
            -- Ensure Island TP is ON visually and logically
            if not autoIslandTP then
                autoIslandTP = true
                if islandToggleBtn then
                    islandToggleBtn.Text = 'Island TP: ON'
                    islandToggleBtn.BackgroundColor3 = Color3.fromRGB(65, 160, 85)
                end
                saveSettings()
            end
            -- Run Island TP first, then obby after a short delay
            autoIslandTeleport()
            task.wait(1.0)
            runAutoParkourOnce()
        end)
    end
end)

local foot = Instance.new('TextLabel')
foot.BackgroundTransparency = 1
foot.Font = Enum.Font.Gotham
foot.Text = ('Y offset: %.2f'):format(Y_OFFSET)
foot.TextSize = 12
foot.TextColor3 = Color3.fromRGB(160, 170, 190)
foot.Size = UDim2.new(1, -8, 0, 18)
foot.Parent = card

local function setStatus(t)
    statusLbl.Text = 'Status: ' .. t
end
local function setCount(n)
    countLbl.Text = ('Detected fairies: %d'):format(n)
end

--- Book-keeping
local function updateCountLabel()
    local i = 1
    while i <= #Anchors do
        local a = Anchors[i]
        if not (a and a.Parent) then
            local dead = table.remove(Anchors, i)
            AnchorSet[dead] = nil
            local cons = AnchorCons[dead]
            if cons then
                for _, c in ipairs(cons) do
                    pcall(function()
                        c:Disconnect()
                    end)
                end
            end
            AnchorCons[dead] = nil
        else
            i += 1
        end
    end
    setCount(#Anchors)
end

local function enqueue(anchor)
    if not anchor or InQueue[anchor] then
        return
    end
    InQueue[anchor] = true
    table.insert(Queue, anchor)
end

local function processAnchor(anchor)
    if not (anchor and anchor.Parent) then
        return
    end
    local part = toPartOrModel(anchor)
    if autoTP then
        setStatus('TP → ' .. (anchor.Name or 'fairy'))
        safeTP(part)
        task.wait(0.10)
    end
    if autoSwing then
        setStatus('swinging net')
        local ok, err = swingNetAt(anchor)
        if not ok then
            setStatus(err or 'swing failed')
        else
            setStatus('done')
        end
    else
        setStatus('queued (auto swing OFF)')
    end
end

----------------------------------------------------------------
-- REJOIN (simplified: just Teleport to the same place)
----------------------------------------------------------------
local _rejoinInFlight = false

local function rejoinNow(reason)
    if _rejoinInFlight then return end
    _rejoinInFlight = true
    setStatus('rejoining…')
    print(("[FairyJar] Rejoin requested%s"):format(reason and (" ("..tostring(reason)..")") or ""))

    -- Ensure the loader is queued so the script runs after teleport
    queueSelfOnTeleport()

    local ok, err = pcall(function()
        TeleportService:Teleport(game.PlaceId, LP)
    end)
    if not ok then
        warn("[FairyJar] Teleport failed: " .. tostring(err))
        _rejoinInFlight = false
    end
end

-- Expose manual entry point (console): _G.FairyAutoHarvester_RejoinNow()
_G.FairyAutoHarvester_RejoinNow = function()
    rejoinNow('Manual rejoin')
end

-- (Optional) Hotkey: Alt+R to rejoin now
_trackConn(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.R and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
        rejoinNow('Alt+R')
    end
end))

-- UI: TP Island button (manual one-time Island teleport)
do
    local tpBtn = Instance.new('TextButton')
    tpBtn.Name = 'TPIsland'
    tpBtn.Text = 'Teleport to Fairy Island'
    tpBtn.Font = Enum.Font.GothamBold
    tpBtn.TextSize = 14
    tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    tpBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 90)
    tpBtn.Size = UDim2.new(1, 0, 0, 36)
    tpBtn.AutoButtonColor = true
    tpBtn.Parent = card
    Instance.new('UICorner', tpBtn).CornerRadius = UDim.new(0, 8)
    local tpStroke = Instance.new('UIStroke')
    tpStroke.Color = Color3.fromRGB(60, 65, 85)
    tpStroke.Thickness = 1
    tpStroke.Parent = tpBtn

    tpBtn.MouseButton1Click:Connect(function()
        -- Auto TP to FairyIsland.TeleportDestination, hold 2s, then auto-disable
        -- paste in console

        local Players     = game:GetService("Players")
        local RunService  = game:GetService("RunService")
        local Workspace   = game:GetService("Workspace")

        local LP = Players.LocalPlayer
        local HOLD_SECONDS = 2.0            -- how long to fight the server before disabling
        local LIFT_Y       = 3               -- lift above the TeleportDestination to avoid floor clipping

        -- --- helpers ---
        local function HRP()
            local c = LP.Character or LP.CharacterAdded:Wait()
            local h = c:FindFirstChild("HumanoidRootPart")
            while not h do
                h = c:FindFirstChild("HumanoidRootPart")
                task.wait(0.05)
            end
            return h
        end

        local function findDest()
            local node = Workspace
            node = node:FindFirstChild("Interaction"); if not node then return nil end
            node = node:FindFirstChild("UpdateItems"); if not node then return nil end
            node = node:FindFirstChild("FairyIsland"); if not node then return nil end
            node = node:FindFirstChild("FairyIsland"); if not node then return nil end
            node = node:FindFirstChild("Decor"); if not node then return nil end
            node = node:FindFirstChild("EntryFairyPond"); if not node then return nil end
            if node:IsA("BasePart") then return node end
            if node:IsA("Model") then
                local pp = node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart", true)
                return pp
            end
            return nil
        end

        local function waitForDest()
            local dest = findDest()
            while not dest do
                task.wait(0.25)
                dest = findDest()
            end
            return dest
        end

        local function forceTo(cf)
            local h = HRP()
            -- zero velocities to reduce rubber-banding while holding
            pcall(function()
                h.AssemblyLinearVelocity  = Vector3.new()
                h.AssemblyAngularVelocity = Vector3.new()
            end)
            h.CFrame = cf
        end

        -- --- main ---
        task.spawn(function()
            local dest = waitForDest()
            local targetCF = dest.CFrame + Vector3.new(0, LIFT_Y, 0)

            -- initial teleport
            forceTo(targetCF)
            if toast then toast("2 second wait") end
            warn("[FAIRY] Teleported to TeleportDestination; holding for "..HOLD_SECONDS.."s...")

            -- hold for exactly N seconds, then stop automatically
            local t0 = tick()
            local holdConnRS, holdConnHB

            local function shouldHold()
                return (tick() - t0) <= HOLD_SECONDS
            end

            holdConnRS = RunService.RenderStepped:Connect(function()
                if shouldHold() then
                    forceTo(targetCF)
                else
                    if holdConnRS then holdConnRS:Disconnect() end
                end
            end)

            -- optional: double up on Heartbeat too (helps against some server pulls)
            holdConnHB = RunService.Heartbeat:Connect(function()
                if not shouldHold() then
                    if holdConnHB then holdConnHB:Disconnect() end
                end
            end)

            -- wait out the hold, then announce disabled
            task.delay(HOLD_SECONDS, function()
                warn("[FAIRY] Hold disabled automatically after "..HOLD_SECONDS.."s.")
            end)
        end)
    end)
end

-- UI: Rejoin button
do
    local rejoinBtn = Instance.new('TextButton')
    rejoinBtn.Name = 'Rejoin'
    rejoinBtn.Text = 'Rejoin'
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 14
    rejoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
    rejoinBtn.Size = UDim2.new(1, 0, 0, 36)
    rejoinBtn.AutoButtonColor = true
    rejoinBtn.Parent = card
    Instance.new('UICorner', rejoinBtn).CornerRadius = UDim.new(0, 8)
    local tStroke = Instance.new('UIStroke')
    tStroke.Color = Color3.fromRGB(60, 65, 85)
    tStroke.Thickness = 1
    tStroke.Parent = rejoinBtn

    rejoinBtn.MouseButton1Click:Connect(function()
        setStatus('rejoining…')
        rejoinNow('UI rejoin')
    end)
end

----------------------------------------------------------------
-- Worker
----------------------------------------------------------------
local function runWorker()
    if workerRunning then
        return
    end
    workerRunning = true
    setStatus('worker running')
    while #Queue > 0 do
        local a = table.remove(Queue, 1)
        InQueue[a] = nil
        pcall(processAnchor, a)
        task.wait(0.18)
    end
    workerRunning = false
    setStatus('idle')

    -- Auto rejoin when queue stays empty briefly
    if autoRejoin then
        local t0 = os.clock()
        while (os.clock() - t0) < 0.75 do
            if #Queue > 0 then
                return
            end
            RunService.Heartbeat:Wait()
        end
        -- mirror your snippet's logic:
        -- if alone => Kick + Teleport(place)
        -- else      => TeleportToPlaceInstance(place, jobId)
        rejoinNow('Auto rejoin')
    end
end

local function kickWorker()
    if not workerRunning and #Queue > 0 then
        task.defer(function()
            RunService.Heartbeat:Wait() -- allow bursts to coalesce
            if not workerRunning and #Queue > 0 then
                runWorker()
            end
        end)
    end
end

local function trackAnchor(anchor)
    if not anchor or AnchorSet[anchor] then
        return
    end
    AnchorSet[anchor] = true
    table.insert(Anchors, anchor)
    AnchorCons[anchor] = AnchorCons[anchor] or {}
    table.insert(
        AnchorCons[anchor],
        _trackConn(anchor.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                updateCountLabel()
            end
        end))
    )
    updateCountLabel()
    enqueue(anchor)
    kickWorker()
end

---------------- Detection (existing + new) ----------------
local function attachPromptWatchers(prompt)
    local function check()
        if prompt.Enabled and isFairyPrompt(prompt) then
            local a = anchorFromPrompt(prompt)
            if a then
                trackAnchor(a)
            end
        end
    end
    check()
    _trackConn(prompt:GetPropertyChangedSignal('Enabled'):Connect(check))
    _trackConn(prompt:GetPropertyChangedSignal('ObjectText'):Connect(check))
end

-- initial pass (prompts only)
for _, inst in ipairs(Workspace:GetDescendants()) do
    if inst:IsA('ProximityPrompt') then
        attachPromptWatchers(inst)
    end
end
kickWorker() -- start immediately if initial scan queued anything

-- live hooks
_trackConn(Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA('ProximityPrompt') then
        attachPromptWatchers(obj)
    end
end))

_trackConn(PPS.PromptShown:Connect(function(prompt)
    if isFairyPrompt(prompt) then
        local a = anchorFromPrompt(prompt)
        if a then
            trackAnchor(a)
        end
    end
end))

print(
    '[FairyAutoCollect]'
)

-- Startup auto Island TP if configured
task.spawn(function()
    -- wait for game, player, and a tiny settle
    repeat task.wait() until game and game:IsLoaded()
    local ok = pcall(function() local _ = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait() end)
    task.wait(0.5)
    if autoIslandTP then
        autoIslandTeleport()
        if autoObby then
            task.wait(1.0)
            runAutoParkourOnce()
        end
    end
end)

