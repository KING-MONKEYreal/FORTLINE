local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local Camera = Workspace:FindFirstChildOfClass("Camera") or Workspace.CurrentCamera

-- ===== Rayfield UI =====
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "FORTLINE BIG UPDATE 2025",
    Icon = 0,
    LoadingTitle = "LOADING",
    LoadingSubtitle = "by Chance",
    Theme = "Default",
    ConfigurationSaving = {Enabled=true, FolderName=nil, FileName="FORTLINE_PRO_2025_CFG"},
})

-- Tabs: Main, Combat, ESP, Aimbot, Movement, Settings
local TabMain    = Window:CreateTab("Main",    4483362458)
local TabCombat  = Window:CreateTab("Combat",  4483362458)
local TabESP     = Window:CreateTab("ESP",     4483362458)
local TabAimbot  = Window:CreateTab("Aimbot",  4483362458)
local TabMove    = Window:CreateTab("Movement",4483362458)
local TabSettings= Window:CreateTab("Settings",4483362458)

-- ===== Internal state =====
local Connections = {}
local Drawings = {} -- store any drawing objects for cleanup
local PlayersESP = {}
local LoopKillAllRunning = false
local LoopKillPlayers = {} -- name -> bool
local GodRunning = false
local AntiKickRunning = true

-- ===== Cached remote finder =====
local function safeFindWeaponsNetwork()
    local ok, net = pcall(function()
        local ws = ReplicatedStorage:FindFirstChild("WeaponsSystem")
        if not ws then return nil end
        local network = ws:FindFirstChild("Network")
        if not network then return nil end
        return network:FindFirstChild("WeaponHit") or network:FindFirstChild("WeaponHit")
    end)
    return ok and net or nil
end
local cachedWeaponNetwork = safeFindWeaponsNetwork()
-- attempt a short wait if nil
if not cachedWeaponNetwork then
    task.spawn(function()
        pcall(function()
            cachedWeaponNetwork = ReplicatedStorage:WaitForChild("WeaponsSystem", 2)
                and ReplicatedStorage.WeaponsSystem:WaitForChild("Network", 2)
                and ReplicatedStorage.WeaponsSystem.Network:FindFirstChild("WeaponHit")
        end)
    end)
end

-- ===== Utilities =====
local function safeFire(weapon, args)
    if not weapon or not cachedWeaponNetwork then return end
    pcall(function() cachedWeaponNetwork:FireServer(weapon, args) end)
end

local function findRocketLauncher()
    local w = (LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("RocketLauncher"))
           or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RocketLauncher"))
    return w
end

local function isPartValid(part)
    return part and typeof(part.Position) == "Vector3" and part:IsA("BasePart")
end

-- ===== Combat: Fire helper, Kill All, Loop Kill player =====
local function FireWeaponAtPart(part)
    if not isPartValid(part) then return false end
    local weapon = findRocketLauncher()
    if not weapon then return false end
    if not cachedWeaponNetwork then cachedWeaponNetwork = safeFindWeaponsNetwork() end
    if not cachedWeaponNetwork then return false end

    pcall(function()
        cachedWeaponNetwork:FireServer(weapon, {
            p = part.Position,
            pid = 0,
            part = part,
            d = 0, maxDist = 0, h = part, m = Enum.Material.Concrete,
            n = Vector3.new(0,0,0), t = 0, sid = 0
        })
    end)
    return true
end

local function KillAll()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local head = pl.Character:FindFirstChild("Head") or pl.Character:FindFirstChild("HumanoidRootPart")
            if head and head:IsA("BasePart") then
                pcall(function() FireWeaponAtPart(head) end)
            end
        end
    end
end

local function ToggleLoopKillAll()
    LoopKillAllRunning = not LoopKillAllRunning
    if LoopKillAllRunning then
        task.spawn(function()
            while LoopKillAllRunning do
                pcall(KillAll)
                task.wait(0.5)
            end
        end)
    end
end

