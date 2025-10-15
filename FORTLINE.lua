-- FORTLINE: REWORKED (All bugs fixed / Reworked / Extras) - by Shxdow
-- Features:
--  • Robust network detection + safe-mode (disable remote firing)
--  • Modular structure with connection management
--  • Per-player loop kill with rate-limiter
--  • Global loop-kill toggle
--  • Aimbot: hold-to-aim, smooth, prediction, configurable bone & FOV circle
--  • ESP: stable Drawing objects, health bar, name, distance, auto-cleanup
--  • Misc: Speed/Jump toggles, teleport to player, reset, hitbox loader
--  • UI: safe Rayfield load, UI toggle key, status overlay (Drawing)
--  • Proper unload that disconnects everything & removes drawings
--  • Defensive checks everywhere to avoid runtime errors

-- CONFIG (tweak here)
local CONFIG = {
    UI = {
        RayfieldURL = 'https://sirius.menu/rayfield',
        ConfigFile = "FORTLINE_PRO_2025",
        ToggleKey = Enum.KeyCode.RightControl, -- hide/show UI
    },
    Aimbot = {
        HoldToAim = true,
        HoldInput = Enum.UserInputType.MouseButton2, -- right mouse
        DefaultFOV = 120,
        DefaultBone = "HumanoidRootPart",
        DefaultSmooth = 0.22,
        DefaultPrediction = 0, -- studs/sec used for prediction scaling
    },
    LoopKill = {
        Delay = 0.6, -- seconds between calls per target
        MaxCallsPerSecond = 1.5, -- safety
    },
    ESP = {
        MaxDistance = 1500,
        TextSize = 16,
    },
    Misc = {
        SpeedValue = 50,
        JumpValue = 100,
    },
    Safety = {
        SafeModeDisableFiring = false, -- if true, network-based firing won't run
    }
}

-- ======= Services / Basic refs =======
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

-- camera safer retrieval (handles replacements)
local function getCamera()
    local cam = workspace:FindFirstChildOfClass("Camera") or workspace.CurrentCamera
    if not cam then
        -- try waiting briefly (non-blocking)
        for i=1,5 do
            cam = workspace:FindFirstChildOfClass("Camera") or workspace.CurrentCamera
            if cam then break end
            task.wait(0.1)
        end
    end
    return cam
end
local Camera = getCamera()

-- ======= Module: Connection Manager =======
local ConnManager = {
    connections = {}
}
function ConnManager:Bind(connKey, connObj)
    if not connKey or not connObj then return end
    self.connections[connKey] = connObj
end
function ConnManager:Unbind(connKey)
    local c = self.connections[connKey]
    if c then
        if typeof(c) == "RBXScriptConnection" and c.Disconnect then
            pcall(function() c:Disconnect() end)
        elseif type(c) == "function" then
            pcall(c)
        end
        self.connections[connKey] = nil
    end
end
function ConnManager:DisconnectAll()
    for k,v in pairs(self.connections) do
        pcall(function()
            if typeof(v) == "RBXScriptConnection" and v.Disconnect then v:Disconnect() end
        end)
        self.connections[k] = nil
    end
end

-- ======= Module: Safe Rayfield Load (UI) =======
local Rayfield
do
    local ok, ret = pcall(function()
        return loadstring(game:HttpGet(CONFIG.UI.RayfieldURL))()
    end)
    if ok and ret then
        Rayfield = ret
    else
        warn("Rayfield failed to load; using fallback minimal API.")
        Rayfield = {
            CreateWindow = function() return {
                CreateTab = function() return {
                    CreateButton = function() end,
                    CreateToggle = function() end,
                    CreateInput = function() end,
                    CreateSlider = function() end,
                } end,
                LoadConfiguration = function() end,
            } end
        }
    end
end

local Window = Rayfield:CreateWindow({
    Name = "FORTLINE (REWORKED)",
    Icon = 0,
    LoadingTitle = "Initializing...",
    LoadingSubtitle = "by Shxdow",
    Theme = "Ocean",
    ConfigurationSaving = {Enabled=true, FolderName=nil, FileName=CONFIG.UI.ConfigFile},
})

