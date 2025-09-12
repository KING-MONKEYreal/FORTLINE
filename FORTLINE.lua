--[[
    Fortline PRO 2025 — Updated & Hardened (by Zero)
    - Safer network calls, robust nil checks
    - ESP: colors, thickness, dynamic box size, per-player lifecycle
    - Aimbot: smooth lerp, hold-to-aim keybind, bone pick
    - LoopKill / Kill: safe remote lookups, respects missing weapon
    - Misc: Attach-like safe behaviour, Speed/Jump toggles, Teleport
    - Anti-kick: less noisy, kept in pcall
    - Resource cleanup: proper removal when player leaves or script unloads
    - Config persistence via Rayfield Load/Save (uses existing Rayfield API)
]]

-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

-- GUI (Rayfield)
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Fortline PRO 2025 - ZERO",
    Icon = 0,
    LoadingTitle = "Fortline Big Update",
    LoadingSubtitle = "by Chance",
    Theme = "Default",
    ConfigurationSaving = {Enabled=true, FileName="FORTLINE_PRO_2025_PLUS"},
})

local TabMain   = Window:CreateTab("Main", 4483362458)
local TabESP    = Window:CreateTab("ESP", 4483362458)
local TabMisc   = Window:CreateTab("Misc", 4483362458)
local TabAimbot = Window:CreateTab("Aimbot", 4483362458)
local TabFun    = Window:CreateTab("Fun", 4483362458)
local TabConfig = Window:CreateTab("Config", 4483362458)

-- CONFIG (defaults)
local Config = {
    Kill = {LoopAll=false, LoopPlayerName="", Delay=0.5},
    God = {Enabled=false},
    Speed = {Enabled=false, WalkSpeed=50},
    Jump = {Enabled=false, JumpPower=100},
    ESP = {Enabled=true, ShowNames=true, ShowHealth=true, ShowDistance=true, TeamColor=false, BoxSize=Vector2.new(50,100), Thickness=2, Color={255,0,0}},
    Aimbot = {Enabled=false, FOV=100, Bone="HumanoidRootPart", Smooth=0.25, HoldToAim=false, AimKey=Enum.KeyCode.E},
}

-- helpers
local function safeFind(t, ...)
    if not t then return nil end
    return t:FindFirstChild(...)
end

local function GetWeaponRemote()
    local ok, rs = pcall(function() return ReplicatedStorage:FindFirstChild("WeaponsSystem") end)
    if not ok or not rs then return nil end
    local net = safeFind(rs, "Network")
    if not net then return nil end
    return safeFind(net, "WeaponHit")
end

local function FireWeaponAtPart(targetPart)
    if not (targetPart and targetPart:IsA("BasePart")) then return false end
    pcall(function()
        local weapon = LocalPlayer.Backpack:FindFirstChild("RocketLauncher") or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RocketLauncher"))
        if not weapon then return end
        local remote = GetWeaponRemote()
        if not remote then return end
        remote:FireServer(weapon, {
            p = targetPart.Position, pid = 0, part = targetPart,
            d = 0, maxDist = 0, h = targetPart, m = Enum.Material.Concrete,
            n = Vector3.zero, t = 0, sid = 0
        })
    end)
    return true
end

-- CLEANUP UTILS
local PlayersESP = {} -- maps player -> {Box,Text}
local CreatedConnections = {} -- store connections for easy disconnect

local function disconnectAll()
    for _, c in pairs(CreatedConnections) do
        pcall(function() c:Disconnect() end)
    end
    CreatedConnections = {}
end

local function clearAllESP()
    for p,data in pairs(PlayersESP) do
        if data.Box then pcall(function() data.Box:Remove() end) end
        if data.Text then pcall(function() data.Text:Remove() end) end
        PlayersESP[p] = nil
    end
end

-- PLAYER DRAWING LIFECYCLE
local function createESPForPlayer(player)
    if PlayersESP[player] then return PlayersESP[player] end
    local box = Drawing.new("Square")
    box.Filled = false
    box.Thickness = Config.ESP.Thickness
    box.Color = Color3.fromRGB(unpack(Config.ESP.Color))
    local text = Drawing.new("Text")
    text.Center = true
    text.Size = 16
    text.Outline = true
    PlayersESP[player] = {Box = box, Text = text}
    return PlayersESP[player]
end