local function ToggleLoopKillPlayer(name)
    if not name or name == "" then return end
    LoopKillPlayers[name] = not LoopKillPlayers[name]
    if LoopKillPlayers[name] then
        task.spawn(function()
            while LoopKillPlayers[name] do
                local p = Players:FindFirstChild(name)
                if p and p.Character then
                    local head = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
                    if head and head:IsA("BasePart") then
                        pcall(function() FireWeaponAtPart(head) end)
                    end
                end
                task.wait(0.5)
            end
        end)
    end
end

-- Combat UI
TabCombat:CreateButton({Name="Kill All (once)", Callback=function() pcall(KillAll) end})
TabCombat:CreateButton({Name="Toggle LoopKill All", Callback=ToggleLoopKillAll})
TabCombat:CreateInput({Name="Kill Player (once)", CurrentValue="", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local p = Players:FindFirstChild(txt)
    if p and p.Character then
        local head = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
        if head then FireWeaponAtPart(head) end
    end
end})
TabCombat:CreateInput({Name="Toggle LoopKill Player", CurrentValue="", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false, Callback=ToggleLoopKillPlayer})

-- ===== God Mode (improved) =====
local function ToggleGod()
    GodRunning = not GodRunning
    if GodRunning then
        task.spawn(function()
            while GodRunning do
                pcall(function()
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local safePart = Workspace:FindFirstChild("Safe")
                        if safePart and safePart:IsA("BasePart") then
                            safePart.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                        end
                    end
                end)
                task.wait(0.1)
            end
        end)
    end
end
TabMain:CreateButton({Name="Toggle God Mode", Callback=ToggleGod})

-- ===== Reset =====
TabMain:CreateButton({Name="Reset (Ragdoll)", Callback=function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
    end
end})

-- ===== Hitbox Expander (external) =====
TabMain:CreateButton({Name="Hitbox Expander (external)", Callback=function()
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))()
    end)
end})

-- ===== Movement: Speed, Jump, Fly, Noclip, Teleport UI =====
local defaultSpeed, defaultJump = 16, 50
local speedValue, jumpValue = defaultSpeed, defaultJump
local speedEnabled, jumpEnabled = false, false
local FlyActive = false
local FlySpeed = 70
local NoclipActive = false

local function UpdateHumanoid()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local hum = LocalPlayer.Character.Humanoid
        hum.WalkSpeed = speedEnabled and speedValue or defaultSpeed
        hum.JumpPower = jumpEnabled and jumpValue or defaultJump
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    UpdateHumanoid()
end)

TabMove:CreateToggle({Name="Speed Enabled", CurrentValue=false, Callback=function(val) speedEnabled = val UpdateHumanoid() end})
TabMove:CreateSlider({Name="Speed", Range={16,200}, Increment=1, CurrentValue=50, Callback=function(v) speedValue = v UpdateHumanoid() end})

TabMove:CreateToggle({Name="Jump Enabled", CurrentValue=false, Callback=function(val) jumpEnabled = val UpdateHumanoid() end})
TabMove:CreateSlider({Name="Jump Power", Range={50,300}, Increment=1, CurrentValue=100, Callback=function(v) jumpValue = v UpdateHumanoid() end})

TabMove:CreateToggle({Name="Fly (Hold F)", CurrentValue=false, Callback=function(val)
    FlyActive = val
end})
TabMove:CreateSlider({Name="Fly Speed", Range={20,200}, Increment=1, CurrentValue=FlySpeed, Callback=function(v) FlySpeed = v end})
TabMove:CreateToggle({Name="Noclip (Toggle N)", CurrentValue=false, Callback=function(v) NoclipActive = v end})
TabMove:CreateInput({Name="Teleport to Player", CurrentValue="", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local p = Players:FindFirstChild(txt)
    if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame end)
    end
end})