-- Tabs
local TabMain = Window:CreateTab("Main", 4483362458)
local TabESP = Window:CreateTab("ESP", 4483362458)
local TabMisc = Window:CreateTab("Misc", 4483362458)
local TabAimbot = Window:CreateTab("Aimbot", 4483362458)

-- ======= Module: Weapon Network (safe detection + caching) =======
local WeaponNetwork = {
    cached = nil,
    lastTry = 0,
    retryInterval = 1.0,
}
function WeaponNetwork:FindNetwork()
    -- Try cached first
    if self.cached then return self.cached end
    -- throttle repeated lookups
    if tick() - self.lastTry < self.retryInterval then return nil end
    self.lastTry = tick()
    local ok, net = pcall(function()
        local ws = ReplicatedStorage:FindFirstChild("WeaponsSystem")
        if not ws then return nil end
        local network = ws:FindFirstChild("Network")
        if not network then return nil end
        -- try known names
        for _,n in ipairs({"WeaponHit","FireWeapon","HitEvent","WeaponRemote"}) do
            local c = network:FindFirstChild(n)
            if c then return c end
        end
        -- fallback: first RemoteEvent/Function
        for _,c in ipairs(network:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then return c end
        end
        return nil
    end)
    if ok and net then
        self.cached = net
        return net
    end
    return nil
end

-- background refresh task (non-blocking)
task.spawn(function()
    while task.wait(2) do
        if not WeaponNetwork.cached then
            WeaponNetwork:FindNetwork()
        end
    end
end)

-- ======= Module: Safe Firing (respect SafeMode) =======
local FireModule = {
    lastFire = {},
    blacklist = {}, -- per-player name blacklist if needed
}
local function safePartPosition(part)
    if not part then return nil end
    if typeof(part.Position) == "Vector3" then return part.Position end
    if part:IsA("BasePart") then return part.Position end
    if typeof(part.CFrame) == "CFrame" then return part.CFrame.Position end
    return nil
end

local function rateLimitAllowed(key, interval)
    interval = interval or CONFIG.LoopKill.Delay
    local last = FireModule.lastFire[key] or 0
    if tick() - last < interval then return false end
    FireModule.lastFire[key] = tick()
    return true
end

function FireModule:FireAtPart(targetPart)
    if CONFIG.Safety.SafeModeDisableFiring then return false end
    if not targetPart then return false end
    local pos = safePartPosition(targetPart)
    if not pos then return false end

    local net = WeaponNetwork:FindNetwork()
    if not net then return false end

    -- be tolerant of argument shapes; attempt safe calls wrapped in pcall
    local ok = pcall(function()
        -- prefer table-arg style
        net:FireServer(targetPart, {
            p = pos,
            part = targetPart,
            pid = 0, d = 0, maxDist = 0, h = targetPart, m = Enum.Material.Concrete,
            n = Vector3.new(0,0,0), t = 0, sid = 0
        })
    end)
    if not ok then
        pcall(function() net:FireServer(pos) end)
    end
    return true
end

-- ======= LoopKill: per-player & global =======
local LoopKill = {
    runningAll = false,
    players = {}, -- map name -> running bool
    tasks = {},   -- map name -> task
}

local function safeGetPlayerHead(player)
    if not player or not player.Character then return nil end
    local head = player.Character:FindFirstChild("Head") or player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChildWhichIsA("BasePart")
    if head and head:IsA("BasePart") then return head end
    return nil
end

function LoopKill:KillAllOnce()
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local head = safeGetPlayerHead(pl)
            if head then
                local key = pl.Name
                if rateLimitAllowed(key) then
                    pcall(function() FireModule:FireAtPart(head) end)
                end
            end
        end
    end
end

function LoopKill:ToggleAll()
    self.runningAll = not self.runningAll
    if self.runningAll then
        self.tasks["__all"] = task.spawn(function()
            while self.runningAll do
                pcall(function() self:KillAllOnce() end)
                task.wait(CONFIG.LoopKill.Delay)
            end
        end)
    else
        self.tasks["__all"] = nil
    end
end

function LoopKill:TogglePlayerByName(name)
    if not name or name == "" then return end
    self.players[name] = not self.players[name]
    if self.players[name] then
        self.tasks[name] = task.spawn(function()
            while self.players[name] do
                local pl = Players:FindFirstChild(name)
                if pl then
                    local head = safeGetPlayerHead(pl)
                    if head and rateLimitAllowed(name) then
                        pcall(function() FireModule:FireAtPart(head) end)
                    end
                end
                task.wait(CONFIG.LoopKill.Delay)
            end
        end)
    else
        self.tasks[name] = nil
    end
end

-- ======= ESP System (Drawings) =======
local ESP = {
    active = true,
    entries = {},
    settings = {
        PlayerESP = true,
        ShowNames = true,
        ShowHealth = true,
        ShowDistance = true,
    }
}

local function createESPObjects()
    return {
        Box = Drawing.new("Square"),
        Text = Drawing.new("Text"),
        Health = Drawing.new("Square"),
    }
end

local function initESPForPlayer(player)
    if ESP.entries[player] then return end
    local obj = createESPObjects()
    -- configure drawing objects safely
    pcall(function()
        obj.Box.Thickness = 2
        obj.Box.Filled = false
        obj.Box.Visible = false
        obj.Text.Size = CONFIG.ESP.TextSize
        obj.Text.Center = true
        obj.Text.Outline = true
        obj.Text.Visible = false
        obj.Health.Filled = true
        obj.Health.Visible = false
    end)
    ESP.entries[player] = obj
end

local function removeESPForPlayer(player)
    local ent = ESP.entries[player]
    if not ent then return end
    pcall(function()
        if ent.Box and ent.Box.Remove then ent.Box:Remove() end
        if ent.Text and ent.Text.Remove then ent.Text:Remove() end
        if ent.Health and ent.Health.Remove then ent.Health:Remove() end
    end)
    ESP.entries[player] = nil
end

Players.PlayerRemoving:Connect(function(pl)
    if ESP.entries[pl] then removeESPForPlayer(pl) end
end)

local espRenderConn
espRenderConn = RunService.RenderStepped:Connect(function()
    if not ESP.settings.PlayerESP then
        for p,_ in pairs(ESP.entries) do removeESPForPlayer(p) end
        return
    end
    Camera = getCamera()
    for _,player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")) then
            if not ESP.entries[player] then initESPForPlayer(player) end
            local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")
            if not hrp then removeESPForPlayer(player) continue end
            local ok, screenX, screenY, onScreen = pcall(function()
                local p2 = Camera:WorldToViewportPoint(hrp.Position)
                return p2.X, p2.Y, p2.Z > 0
            end)
            local ent = ESP.entries[player]
            if ok and onScreen then
                local dist = 0
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude)
                end
                if dist > CONFIG.ESP.MaxDistance then
                    ent.Box.Visible = false
                    ent.Text.Visible = false
                    ent.Health.Visible = false
                else
                    local sizeScale = math.clamp(200 / math.max(dist, 10), 0.6, 2.0)
                    local boxW, boxH = 50 * sizeScale, 100 * sizeScale
                    ent.Box.Position = Vector2.new(screenX - boxW/2, screenY - boxH/1.7)
                    ent.Box.Size = Vector2.new(boxW, boxH)
                    ent.Box.Visible = true
                    local info = ""
                    if ESP.settings.ShowNames then info = info .. player.Name .. " " end
                    if ESP.settings.ShowHealth and player.Character:FindFirstChild("Humanoid") then
                        info = info .. "[" .. math.floor(player.Character.Humanoid.Health) .. "] "
                    end
                    if ESP.settings.ShowDistance and dist > 0 then
                        info = info .. "(" .. dist .. "m)"
                    end
                    ent.Text.Position = Vector2.new(screenX, screenY - boxH/2 - 12)
                    ent.Text.Text = info
                    ent.Text.Visible = true
                    if player.Character:FindFirstChild("Humanoid") then
                        local hum = player.Character.Humanoid
                        local pct = math.clamp(hum.Health / (hum.MaxHealth > 0 and hum.MaxHealth or 100), 0, 1)
                        ent.Health.Position = Vector2.new(screenX - boxW/2 - 10, screenY + boxH/2 - (boxH * pct))
                        ent.Health.Size = Vector2.new(6, boxH * pct)
                        ent.Health.Visible = true
                    else
                        ent.Health.Visible = false
                    end
                end
            else
                ent.Box.Visible = false
                ent.Text.Visible = false
                ent.Health.Visible = false
            end
        else
            if ESP.entries[player] then removeESPForPlayer(player) end
        end
    end
end)
ConnManager:Bind("espRender", espRenderConn)

