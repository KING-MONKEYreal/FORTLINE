local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace:FindFirstChildOfClass("Camera") or Workspace.CurrentCamera


local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "FORTLINE Update",
    Icon = 0,
    LoadingTitle = "Loading Cheat",
    LoadingSubtitle = "by Chance",
    Theme = "Default",
    ConfigurationSaving = {Enabled=true, FolderName=nil, FileName="FORTLINE_PRO_2025"},
})

local TabMain = Window:CreateTab("Main", 4483362458)
local TabESP = Window:CreateTab("ESP", 4483362458)
local TabMisc = Window:CreateTab("Misc", 4483362458)
local TabAimbot = Window:CreateTab("Aimbot", 4483362458)


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


if not cachedWeaponNetwork then
    task.spawn(function()
        pcall(function()
            cachedWeaponNetwork = ReplicatedStorage:WaitForChild("WeaponsSystem", 2)
                and ReplicatedStorage.WeaponsSystem:WaitForChild("Network", 2)
                and ReplicatedStorage.WeaponsSystem.Network:FindFirstChild("WeaponHit")
        end)
    end)
end


local function FireWeapon(targetPart)
    if not (targetPart and typeof(targetPart.Position) == "Vector3") then return false end
    pcall(function()
        
        local weapon = (LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("RocketLauncher"))
                    or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RocketLauncher"))
        if weapon and cachedWeaponNetwork then
            cachedWeaponNetwork:FireServer(weapon, {
                p = targetPart.Position,
                pid = 0,
                part = targetPart,
                d = 0, maxDist = 0, h = targetPart, m = Enum.Material.Concrete,
                n = Vector3.new(0,0,0), t = 0, sid = 0
            })
        end
    end)
    return true
end


local LoopKillAllRunning = false
local LoopKillPlayers = {} 

local function KillAll()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local head = pl.Character:FindFirstChild("Head") or pl.Character:FindFirstChild("Head") -- try typical
            if head and head:IsA("BasePart") then
                FireWeapon(head)
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

local function ToggleLoopKillPlayer(playerName)
    if not playerName or playerName == "" then return end
    LoopKillPlayers[playerName] = not LoopKillPlayers[playerName]
    local function runner()
        while LoopKillPlayers[playerName] do
            local player = Players:FindFirstChild(playerName)
            if player and player.Character then
                local head = player.Character:FindFirstChild("Head") or player.Character:FindFirstChild("HumanoidRootPart")
                if head and head:IsA("BasePart") then
                    pcall(function() FireWeapon(head) end)
                end
            end
            task.wait(0.5)
        end
    end
    if LoopKillPlayers[playerName] then
        task.spawn(runner)
    end
end

TabMain:CreateButton({Name="Kill All", Callback=function() pcall(KillAll) end})
TabMain:CreateButton({Name="Toggle LoopKill All", Callback=ToggleLoopKillAll})
TabMain:CreateInput({
    Name="Kill Player",
    CurrentValue="",
    PlaceholderText="Name",
    RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local player = Players:FindFirstChild(txt)
        if player and player.Character then
            local head = player.Character:FindFirstChild("Head") or player.Character:FindFirstChild("HumanoidRootPart")
            if head then FireWeapon(head) end
        end
    end
})
TabMain:CreateInput({
    Name="Toggle LoopKill Player",
    CurrentValue="",
    PlaceholderText="Name",
    RemoveTextAfterFocusLost=false,
    Callback=ToggleLoopKillPlayer
})


local GodRunning = false
local function ToggleGod()
    GodRunning = not GodRunning
    if GodRunning then
        task.spawn(function()
            while GodRunning do
                pcall(function()
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        if Workspace:FindFirstChild("Safe") and Workspace.Safe:IsA("BasePart") then
                            Workspace.Safe.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                        else
                            
                        end
                    end
                end)
                task.wait(0.1)
            end
        end)
    end
end
TabMain:CreateButton({Name="Toggle God Mode", Callback=ToggleGod})

-- ======= Reset Player =======
TabMain:CreateButton({Name="Reset", Callback=function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
    end
end})

-- ======= Hitbox Expander (external) =======
TabMain:CreateButton({Name="Hitbox Expander (NOT MINE BTW)", Callback=function()
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))()
    end)
end})

-- ======= Misc Features (Speed / Jump / Teleport) =======
local defaultSpeed, defaultJump = 16, 50
local speedEnabled, jumpEnabled = false, false

local function UpdateHumanoid()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local hum = LocalPlayer.Character.Humanoid
        hum.WalkSpeed = speedEnabled and 50 or defaultSpeed
        hum.JumpPower = jumpEnabled and 100 or defaultJump
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    UpdateHumanoid()
end)

TabMisc:CreateToggle({Name="Speed Toggle", CurrentValue=false, Callback=function(val)
    speedEnabled = val
    UpdateHumanoid()
end})
TabMisc:CreateToggle({Name="Jump Power Toggle", CurrentValue=false, Callback=function(val)
    jumpEnabled = val
    UpdateHumanoid()
end})
TabMisc:CreateInput({
    Name="Teleport to Player",
    CurrentValue="",
    PlaceholderText="Player Name",
    RemoveTextAfterFocusLost=false,
    Callback=function(txt)
        local player = Players:FindFirstChild(txt)
        if player and player.Character and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("HumanoidRootPart") then
            pcall(function()
                LocalPlayer.Character.HumanoidRootPart.CFrame = player.Character.HumanoidRootPart.CFrame
            end)
        end
    end
})