-- Fly implementation
local bodyVel
task.spawn(function()
    while task.wait() do
        if FlyActive and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = LocalPlayer.Character.HumanoidRootPart
            if not bodyVel or not bodyVel.Parent then
                bodyVel = Instance.new("BodyVelocity")
                bodyVel.MaxForce = Vector3.new(1e5,1e5,1e5)
                bodyVel.Velocity = Vector3.new(0,0,0)
                bodyVel.Parent = hrp
            end
            local camCf = Camera and Camera.CFrame or CFrame.new()
            local forward = camCf.LookVector
            local right = camCf.RightVector
            local move = Vector3.new(0,0,0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - right end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + right end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0,1,0) end
            bodyVel.Velocity = move.Unit == move.Unit and move.Unit * FlySpeed or Vector3.new(0,0,0)
        else
            if bodyVel then
                pcall(function() bodyVel:Destroy() end)
                bodyVel = nil
            end
        end
    end
end)

-- Noclip implementation
task.spawn(function()
    while task.wait(0.25) do
        if NoclipActive and LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end
    end
end)

-- ===== Anti-kick / Anti-AFK =====
task.spawn(function()
    while AntiKickRunning do
        pcall(function()
            if LocalPlayer and LocalPlayer.SetAttribute then
                LocalPlayer:SetAttribute("PreventKick", true)
            end
            -- anti-AFK: send a controller input
            pcall(function() StarterGui:SetCore("ResetButtonCallback", true) end)
        end)
        task.wait(1)
    end
end)

-- ===== ESP System (improved) =====
local ESPSettings = {
    Enabled = true,
    ShowNames = true,
    ShowHealth = true,
    ShowDistance = true,
    Tracers = true,
    BoxScale = 1.0,
    TeamColor = true,
}

TabESP:CreateToggle({Name="Enable ESP", CurrentValue=true, Callback=function(v) ESPSettings.Enabled = v end})
TabESP:CreateToggle({Name="Show Names", CurrentValue=true, Callback=function(v) ESPSettings.ShowNames = v end})
TabESP:CreateToggle({Name="Show Health", CurrentValue=true, Callback=function(v) ESPSettings.ShowHealth = v end})
TabESP:CreateToggle({Name="Show Distance", CurrentValue=true, Callback=function(v) ESPSettings.ShowDistance = v end})
TabESP:CreateToggle({Name="Tracers", CurrentValue=true, Callback=function(v) ESPSettings.Tracers = v end})
TabESP:CreateSlider({Name="Box Scale", Range={0.5,2.5}, Increment=0.1, CurrentValue=1.0, Callback=function(v) ESPSettings.BoxScale = v end})
TabESP:CreateToggle({Name="Team color tags", CurrentValue=true, Callback=function(v) ESPSettings.TeamColor = v end})

-- Drawing helpers
local function newSquare()
    local sq = Drawing.new("Square")
    sq.Thickness = 2
    sq.Filled = false
    sq.Visible = false
    return sq
end
local function newText()
    local t = Drawing.new("Text")
    t.Size = 16
    t.Center = true
    t.Outline = true
    t.Visible = false
    return t
end
local function newLine()
    local l = Drawing.new("Line")
    l.Thickness = 1
    l.Visible = false
    return l
end

-- cleanup utility
local function cleanupESPForPlayer(player)
    if PlayersESP[player] then
        pcall(function()
            if PlayersESP[player].Box then PlayersESP[player].Box:Remove() end
            if PlayersESP[player].Text then PlayersESP[player].Text:Remove() end
            if PlayersESP[player].Tracer then PlayersESP[player].Tracer:Remove() end
        end)
        PlayersESP[player] = nil
    end
end

Players.PlayerRemoving:Connect(function(plr)
    cleanupESPForPlayer(plr)
end)