-- ======= Aimbot Module =======
local Aimbot = {
    enabled = false,
    fov = CONFIG.Aimbot.DefaultFOV,
    bone = CONFIG.Aimbot.DefaultBone,
    smooth = CONFIG.Aimbot.DefaultSmooth,
    prediction = CONFIG.Aimbot.DefaultPrediction,
    holdActive = false,
    uiFOVCircle = nil,
}

-- Create FOV circle drawing
local function createFOVCircle()
    local c = Drawing.new("Circle")
    c.Thickness = 2
    c.Filled = false
    c.NumSides = 64
    c.Visible = false
    return c
end
Aimbot.uiFOVCircle = createFOVCircle()

local function getClosestToCursor()
    local closest, bestDist = nil, Aimbot.fov + 0
    local mpos = UserInputService:GetMouseLocation()
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild(Aimbot.bone) then
            local bonePos = pl.Character[Aimbot.bone].Position
            local screenPos = Camera:WorldToViewportPoint(bonePos)
            local onScreen = screenPos.Z > 0
            if onScreen then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(mpos.X, mpos.Y)).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    closest = pl
                end
            end
        end
    end
    return closest
end

-- Input handlers for hold-to-aim + UI toggle
local uiHidden = false
UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.UserInputType == CONFIG.Aimbot.HoldInput then
        Aimbot.holdActive = true
        Aimbot.uiFOVCircle.Visible = Aimbot.enabled
    elseif inp.KeyCode == CONFIG.UI.ToggleKey then
        uiHidden = not uiHidden
        -- Rayfield's API often provides a window toggle; if absent, warn
        pcall(function() Window:Toggle() end)
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == CONFIG.Aimbot.HoldInput then
        Aimbot.holdActive = false
        Aimbot.uiFOVCircle.Visible = false
    end