local function removeESPForPlayer(player)
    if PlayersESP[player] then
        local d = PlayersESP[player]
        if d.Box then pcall(function() d.Box:Remove() end) end
        if d.Text then pcall(function() d.Text:Remove() end) end
        PlayersESP[player] = nil
    end
end

-- PLAYER ADDED / REMOVED
table.insert(CreatedConnections, Players.PlayerRemoving:Connect(function(plr)
    removeESPForPlayer(plr)
end))

table.insert(CreatedConnections, Players.PlayerAdded:Connect(function(plr)
    -- Nothing required on add, will lazily create esp
end))

-- KILL SYSTEM
local LoopKillRunning = false
local function KillAll()
    for _,v in ipairs(Players:GetPlayers()) do
        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("Head") then
            FireWeaponAtPart(v.Character.Head)
        end
    end
end

local function ToggleLoopKillAll()
    LoopKillRunning = not LoopKillRunning
    task.spawn(function()
        while LoopKillRunning do
            pcall(KillAll)
            task.wait(Config.Kill.Delay or 0.5)
        end
    end)
end

local runningLoopKillPlayer = {}
local function ToggleLoopKillPlayer(playerName)
    if runningLoopKillPlayer[playerName] then
        runningLoopKillPlayer[playerName] = nil
        return
    end
    runningLoopKillPlayer[playerName] = true
    task.spawn(function()
        while runningLoopKillPlayer[playerName] do
            local player = Players:FindFirstChild(playerName)
            if player and player.Character and player.Character:FindFirstChild("Head") then
                FireWeaponAtPart(player.Character.Head)
            end
            task.wait(Config.Kill.Delay or 0.5)
        end
    end)
end

-- GUI: Main
TabMain:CreateButton({Name="Kill All (once)", Callback=KillAll})
TabMain:CreateButton({Name="Toggle LoopKill All", Callback=ToggleLoopKillAll})
TabMain:CreateInput({
    Name="Kill Player (once)", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local p = Players:FindFirstChild(txt)
        if p and p.Character and p.Character:FindFirstChild("Head") then
            FireWeaponAtPart(p.Character.Head)
        end
    end
})
TabMain:CreateInput({
    Name="Toggle LoopKill Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=function(txt) ToggleLoopKillPlayer(txt) end
})

-- GOD MODE
local GodRunning = false
local function ToggleGod()
    GodRunning = not GodRunning
    task.spawn(function()
        while GodRunning do
            pcall(function()
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and workspace:FindFirstChild("Safe") then
                    workspace.Safe.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                end
            end)
            task.wait(0.12)
        end
    end)
end
TabMain:CreateButton({Name="Toggle God Mode", Callback=ToggleGod})

-- RESET
TabMain:CreateButton({Name="Reset (Suicide)", Callback=function()
    pcall(function()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Health = 0
        end
    end)
end})

TabMain:CreateButton({Name="Open Hitbox Expander", Callback=function()
    pcall(function() loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))() end)
end})

-- MISC: Speed & Jump & Teleport
local defaultSpeed, defaultJump = 16, 50
local function UpdateHumanoidSettings()
    pcall(function()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local humanoid = LocalPlayer.Character.Humanoid
            humanoid.WalkSpeed = Config.Speed.Enabled and Config.Speed.WalkSpeed or defaultSpeed
            humanoid.JumpPower = Config.Jump.Enabled and Config.Jump.JumpPower or defaultJump
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.8)
    UpdateHumanoidSettings()
end)

TabMisc:CreateToggle({
    Name="Speed Toggle", CurrentValue=false,
    Callback=function(val)
        Config.Speed.Enabled = val
        UpdateHumanoidSettings()
    end
})
TabMisc:CreateInput({
    Name="Set Speed", CurrentValue=tostring(Config.Speed.WalkSpeed), PlaceholderText="WalkSpeed", RemoveTextAfterFocusLost=false,
    Callback=function(val)
        local n = tonumber(val)
        if n then Config.Speed.WalkSpeed = n; UpdateHumanoidSettings() end
    end
})
TabMisc:CreateToggle({
    Name="Jump Toggle", CurrentValue=false,
    Callback=function(val)
        Config.Jump.Enabled = val
        UpdateHumanoidSettings()
    end
})
TabMisc:CreateInput({
    Name="Set JumpPower", CurrentValue=tostring(Config.Jump.JumpPower), PlaceholderText="JumpPower",
    Callback=function(val)
        local n = tonumber(val)
        if n then Config.Jump.JumpPower = n; UpdateHumanoidSettings() end
    end
})
TabMisc:CreateInput({
    Name="Teleport to Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local p = Players:FindFirstChild(txt)
        if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            pcall(function()
                LocalPlayer.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame
            end)
        end
    end
})