-- ESP render loop
Connections.ESP = RunService.RenderStepped:Connect(function()
    if not ESPSettings.Enabled then
        for p,_ in pairs(PlayersESP) do cleanupESPForPlayer(p) end
        return
    end

    for _,player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")) then
            if not PlayersESP[player] then
                PlayersESP[player] = {
                    Box = newSquare(),
                    Text = newText(),
                    Tracer = newLine()
                }
            end

            local root = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")
            if not root then cleanupESPForPlayer(player); continue end
            local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
            local data = PlayersESP[player]
            local box = data.Box; local text = data.Text; local tracer = data.Tracer

            if onScreen then
                local dist = 0
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Magnitude)
                end

                -- scale box by distance
                local scale = math.clamp(200 / math.max(dist, 10), 0.7, 2.0) * ESPSettings.BoxScale
                local w,h = 50 * scale, 100 * scale
                box.Position = Vector2.new(screenPos.X - w/2, screenPos.Y - h/1.8)
                box.Size = Vector2.new(w, h)
                box.Color = (ESPSettings.TeamColor and (player.Team and (player.Team.TeamColor.Color) or Color3.fromRGB(255,0,0))) or Color3.fromRGB(255,0,0)
                box.Visible = true

                -- text info
                local info = ""
                if ESPSettings.ShowNames then info = info .. player.Name .. " " end
                if ESPSettings.ShowHealth and player.Character:FindFirstChild("Humanoid") then
                    info = info .. "[" .. math.floor(player.Character.Humanoid.Health) .. "] "
                end
                if ESPSettings.ShowDistance then info = info .. "("..dist.."m)" end
                text.Position = Vector2.new(screenPos.X, screenPos.Y - h/2 - 14)
                text.Text = info
                text.Color = Color3.fromRGB(255,255,255)
                text.Visible = true

                if ESPSettings.Tracers then
                    tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y) -- bottom centre
                    tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                    tracer.Color = box.Color
                    tracer.Visible = true
                else
                    tracer.Visible = false
                end
            else
                box.Visible = false; text.Visible = false; tracer.Visible = false
            end
        else
            if PlayersESP[player] then cleanupESPForPlayer(player) end
        end
    end
end)

-- ===== Aimbot: Hold-to-aim, Legit, Smoothing, FOV circle, Silent Aim =====
local Aimbot = {
    Enabled = false,
    HoldToAim = true,
    AimKey = Enum.UserInputType.MouseButton2, -- Right mouse
    FOV = 120,
    Smooth = 0.25,
    Bone = "HumanoidRootPart",
    Legit = false, -- lower smoothing & randomization
    SilentAim = false, -- when true, FireWeaponAtPart is used directly (no camera move)
    AutoHeadshot = false,
    DrawFOV = true,
    FOVCircle = nil
}

-- FOV circle drawing
local function createFOVCircle()
    if Aimbot.FOVCircle then
        pcall(function() Aimbot.FOVCircle:Remove() end)
    end
    local circ = Drawing.new("Circle")
    circ.Radius = Aimbot.FOV
    circ.Filled = false
    circ.Transparency = 1
    circ.Thickness = 1
    circ.Visible = Aimbot.DrawFOV
    Aimbot.FOVCircle = circ
end
createFOVCircle()

TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=false, Callback=function(v) Aimbot.Enabled = v end})
TabAimbot:CreateToggle({Name="Hold-to-Aim (RMB)", CurrentValue=true, Callback=function(v) Aimbot.HoldToAim = v end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={50,500}, Increment=1, CurrentValue=Aimbot.FOV, Callback=function(v) Aimbot.FOV = v if Aimbot.FOVCircle then Aimbot.FOVCircle.Radius = v end end})
TabAimbot:CreateSlider({Name="Smoothing", Range={0.01,0.8}, Increment=0.01, CurrentValue=Aimbot.Smooth, Callback=function(v) Aimbot.Smooth = v end})
TabAimbot:CreateInput({Name="Aim Bone", CurrentValue="HumanoidRootPart", PlaceholderText="Bone name", RemoveTextAfterFocusLost=false, Callback=function(v) if v and v ~= "" then Aimbot.Bone = v end end})
TabAimbot:CreateToggle({Name="Legit Mode (subtle)", CurrentValue=false, Callback=function(v) Aimbot.Legit = v end})
TabAimbot:CreateToggle({Name="Silent Aim (fire w/out camera)", CurrentValue=false, Callback=function(v) Aimbot.SilentAim = v end})
TabAimbot:CreateToggle({Name="Auto Headshot", CurrentValue=false, Callback=function(v) Aimbot.AutoHeadshot = v end})
TabAimbot:CreateToggle({Name="Show FOV Circle", CurrentValue=true, Callback=function(v) Aimbot.DrawFOV = v if Aimbot.FOVCircle then Aimbot.FOVCircle.Visible = v end end})
TabAimbot:CreateInput({Name="Aim Hotkey (for HoldToAim leave empty)", CurrentValue="", PlaceholderText="E.g. Q", RemoveTextAfterFocusLost=false, Callback=function(v)
    -- optional: map a single-key hotkey to toggle aim while HoldToAim disabled
    -- handled below via InputBegan/Ended
end})