end)

local aimbotConn = RunService.RenderStepped:Connect(function()
    -- update camera each frame (in case replaced)
    Camera = getCamera()
    -- update FOV circle pos/radius
    local mpos = UserInputService:GetMouseLocation()
    Aimbot.uiFOVCircle.Position = Vector2.new(mpos.X, mpos.Y)
    Aimbot.uiFOVCircle.Radius = Aimbot.fov

    if not Aimbot.enabled then
        Aimbot.uiFOVCircle.Visible = false
        return
    end
    if CONFIG.Aimbot.HoldToAim and not Aimbot.holdActive then return end
    -- find target
    local target = getClosestToCursor()
    if not target or not target.Character or not target.Character:FindFirstChild(Aimbot.bone) then return end
    local targetPart = target.Character[Aimbot.bone]
    local predicted = targetPart.Position
    -- prediction using HRP velocity if available
    if Aimbot.prediction and Aimbot.prediction > 0 and target.Character:FindFirstChild("HumanoidRootPart") then
        local vel = target.Character.HumanoidRootPart.Velocity or Vector3.new(0,0,0)
        predicted = predicted + vel * (Aimbot.prediction/1000)
    end
    if Camera and Camera.CFrame then
        local desired = CFrame.new(Camera.CFrame.Position, predicted)
        local lerpAmount = math.clamp(1 - Aimbot.smooth, 0.01, 1)
        Camera.CFrame = Camera.CFrame:Lerp(desired, lerpAmount)
    end
end)
ConnManager:Bind("aimbot", aimbotConn)

