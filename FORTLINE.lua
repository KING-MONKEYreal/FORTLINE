--// Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera
local Debris = game:GetService("Debris")

--// GUI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Fortline Fixed",
    Icon = 0,
    LoadingTitle = "Loading cheat",
    LoadingSubtitle = "by Chance",
    Theme = "Default",
    ConfigurationSaving = {Enabled=true, FileName="FORTLINE_PRO_2025_PLUS"},
})

local TabMain   = Window:CreateTab("Main", 4483362458)
local TabESP    = Window:CreateTab("ESP", 4483362458)
local TabMisc   = Window:CreateTab("Misc", 4483362458)
local TabAimbot = Window:CreateTab("Aimbot", 4483362458)
local TabFun    = Window:CreateTab("Fun", 4483362458)

-- ======================================================
-- Weapon Helper
-- ======================================================
local function FireWeapon(target)
    if not (target and target.Parent) then return end
    pcall(function()
        local weapon = LocalPlayer.Backpack:FindFirstChild("RocketLauncher") or LocalPlayer.Character:FindFirstChild("RocketLauncher")
        if weapon then
            local network = ReplicatedStorage:FindFirstChild("WeaponsSystem") and ReplicatedStorage.WeaponsSystem:FindFirstChild("Network") and ReplicatedStorage.WeaponsSystem.Network:FindFirstChild("WeaponHit")
            if network then
                network:FireServer(weapon, {
                    p = target.Position, pid = 0, part = target,
                    d = 0, maxDist = 0, h = target, m = Enum.Material.Concrete,
                    n = Vector3.zero, t = 0, sid = 0
                })
            end
        end
    end)
end

-- ======================================================
-- Kill System
-- ======================================================
local LoopKillRunning, LoopKillPlayerRunning = false, false

local function KillAll()
    for _,v in ipairs(Players:GetPlayers()) do
        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("Head") then
            FireWeapon(v.Character.Head)
        end
    end
end

local function ToggleLoopKillAll()
    LoopKillRunning = not LoopKillRunning
    task.spawn(function()
        while LoopKillRunning do
            KillAll()
            task.wait(0.5)
        end
    end)
end

local function ToggleLoopKillPlayer(playerName)
    LoopKillPlayerRunning = not LoopKillPlayerRunning
    task.spawn(function()
        while LoopKillPlayerRunning do
            local player = Players:FindFirstChild(playerName)
            if player and player.Character and player.Character:FindFirstChild("Head") then
                FireWeapon(player.Character.Head)
            end
            task.wait(0.5)
        end
    end)
end

TabMain:CreateButton({Name="Kill All", Callback=KillAll})
TabMain:CreateButton({Name="Toggle LoopKill All", Callback=ToggleLoopKillAll})
TabMain:CreateInput({
    Name="Kill Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local player = Players:FindFirstChild(txt)
        if player and player.Character and player.Character:FindFirstChild("Head") then
            FireWeapon(player.Character.Head)
        end
    end
})
TabMain:CreateInput({
    Name="Toggle LoopKill Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=ToggleLoopKillPlayer
})

-- ======================================================
-- God Mode
-- ======================================================
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
            task.wait(0.1)
        end
    end)
end
TabMain:CreateButton({Name="Toggle God Mode", Callback=ToggleGod})

-- Reset
TabMain:CreateButton({Name="Reset", Callback=function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.Health = 0
    end
end})

-- Hitbox Expander
TabMain:CreateButton({Name="Hitbox Expander GUI", Callback=function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))()
end})

-- ======================================================
-- Misc
-- ======================================================
local defaultSpeed, defaultJump = 16, 50
local speedEnabled, jumpEnabled = false, false

local function UpdateHumanoid()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = speedEnabled and 50 or defaultSpeed
        LocalPlayer.Character.Humanoid.JumpPower = jumpEnabled and 100 or defaultJump
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    UpdateHumanoid()
end)

TabMisc:CreateToggle({Name="Speed Toggle", CurrentValue=false, Callback=function(val) speedEnabled=val; UpdateHumanoid() end})
TabMisc:CreateToggle({Name="Jump Power Toggle", CurrentValue=false, Callback=function(val) jumpEnabled=val; UpdateHumanoid() end})
TabMisc:CreateInput({
    Name="Teleport to Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local player = Players:FindFirstChild(txt)
        if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = player.Character.HumanoidRootPart.CFrame
        end
    end
})