-- Helper to get mouse position
local function getMousePos()
    local mousePos = UserInputService:GetMouseLocation()
    -- On some exploits mouseY includes topbar offset; Camera.ViewportSize is used in FOV circle positioning
    return Vector2.new(mousePos.X, mousePos.Y)
end

-- find closest player within FOV (screen-space)
local function getClosestInFOV()
    local closest, best = nil, Aimbot.FOV + 0
    local mouse = getMousePos()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild(Aimbot.Bone) then
            local pos = pl.Character[Aimbot.Bone].Position
            local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
            if onScreen then
                local d = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
                if d < best then
                    best = d
                    closest = pl
                end
            end
        end
    end
    return closest, best
end

-- Draw FOV circle updating
Connections.FOV = RunService.RenderStepped:Connect(function()
    if Aimbot.FOVCircle and Aimbot.DrawFOV then
        local view = Camera and Camera.ViewportSize or Vector2.new(800,600)
        Aimbot.FOVCircle.Position = getMousePos()
        Aimbot.FOVCircle.Radius = Aimbot.FOV
        Aimbot.FOVCircle.Visible = Aimbot.Enabled and Aimbot.DrawFOV
    end
end)

-- Aim actions: move camera to look at target (smooth) OR silent-fire
local function aimAtPlayer(pl)
    if not pl or not pl.Character or not pl.Character:FindFirstChild(Aimbot.Bone) then return end
    local targetPos = pl.Character[Aimbot.Bone].Position
    if Aimbot.SilentAim then
        -- Fire directly at head or specified bone (silent)
        local aimPart = (Aimbot.AutoHeadshot and pl.Character:FindFirstChild("Head")) or pl.Character[Aimbot.Bone]
        if aimPart then FireWeaponAtPart(aimPart) end
    else
        -- Move camera towards target smoothly
        local smooth = Aimbot.Legit and math.max(Aimbot.Smooth * 1.8, 0.05) or Aimbot.Smooth
        if Camera and Camera.CFrame then
            pcall(function()
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, targetPos), smooth)
            end)
        end
    end
end

-- Input handling for hold-to-aim
local aiming = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    -- Right mouse for hold-to-aim
    if Aimbot.HoldToAim and input.UserInputType == Aimbot.AimKey then
        aiming = true
    end
    -- example single-key toggle (Q) for manual aim if not hold-to-aim
    if not Aimbot.HoldToAim and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Q then
        aiming = not aiming
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if Aimbot.HoldToAim and input.UserInputType == Aimbot.AimKey then
        aiming = false
    end
end)

-- Aimbot loop
Connections.Aimbot = RunService.RenderStepped:Connect(function()
    if not Aimbot.Enabled then return end
    if Aimbot.HoldToAim and not aiming then return end

    local target, dist = getClosestInFOV()
    if target and dist <= Aimbot.FOV then
        aimAtPlayer(target)
    end
end)