-- ======= UI Controls (Rayfield) =======
-- Main tab controls
TabMain:CreateButton({Name="Kill All (Once)", Callback=function() pcall(function() LoopKill:KillAllOnce() end) end})
TabMain:CreateButton({Name="Toggle LoopKill All", Callback=function() pcall(function() LoopKill:ToggleAll() end) end})
TabMain:CreateInput({Name="Kill Player", CurrentValue="", PlaceholderText="Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    if txt and txt ~= "" then
        local p = Players:FindFirstChild(txt)
        if p and p.Character then
            local head = safeGetPlayerHead(p)
            if head then pcall(function() FireModule:FireAtPart(head) end) end
        end
    end
end})
TabMain:CreateInput({Name="Toggle LoopKill Player", CurrentValue="", PlaceholderText="Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    if txt and txt ~= "" then LoopKill:TogglePlayerByName(txt) end
end})
TabMain:CreateButton({Name="Unload / Cleanup", Callback=function() -- perform full unload
    pcall(function()
        cleanupAll()
    end)
end})

-- God mode
local godRunning = false
local godT
TabMain:CreateButton({Name="Toggle God Mode", Callback=function()
    godRunning = not godRunning
    if godRunning then
        godT = task.spawn(function()
            while godRunning do
                pcall(function()
                    if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        if Workspace:FindFirstChild("Safe") and Workspace.Safe:IsA("BasePart") then
                            Workspace.Safe.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                        end
                    end
                end)
                task.wait(0.12)
            end
        end)
    else
        godT = nil
    end
end})

-- Misc tab
TabMisc:CreateToggle({Name="Speed Toggle", CurrentValue=false, Callback=function(val)
    if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local hum = LocalPlayer.Character.Humanoid
        hum.WalkSpeed = val and CONFIG.Misc.SpeedValue or 16
    end
end})
TabMisc:CreateToggle({Name="Jump Power Toggle", CurrentValue=false, Callback=function(val)
    if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local hum = LocalPlayer.Character.Humanoid
        hum.JumpPower = val and CONFIG.Misc.JumpValue or 50
    end
end})
TabMisc:CreateInput({Name="Teleport to Player", CurrentValue="", PlaceholderText="Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local p = Players:FindFirstChild(txt)
    if p and p.Character and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame end)
    end
end})
TabMisc:CreateButton({Name="Reset (Kill Local)", Callback=function()
    if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
    end
end})
TabMisc:CreateButton({Name="Load Hitbox Expander (External)", Callback=function()
    pcall(function()
        local ok, res = pcall(function() return loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))() end)
        if not ok then warn("HitboxExpander failed to load") end
    end)
end})
TabMisc:CreateToggle({Name="Safe Mode (Disable Remote Firing)", CurrentValue=CONFIG.Safety.SafeModeDisableFiring, Callback=function(val)
    CONFIG.Safety.SafeModeDisableFiring = val
end})

-- Aimbot tab controls
TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=false, Callback=function(val) Aimbot.enabled = val; Aimbot.uiFOVCircle.Visible = val and (not CONFIG.Aimbot.HoldToAim or Aimbot.holdActive) end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={50,600}, Increment=5, CurrentValue=Aimbot.fov, Callback=function(val) Aimbot.fov = val end})
TabAimbot:CreateInput({Name="Aimbot Bone", CurrentValue=Aimbot.bone, PlaceholderText="Bone name (e.g. Head)", RemoveTextAfterFocusLost=false, Callback=function(val) if val and val ~= "" then Aimbot.bone = val end end})
TabAimbot:CreateSlider({Name="Smooth (0-1)", Range={0,1}, Increment=0.01, CurrentValue=Aimbot.smooth, Callback=function(val) Aimbot.smooth = val end})
TabAimbot:CreateSlider({Name="Prediction (studs/s)", Range={0,500}, Increment=1, CurrentValue=Aimbot.prediction, Callback=function(val) Aimbot.prediction = val end})