-- Anti-Kick
task.spawn(function()
    while task.wait(1) do
        pcall(function() LocalPlayer:SetAttribute("PreventKick", true) end)
    end
end)

-- ======================================================
-- ESP
-- ======================================================
local PlayersESP = {}
local ESPSettings = {Enabled=true, ShowNames=true, ShowHealth=true, ShowDistance=true}

TabESP:CreateToggle({Name="Enable Player ESP", CurrentValue=true, Callback=function(val) ESPSettings.Enabled = val end})

Players.PlayerRemoving:Connect(function(plr)
    if PlayersESP[plr] then
        if PlayersESP[plr].Box then PlayersESP[plr].Box:Remove() end
        if PlayersESP[plr].Text then PlayersESP[plr].Text:Remove() end
        PlayersESP[plr] = nil
    end
end)

RunService.RenderStepped:Connect(function()
    for _,player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            if not PlayersESP[player] then
                local box = Drawing.new("Square")
                box.Thickness, box.Filled, box.Color = 2, false, Color3.fromRGB(255,0,0)
                local text = Drawing.new("Text")
                text.Color, text.Size, text.Center, text.Outline = Color3.new(1,1,1), 16, true, true
                PlayersESP[player] = {Box=box, Text=text}
            end
            local hrp = player.Character.HumanoidRootPart
            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            local box, text = PlayersESP[player].Box, PlayersESP[player].Text
            if ESPSettings.Enabled and onScreen then
                box.Position = Vector2.new(screenPos.X-25, screenPos.Y-50)
                box.Size = Vector2.new(50,100)
                box.Visible = true
                local info = ""
                if ESPSettings.ShowNames then info ..= player.Name.." " end
                if ESPSettings.ShowHealth and player.Character:FindFirstChild("Humanoid") then
                    info ..= "["..math.floor(player.Character.Humanoid.Health).."] "
                end
                if ESPSettings.ShowDistance and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position-hrp.Position).Magnitude)
                    info ..= "("..dist.."m)"
                end
                text.Position, text.Text, text.Visible = Vector2.new(screenPos.X, screenPos.Y-60), info, true
            else
                box.Visible, text.Visible = false, false
            end
        end
    end
end)

-- ======================================================
-- Aimbot
-- ======================================================
local AimbotEnabled, AimbotFOV, AimbotBone = false, 100, "HumanoidRootPart"

TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=false, Callback=function(val) AimbotEnabled=val end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={50,300}, Increment=5, CurrentValue=AimbotFOV, Callback=function(val) AimbotFOV=val end})
TabAimbot:CreateInput({Name="Aimbot Bone", CurrentValue="HumanoidRootPart", PlaceholderText="Bone Name", RemoveTextAfterFocusLost=false, Callback=function(val) AimbotBone=val end})

local function GetClosestPlayer()
    local closest, shortest = nil, AimbotFOV
    for _,player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(AimbotBone) then
            local screenPos, onScreen = Camera:WorldToViewportPoint(player.Character[AimbotBone].Position)
            if onScreen then
                local mousePos = UserInputService:GetMouseLocation()
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                if dist < shortest then
                    shortest, closest = dist, player
                end
            end
        end
    end
    return closest
end

RunService.RenderStepped:Connect(function()
    if AimbotEnabled then
        local target = GetClosestPlayer()
        if target and target.Character and target.Character:FindFirstChild(AimbotBone) then
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, target.Character[AimbotBone].Position), 0.25)
        end
    end
end)

-- ======================================================
-- Fun Utilities
-- ======================================================
TabFun:CreateButton({Name="Fling All Players", Callback=function()
    for _,v in ipairs(Players:GetPlayers()) do
        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
            local bodyVel = Instance.new("BodyVelocity")
            bodyVel.Velocity, bodyVel.MaxForce, bodyVel.P = Vector3.new(0,500,0), Vector3.new(1e6,1e6,1e6), 1e6
            bodyVel.Parent = v.Character.HumanoidRootPart
            Debris:AddItem(bodyVel,0.5)
        end
    end
end})

Rayfield:LoadConfiguration()