-- Anti-Kick (gentle)
task.spawn(function()
    while true do
        pcall(function()
            if LocalPlayer then
                LocalPlayer:SetAttribute("PreventKick", true)
            end
        end)
        task.wait(2 + (math.random() * 1.5))
    end
end)

-- ESP: UI controls
TabESP:CreateToggle({Name="Enable ESP", CurrentValue=Config.ESP.Enabled, Callback=function(v) Config.ESP.Enabled=v end})
TabESP:CreateToggle({Name="Show Names", CurrentValue=Config.ESP.ShowNames, Callback=function(v) Config.ESP.ShowNames=v end})
TabESP:CreateToggle({Name="Show Health", CurrentValue=Config.ESP.ShowHealth, Callback=function(v) Config.ESP.ShowHealth=v end})
TabESP:CreateToggle({Name="Show Distance", CurrentValue=Config.ESP.ShowDistance, Callback=function(v) Config.ESP.ShowDistance=v end})
TabESP:CreateSlider({Name="Box Thickness", Range={1,6}, Increment=1, CurrentValue=Config.ESP.Thickness, Callback=function(v) Config.ESP.Thickness=v end})
TabESP:CreateSlider({Name="Box Width", Range={20,200}, Increment=1, CurrentValue=Config.ESP.BoxSize.X, Callback=function(v) Config.ESP.BoxSize = Vector2.new(v, Config.ESP.BoxSize.Y) end})
TabESP:CreateSlider({Name="Box Height", Range={20,300}, Increment=1, CurrentValue=Config.ESP.BoxSize.Y, Callback=function(v) Config.ESP.BoxSize = Vector2.new(Config.ESP.BoxSize.X, v) end})
TabESP:CreateInput({Name="ESP Color (r,g,b)", CurrentValue=table.concat(Config.ESP.Color, ","), PlaceholderText="255,0,0", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local ok, t = pcall(function() return HttpService:JSONDecode("["..txt.."]") end)
    if ok and type(t)=="table" and #t==3 then Config.ESP.Color = t end
end})
TabESP:CreateButton({Name="Clear All ESP", Callback=function() clearAllESP() end})

-- Aimbot UI
TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=Config.Aimbot.Enabled, Callback=function(v) Config.Aimbot.Enabled=v end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={30,600}, Increment=5, CurrentValue=Config.Aimbot.FOV, Callback=function(v) Config.Aimbot.FOV=v end})
TabAimbot:CreateInput({Name="Aimbot Bone", CurrentValue=Config.Aimbot.Bone, PlaceholderText="HumanoidRootPart / Head / UpperTorso", RemoveTextAfterFocusLost=false, Callback=function(v) Config.Aimbot.Bone = v end})
TabAimbot:CreateSlider({Name="Smooth (lerp)", Range={0,1}, Increment=0.01, CurrentValue=Config.Aimbot.Smooth, Callback=function(v) Config.Aimbot.Smooth = v end})
TabAimbot:CreateToggle({Name="Hold To Aim", CurrentValue=Config.Aimbot.HoldToAim, Callback=function(v) Config.Aimbot.HoldToAim=v end})
TabAimbot:CreateInput({Name="Aim Key (EnumKeyCode)", CurrentValue=tostring(Config.Aimbot.AimKey), PlaceholderText="E", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local key = nil
    local ok,enum = pcall(function() return Enum.KeyCode[txt] end)
    if ok and enum then key = enum end
    if key then Config.Aimbot.AimKey = key end
end})

-- Aimbot logic & utility
local function getMousePos()
    local x,y = UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y
    return Vector2.new(x,y)
end

local function getClosestWithinFOV()
    local closest, shortest = nil, Config.Aimbot.FOV
    for _,player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(Config.Aimbot.Bone) then
            local bonePart = player.Character[Config.Aimbot.Bone]
            local screenPos, onScreen = Camera:WorldToViewportPoint(bonePart.Position)
            if onScreen then
                local mousePos = getMousePos()
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                if dist < shortest then
                    shortest, closest = dist, player
                end
            end
        end
    end
    return closest