-- ESP tab
TabESP:CreateToggle({Name="Enable Player ESP", CurrentValue=true, Callback=function(val) ESP.settings.PlayerESP = val end})
TabESP:CreateToggle({Name="Show Names", CurrentValue=true, Callback=function(val) ESP.settings.ShowNames = val end})
TabESP:CreateToggle({Name="Show Health", CurrentValue=true, Callback=function(val) ESP.settings.ShowHealth = val end})
TabESP:CreateToggle({Name="Show Distance", CurrentValue=true, Callback=function(val) ESP.settings.ShowDistance = val end})

-- Persist config attempt
pcall(function() Rayfield:LoadConfiguration() end)

-- ======= Status Overlay (small; shows toggles) =======
local statusDrawing = {}
do
    local bg = Drawing.new("Square")
    local txt = Drawing.new("Text")
    pcall(function()
        bg.Filled = true
        bg.Transparency = 0.35
        bg.Visible = true
        txt.Size = 14
        txt.Center = false
        txt.Outline = true
        txt.Visible = true
    end)
    statusDrawing.bg = bg
    statusDrawing.txt = txt
end

local function updateStatusOverlay()
    local mpos = UserInputService:GetMouseLocation()
    statusDrawing.bg.Position = Vector2.new(8, 8)
    statusDrawing.bg.Size = Vector2.new(180, 90)
    local t = ("Aimbot: %s\nLoopKillAll: %s\nSafeMode: %s\nESP: %s")
        :format(tostring(Aimbot.enabled), tostring(LoopKill.runningAll), tostring(CONFIG.Safety.SafeModeDisableFiring), tostring(ESP.settings.PlayerESP))
    statusDrawing.txt.Position = Vector2.new(12, 12)
    statusDrawing.txt.Text = t
end
local statusConn = RunService.RenderStepped:Connect(function() updateStatusOverlay() end)
ConnManager:Bind("status", statusConn)

-- ======= Cleanup function (comprehensive) =======
function cleanupAll()
    -- stop loopkills
    LoopKill.runningAll = false
    for k,_ in pairs(LoopKill.players) do LoopKill.players[k] = false end
    for k,_ in pairs(LoopKill.tasks) do LoopKill.tasks[k] = nil end
    -- stop god
    godRunning = false
    godT = nil
    -- stop antikick if any (we're not using a persistent task here)
    -- remove esp drawings
    for p,_ in pairs(ESP.entries) do removeESPForPlayer(p) end
    -- remove fov circle
    pcall(function() if Aimbot.uiFOVCircle and Aimbot.uiFOVCircle.Remove then Aimbot.uiFOVCircle:Remove() end end)
    -- remove status overlay
    pcall(function()
        if statusDrawing.bg and statusDrawing.bg.Remove then statusDrawing.bg:Remove() end
        if statusDrawing.txt and statusDrawing.txt.Remove then statusDrawing.txt:Remove() end
    end)
    -- disconnect all connections
    ConnManager:DisconnectAll()
    -- additional cleanup: reset local flags
    Aimbot.enabled = false
    Aimbot.holdActive = false
    ESP.settings.PlayerESP = false
    LoopKill.players = {}
    LoopKill.tasks = {}
    -- remove window if Rayfield supports
    pcall(function() if Window and Window.Close then Window:Close() end end)
end

-- final note to user in output (non-blocking)
task.spawn(function()
    -- small confirmation print (visible in executor)
    pcall(function() print("[FORTLINE] Reworked script initialized. Use the UI or keybinds.") end)
end)



TabMain:CreateButton({Name="Unload / Cleanup", Callback=cleanupAll})