local antiKickConn
antiKickConn = task.spawn(function()
    while task.wait(1) do
        pcall(function()
            if LocalPlayer and LocalPlayer.SetAttribute then
                LocalPlayer:SetAttribute("PreventKick", true)
            end
        end)
    end
end)


local PlayersESP = {}
local ESPSettings = {PlayerESP=true, ShowNames=true, ShowHealth=true, ShowDistance=true}

TabESP:CreateToggle({Name="Enable Player ESP", CurrentValue=true, Callback=function(val)
    ESPSettings.PlayerESP = val
end})
TabESP:CreateToggle({Name="Show Names", CurrentValue=true, Callback=function(val) ESPSettings.ShowNames = val end})
TabESP:CreateToggle({Name="Show Health", CurrentValue=true, Callback=function(val) ESPSettings.ShowHealth = val end})
TabESP:CreateToggle({Name="Show Distance", CurrentValue=true, Callback=function(val) ESPSettings.ShowDistance = val end})

Players.PlayerRemoving:Connect(function(plr)
    if PlayersESP[plr] then
        pcall(function()
            if PlayersESP[plr].Box then PlayersESP[plr].Box:Remove() end
            if PlayersESP[plr].Text then PlayersESP[plr].Text:Remove() end
        end)
        PlayersESP[plr] = nil
    end
end)


local function removeESPForPlayer(player)
    if PlayersESP[player] then
        pcall(function()
            if PlayersESP[player].Box then PlayersESP[player].Box:Remove() end
            if PlayersESP[player].Text then PlayersESP[player].Text:Remove() end
        end)
        PlayersESP[player] = nil
    end
end

RunService.RenderStepped:Connect(function()
    if not ESPSettings.PlayerESP then
        
        for p,_ in pairs(PlayersESP) do removeESPForPlayer(p) end
        return
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")) then
            if not PlayersESP[player] then
                local box = Drawing.new("Square")
                box.Thickness = 2
                box.Filled = false
                box.Color = Color3.fromRGB(255,0,0)
                local text = Drawing.new("Text")
                text.Color = Color3.fromRGB(255,255,255)
                text.Size = 16
                text.Center = true
                text.Outline = true
                PlayersESP[player] = {Box=box, Text=text}
            end

            local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")
            if not hrp then
                removeESPForPlayer(player)
                continue
            end

            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            local box, text = PlayersESP[player].Box, PlayersESP[player].Text

            if ESPSettings.PlayerESP and onScreen then
                
                local dist = 0
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude)
                end
                local sizeScale = math.clamp(200 / math.max(dist, 10), 0.6, 2.0)
                local boxW, boxH = 50 * sizeScale, 100 * sizeScale

                box.Position = Vector2.new(screenPos.X - boxW/2, screenPos.Y - boxH/1.7)
                box.Size = Vector2.new(boxW, boxH)
                box.Visible = true

                local info = ""
                if ESPSettings.ShowNames then info = info .. player.Name .. " " end
                if ESPSettings.ShowHealth and player.Character:FindFirstChild("Humanoid") then
                    info = info .. "[" .. math.floor(player.Character.Humanoid.Health) .. "] "
                end
                if ESPSettings.ShowDistance and dist > 0 then
                    info = info .. "(" .. dist .. "m)"
                end

                text.Position = Vector2.new(screenPos.X, screenPos.Y - boxH/2 - 12)
                text.Text = info
                text.Visible = true
            else
                box.Visible = false
                text.Visible = false
            end
        else
            
            if PlayersESP[player] then removeESPForPlayer(player) end
        end
    end
end)


local AimbotEnabled, AimbotFOV, AimbotBone = false, 100, "HumanoidRootPart"

TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=false, Callback=function(val)
    AimbotEnabled = val
end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={50,300}, Increment=5, CurrentValue=AimbotFOV, Callback=function(val)
    AimbotFOV = val
end})
TabAimbot:CreateInput({Name="Aimbot Bone", CurrentValue="HumanoidRootPart", PlaceholderText="Bone Name", RemoveTextAfterFocusLost=false, Callback=function(val)
    if val and val ~= "" then AimbotBone = val end
end})

local function GetClosestPlayerToCursor()
    local closestPlayer, shortestDistance = nil, AimbotFOV + 0
    local mousePos = UserInputService:GetMouseLocation()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(AimbotBone) then
            local bonePos = player.Character[AimbotBone].Position
            local screenPos, onScreen = Camera:WorldToViewportPoint(bonePos)
            if onScreen then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                if dist < shortestDistance then
                    shortestDistance = dist
                    closestPlayer = player
                end
            end
        end
    end
    return closestPlayer
end

RunService.RenderStepped:Connect(function()
    if AimbotEnabled then
        local target = GetClosestPlayerToCursor()
        if target and target.Character and target.Character:FindFirstChild(AimbotBone) then
            local targetPos = target.Character[AimbotBone].Position
            local smooth = 0.25
            if Camera and Camera.CFrame then
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, targetPos), smooth)
            end
        end
    end
end)


pcall(function() Rayfield:LoadConfiguration() end)


local function cleanupAll()
    
    LoopKillAllRunning = false
    for k,_ in pairs(LoopKillPlayers) do LoopKillPlayers[k] = false end
    GodRunning = false
   
    for p,data in pairs(PlayersESP) do
        pcall(function()
            if data.Box then data.Box:Remove() end
            if data.Text then data.Text:Remove() end
        end)
        PlayersESP[p] = nil
    end
   
    pcall(function()
        if LocalPlayer and LocalPlayer.SetAttribute then
            LocalPlayer:SetAttribute("PreventKick", nil)
        end
    end)
end


TabMain:CreateButton({Name="Unload / Cleanup", Callback=cleanupAll})