end

-- optional: hold-to-aim flag
local AimHeld = false
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == (Config.Aimbot.AimKey or Enum.KeyCode.E) and Config.Aimbot.HoldToAim then AimHeld = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == (Config.Aimbot.AimKey or Enum.KeyCode.E) and Config.Aimbot.HoldToAim then AimHeld = false end
end)

-- Main render loop (ESP + Aimbot) - optimized ticking
table.insert(CreatedConnections, RunService.RenderStepped:Connect(function()
    -- ESP update (lightweight)
    if Config.ESP.Enabled then
        for _,player in pairs(Players:GetPlayers()) do
            if player == LocalPlayer then
                removeESPForPlayer(player)
            else
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local data = createESPForPlayer(player)
                    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                    if onScreen then
                        local box = data.Box
                        local text = data.Text
                        box.Thickness = Config.ESP.Thickness
                        box.Color = Color3.fromRGB(unpack(Config.ESP.Color))
                        box.Size = Config.ESP.BoxSize
                        box.Position = Vector2.new(screenPos.X - (box.Size.X/2), screenPos.Y - (box.Size.Y/2))
                        box.Visible = true
                        local info = ""
                        if Config.ESP.ShowNames then info = info .. player.Name .. " " end
                        if Config.ESP.ShowHealth and char:FindFirstChild("Humanoid") then info = info .. "["..math.floor(char.Humanoid.Health).."] " end
                        if Config.ESP.ShowDistance and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                            local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude)
                            info = info .. "("..dist.."m)"
                        end
                        text.Position = Vector2.new(screenPos.X, screenPos.Y - (box.Size.Y/2) - 12)
                        text.Text = info
                        text.Visible = true
                    else
                        if data.Box then data.Box.Visible = false end
                        if data.Text then data.Text.Visible = false end
                    end
                else
                    removeESPForPlayer(player)
                end
            end
        end
    else
        -- ESP disabled: hide everything but keep objects to avoid reallocation spam
        for p,data in pairs(PlayersESP) do
            if data.Box then data.Box.Visible = false end
            if data.Text then data.Text.Visible = false end
        end
    end

    -- Aimbot
    if Config.Aimbot.Enabled then
        if Config.Aimbot.HoldToAim and not AimHeld then
            -- require hold and not held -> skip
        else
            local target = getClosestWithinFOV()
            if target and target.Character and target.Character:FindFirstChild(Config.Aimbot.Bone) and Camera then
                local targetPos = target.Character[Config.Aimbot.Bone].Position
                local camPos = Camera.CFrame.Position
                local desired = CFrame.new(camPos, targetPos)
                Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(Config.Aimbot.Smooth, 0.01, 1))
            end
        end
    end
end))

-- FUN: Fling
TabFun:CreateButton({Name="Fling All Players", Callback=function()
    for _,v in ipairs(Players:GetPlayers()) do
        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = v.Character.HumanoidRootPart
            local bodyVel = Instance.new("BodyVelocity")
            bodyVel.Velocity = Vector3.new(0, 500, 0)
            bodyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            bodyVel.P = 1e6
            bodyVel.Parent = hrp
            Debris:AddItem(bodyVel, 0.45)
        end
    end
end})

-- Config Save / Load
TabConfig:CreateButton({Name="Save Config", Callback=function() Rayfield:SaveConfiguration() end})
TabConfig:CreateButton({Name="Load Config", Callback=function() Rayfield:LoadConfiguration() end})
TabConfig:CreateButton({Name="Clear All (Unload)", Callback=function()
    -- Attempt graceful teardown
    disconnectAll()
    clearAllESP()
    -- stop running loops
    LoopKillRunning = false
    for k,_ in pairs(runningLoopKillPlayer) do runningLoopKillPlayer[k] = nil end
    GodRunning = false
    AimHeld = false
    -- remove Rayfield (if API available)
    pcall(function() Rayfield:Unload() end)
end})

-- Finalize: Load saved config if exists (Rayfield handles file)
pcall(function() Rayfield:LoadConfiguration() end)

-- ensure nothing leaks when leaving
table.insert(CreatedConnections, Players.LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then -- localplayer removed -> attempt cleanup
        disconnectAll()
        clearAllESP()
    end
end))

-- end of script