-- ===== FPS & Ping monitor =====
local FPS = 0
local lastTick = tick()
local frameCount = 0
Connections.FPS = RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if tick() - lastTick >= 1 then
        FPS = frameCount / (tick() - lastTick)
        frameCount = 0
        lastTick = tick()
    end
end)

-- Ping: try to use stats from RunService or network object if available (best-effort)
local Ping = 0
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            -- some exploits expose GetNetworkStats or similar; we fallback to 0
            local ok, res = pcall(function() return Workspace:GetServerTimeNow() end)
            Ping = 0 -- best-effort; leave 0 if not available
            -- alternative methods are exploit-dependent; keep ping as 0 fallback
        end)
    end
end)

-- show FPS/Ping in top-left using Drawing
local fpsText = Drawing.new("Text")
fpsText.Position = Vector2.new(8,8)
fpsText.Size = 16
fpsText.Outline = true
fpsText.Center = false
fpsText.Visible = true
Connections.FPSText = RunService.RenderStepped:Connect(function()
    fpsText.Text = string.format("FPS: %d  Ping: %dms", math.floor(FPS), math.floor(Ping))
    fpsText.Color = Color3.fromRGB(255,255,255)
end)
table.insert(Drawings, fpsText)

-- ===== Settings / Hotkeys / Cleanup =====
-- Hotkeys
local Hotkeys = {
    {key = Enum.KeyCode.N, action = function() NoclipActive = not NoclipActive end, desc = "Toggle Noclip"},
    {key = Enum.KeyCode.F, action = function() FlyActive = not FlyActive end, desc = "Toggle Fly"},
    {key = Enum.KeyCode.B, action = function() Aimbot.Enabled = not Aimbot.Enabled end, desc = "Toggle Aimbot"},
    {key = Enum.KeyCode.K, action = function() ToggleLoopKillAll() end, desc = "Toggle LoopKill All"},
}
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        for _,h in ipairs(Hotkeys) do
            if input.KeyCode == h.key then
                pcall(h.action)
            end
        end
    end
end)

-- Settings UI
TabSettings:CreateLabel({Name="Hotkeys (N:Noclip, F:Fly, B:Aimbot, K:LoopKillAll)"})
TabSettings:CreateButton({Name="Unload / Cleanup (SAFE)", Callback=function()
    -- call cleanup (defined below)
    cleanupAll()
end})
TabSettings:CreateButton({Name="Reload Config", Callback=function() pcall(function() Rayfield:LoadConfiguration() end) end})

-- ===== Cleanup handler (disconnects + remove drawings) =====
function cleanupAll()
    -- stop loops/state
    LoopKillAllRunning = false
    for k,_ in pairs(LoopKillPlayers) do LoopKillPlayers[k] = false end
    GodRunning = false
    FlyActive = false
    NoclipActive = false
    Aimbot.Enabled = false
    AntiKickRunning = false

    -- disconnect connections
    for k,conn in pairs(Connections) do
        if conn and typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        end
        Connections[k] = nil
    end

    -- remove all drawing objects produced by this script
    for _,obj in ipairs(Drawings) do
        pcall(function() obj:Remove() end)
    end
    Drawings = {}

    for p,_ in pairs(PlayersESP) do cleanupESPForPlayer(p) end
    PlayersESP = {}

    -- destroy FOV circle
    if Aimbot.FOVCircle then pcall(function() Aimbot.FOVCircle:Remove() end) end

    -- unset any attributes
    pcall(function() if LocalPlayer and LocalPlayer.SetAttribute then LocalPlayer:SetAttribute("PreventKick", nil) end end)
end

-- Ensure Rayfield config loads (if present)
pcall(function() Rayfield:LoadConfiguration() end)

-- Auto-unload if player leaves or resets (best-effort)
LocalPlayer.AncestryChanged:Connect(function()
    if not LocalPlayer.Parent then
        pcall(cleanupAll)
    end
end)

-- End of script
print("FORTLINE PRO 2025 — BIG UPDATE loaded. Use tabs/hotkeys to control features.")
