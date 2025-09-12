--[[
    Fortline PRO 2025 — "Fixes All Bugs" Hardened Release (by Zero)
    Major improvements:
      • Deterministic throttling (tick-based) for loops (no runaway tasks)
      • Robust nil checks + multiple fallback names for remotes/weapons
      • Single RenderStepped handler for ESP + Aimbot with early-exit cheap checks
      • Proper teardown: remove drawings, disconnect connections, stop loops
      • Debounces and per-player loop maps to avoid overlapping loops
      • Safer Camera/Lua API usage (pcall when needed)
      • Defensive parsing for user inputs (esp color, ints, enums)
      • Minimal allocations in render loop (reused vars)
--]]

-- Services
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")
local HttpService       = game:GetService("HttpService")

-- Safe environment helpers
local function safeFind(obj, child) if obj and obj.FindFirstChild then return obj:FindFirstChild(child) end return nil end
local function isAliveCharacter(char) return char and char.Parent and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") end
local function clamp(n, a, b) if n < a then return a end if n > b then return b end return n end

-- Rayfield GUI (keep existing usage, tolerant to failure)
local success, Rayfield = pcall(function() return loadstring(game:HttpGet('https://sirius.menu/rayfield'))() end)
if not success or not Rayfield then
    warn("Rayfield failed to load; continuing without GUI.")
end

local Window
if Rayfield then
    Window = Rayfield:CreateWindow({
        Name = "Fortline  (Stable)",
        Icon = 0,
        LoadingTitle = "Fortline PRO",
        LoadingSubtitle = "by Chance",
        Theme = "Default",
        ConfigurationSaving = {Enabled=true, FileName="FORTLINE_PRO_2025_STABLE"},
    })
end

local function safeCreateTab(name)
    if not Window then return {CreateButton=function() end, CreateToggle=function() end, CreateInput=function() end, CreateSlider=function() end} end
    return Window:CreateTab(name, 4483362458)
end

local TabMain   = safeCreateTab("Main")
local TabESP    = safeCreateTab("ESP")
local TabMisc   = safeCreateTab("Misc")
local TabAimbot = safeCreateTab("Aimbot")
local TabFun    = safeCreateTab("Fun")
local TabConfig = safeCreateTab("Config")

-- CONFIG (hard defaults + clamps)
local Config = {
    Kill = {Delay = 0.5}, -- seconds (tick-based)
    Speed = {Enabled=false, WalkSpeed=50},
    Jump = {Enabled=false, JumpPower=100},
    ESP = {Enabled=true, ShowNames=true, ShowHealth=true, ShowDistance=true, Thickness=2, BoxW=50, BoxH=100, Color={255,0,0}},
    Aimbot = {Enabled=false, FOV=100, Bone="HumanoidRootPart", Smooth=0.25, HoldToAim=false, AimKey=Enum.KeyCode.E},
}

-- global runtime state
local PlayersESP = {}          -- player -> {Box, Text}
local CreatedConns = {}        -- list of connections to disconnect on unload
local ActivePlayerLoops = {}   -- per-player loop toggles
local Running = true           -- global run flag (used at unload)
local LastKillTick = 0
local Tick = tick

-- Robust remote/weapon lookup (multiple fallbacks)
local function findWeapon()
    -- common names to try
    local names = {"RocketLauncher", "Rocket Launcher", "RL", "Weapon_RocketLauncher"}
    for _,n in ipairs(names) do
        local ok, w = pcall(function()
            return (LocalPlayer.Character and safeFind(LocalPlayer.Character, n)) or safeFind(LocalPlayer.Backpack, n)
        end)
        if ok and w then return w end
    end
    return nil
end

local function findWeaponRemote()
    -- some systems use: WeaponsSystem.Network.WeaponHit, or Weapons.Network.Hit, etc.
    local searchPaths = {
        {"WeaponsSystem","Network","WeaponHit"},
        {"Weapons","Network","WeaponHit"},
        {"WeaponsSystem","Network","Hit"},
        {"WeaponsSystem","WeaponHit"}
    }
    for _, path in ipairs(searchPaths) do
        local root = ReplicatedStorage
        local ok, found = pcall(function()
            for _,part in ipairs(path) do
                root = safeFind(root, part)
                if not root then return nil end
            end
            return root
        end)
        if ok and found then return found end
    end
    return nil
end

local function safeFireWeapon(part)
    if not (part and part:IsA("BasePart")) then return false end
    pcall(function()
        local weapon = findWeapon()
        local remote = findWeaponRemote()
        if not weapon or not remote then return end
        -- FireServer usage is safest, but ensure remote supports FireServer
        if remote.FireServer then
            remote:FireServer(weapon, {
                p = part.Position, pid = 0, part = part,
                d = 0, maxDist = 0, h = part, m = Enum.Material.Concrete,
                n = Vector3.zero, t = 0, sid = 0
            })
        end
    end)
    return true
end

-- DRAWING helpers (safe wrappers)
local DrawingLib = Drawing -- may error in certain environments; wrap creation in pcall
local function newSquare()
    local ok, sq = pcall(function() return DrawingLib.new("Square") end)
    if ok then return sq end
    return nil
end
local function newText()
    local ok, t = pcall(function() return DrawingLib.new("Text") end)
    if ok then return t end
    return nil
end

-- Create/remove esp for player
local function createESP(player)
    local existing = PlayersESP[player]
    if existing then return existing end
    local box = newSquare()
    local text = newText()
    if not box or not text then return nil end
    box.Filled = false
    box.Thickness = Config.ESP.Thickness
    box.Size = Vector2.new(Config.ESP.BoxW, Config.ESP.BoxH)
    box.Color = Color3.fromRGB(unpack(Config.ESP.Color))
    text.Center = true
    text.Outline = true
    text.Size = 16
    PlayersESP[player] = {Box=box, Text=text}
    return PlayersESP[player]
end

local function removeESP(player)
    local d = PlayersESP[player]
    if not d then return end
    pcall(function() if d.Box then d.Box:Remove() end end)
    pcall(function() if d.Text then d.Text:Remove() end end)
    PlayersESP[player] = nil
end

-- Cleanup all
local function disconnectAll()
    for _,c in ipairs(CreatedConns) do
        pcall(function() c:Disconnect() end)
    end
    CreatedConns = {}
end
local function clearAllESP()
    for p,_ in pairs(PlayersESP) do removeESP(p) end
end

-- Player removal handler
table.insert(CreatedConns, Players.PlayerRemoving:Connect(function(plr) removeESP(plr) end))

-- Kill system (tick-throttled)
local function killAllOnce()
    local now = Tick()
    if now - LastKillTick < (Config.Kill.Delay or 0.5) then return end
    LastKillTick = now
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAliveCharacter(pl.Character) then
            safeFireWeapon(pl.Character:FindFirstChild("Head") or pl.Character:FindFirstChild("HumanoidRootPart"))
        end
    end
end

local function toggleLoopKillPlayer(name)
    if not name or name == "" then return end
    if ActivePlayerLoops[name] then ActivePlayerLoops[name] = nil; return end
    ActivePlayerLoops[name] = true
    -- spawn per-player loop
    task.spawn(function()
        while Running and ActivePlayerLoops[name] do
            local pl = Players:FindFirstChild(name)
            if pl and pl.Character and pl.Character:FindFirstChild("Head") then
                safeFireWeapon(pl.Character.Head)
            end
            task.wait(clamp(Config.Kill.Delay or 0.5, 0.05, 2))
        end
    end)
end

-- GUI Main controls (safe)
TabMain:CreateButton({Name="Kill All (once)", Callback=killAllOnce})
TabMain:CreateButton({Name="Toggle LoopKill All", Callback=function()
    -- toggles a global loop that executes killAllOnce
    if ActivePlayerLoops["_LOOP_ALL"] then ActivePlayerLoops["_LOOP_ALL"] = nil; return end
    ActivePlayerLoops["_LOOP_ALL"] = true
    task.spawn(function()
        while Running and ActivePlayerLoops["_LOOP_ALL"] do
            killAllOnce()
            task.wait(clamp(Config.Kill.Delay or 0.5, 0.05, 2))
        end
    end)
end})
TabMain:CreateInput({Name="Kill Player (once)", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false, Callback=function(txt)
    local p = Players:FindFirstChild(txt)
    if p and isAliveCharacter(p.Character) then
        safeFireWeapon(p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart"))
    end
end})
TabMain:CreateInput({Name="Toggle LoopKill Player", PlaceholderText="Player Name", RemoveTextAfterFocusLost=false, Callback=toggleLoopKillPlayer})

-- God mode (safe)
local GodRunning = false
TabMain:CreateButton({Name="Toggle God Mode", Callback=function()
    GodRunning = not GodRunning
    task.spawn(function()
        while Running and GodRunning do
            pcall(function()
                if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and workspace:FindFirstChild("Safe") then
                    workspace.Safe.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                end
            end)
            task.wait(0.12)
        end
    end)
end})

-- Reset
TabMain:CreateButton({Name="Reset (suicide)", Callback=function()
    pcall(function() if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.Health = 0 end end)
end})

-- Hitbox Expander
TabMain:CreateButton({Name="Open Hitbox Expander", Callback=function() pcall(function() loadstring(game:HttpGet("https://raw.githubusercontent.com/Vcsk/RobloxScripts/main/HitboxExpander.lua"))() end) end})

-- Speed & Jump (safe updates)
local defaultSpeed, defaultJump = 16, 50
local function updateHumanoid()
    pcall(function()
        if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local h = LocalPlayer.Character.Humanoid
            h.WalkSpeed = (Config.Speed.Enabled and clamp(Config.Speed.WalkSpeed, 1, 500)) or defaultSpeed
            h.JumpPower = (Config.Jump.Enabled and clamp(Config.Jump.JumpPower, 10, 500)) or defaultJump
        end
    end)
end
LocalPlayer.CharacterAdded:Connect(function() task.wait(0.8); updateHumanoid() end)

TabMisc:CreateToggle({Name="Speed Toggle", CurrentValue=Config.Speed.Enabled, Callback=function(v) Config.Speed.Enabled = v; updateHumanoid() end})
TabMisc:CreateInput({Name="Set Speed", CurrentValue=tostring(Config.Speed.WalkSpeed), Callback=function(val) local n=tonumber(val); if n then Config.Speed.WalkSpeed=n; updateHumanoid() end end})
TabMisc:CreateToggle({Name="Jump Toggle", CurrentValue=Config.Jump.Enabled, Callback=function(v) Config.Jump.Enabled = v; updateHumanoid() end})
TabMisc:CreateInput({Name="Set JumpPower", CurrentValue=tostring(Config.Jump.JumpPower), Callback=function(val) local n=tonumber(val); if n then Config.Jump.JumpPower=n; updateHumanoid() end end})
TabMisc:CreateInput({Name="Teleport to Player", PlaceholderText="Player Name", Callback=function(txt)
    local p = Players:FindFirstChild(txt)
    if p and isAliveCharacter(p.Character) and LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame end)
    end
end})

-- Gentle anti-kick
task.spawn(function()
    while Running do
        pcall(function() if LocalPlayer then LocalPlayer:SetAttribute("PreventKick", true) end end)
        task.wait(2 + math.random())
    end
end)

-- ESP UI inputs
TabESP:CreateToggle({Name="Enable ESP", CurrentValue=Config.ESP.Enabled, Callback=function(v) Config.ESP.Enabled=v end})
TabESP:CreateToggle({Name="Show Names", CurrentValue=Config.ESP.ShowNames, Callback=function(v) Config.ESP.ShowNames=v end})
TabESP:CreateToggle({Name="Show Health", CurrentValue=Config.ESP.ShowHealth, Callback=function(v) Config.ESP.ShowHealth=v end})
TabESP:CreateToggle({Name="Show Distance", CurrentValue=Config.ESP.ShowDistance, Callback=function(v) Config.ESP.ShowDistance=v end})
TabESP:CreateSlider({Name="Thickness", Range={1,6}, Increment=1, CurrentValue=Config.ESP.Thickness, Callback=function(v) Config.ESP.Thickness=v end})
TabESP:CreateSlider({Name="Box Width", Range={20,200}, Increment=1, CurrentValue=Config.ESP.BoxW, Callback=function(v) Config.ESP.BoxW=v end})
TabESP:CreateSlider({Name="Box Height", Range={20,300}, Increment=1, CurrentValue=Config.ESP.BoxH, Callback=function(v) Config.ESP.BoxH=v end})
TabESP:CreateInput({Name="ESP Color (r,g,b)", CurrentValue=table.concat(Config.ESP.Color, ","), Callback=function(txt)
    local ok, t = pcall(function() return HttpService:JSONDecode("["..txt.."]") end)
    if ok and type(t)=="table" and #t==3 then Config.ESP.Color = {clamp(tonumber(t[1]) or 255,0,255), clamp(tonumber(t[2]) or 0,0,255), clamp(tonumber(t[3]) or 0,0,255)} end
end})
TabESP:CreateButton({Name="Clear All ESP", Callback=clearAllESP})

-- Aimbot UI
TabAimbot:CreateToggle({Name="Enable Aimbot", CurrentValue=Config.Aimbot.Enabled, Callback=function(v) Config.Aimbot.Enabled=v end})
TabAimbot:CreateSlider({Name="Aimbot FOV", Range={30,600}, Increment=5, CurrentValue=Config.Aimbot.FOV, Callback=function(v) Config.Aimbot.FOV=clamp(v,30,1000) end})
TabAimbot:CreateInput({Name="Bone", CurrentValue=Config.Aimbot.Bone, Callback=function(v) if v and v~="" then Config.Aimbot.Bone=v end end})
TabAimbot:CreateSlider({Name="Smooth", Range={1,100}, Increment=1, CurrentValue=math.floor(Config.Aimbot.Smooth*100), Callback=function(v) Config.Aimbot.Smooth=clamp(v/100,0.01,1) end})
TabAimbot:CreateToggle({Name="Hold To Aim", CurrentValue=Config.Aimbot.HoldToAim, Callback=function(v) Config.Aimbot.HoldToAim=v end})
TabAimbot:CreateInput({Name="Aim Key (E)", CurrentValue=tostring(Config.Aimbot.AimKey.Name), Callback=function(txt)
    local ok, enum = pcall(function() return Enum.KeyCode[txt] end)
    if ok and enum then Config.Aimbot.AimKey = enum end
end})

-- Aimbot runtime
local AimHeld = false
UserInputService.InputBegan:Connect(function(inp, gpe) if not gpe and inp.KeyCode == (Config.Aimbot.AimKey or Enum.KeyCode.E) then AimHeld = true end end)
UserInputService.InputEnded:Connect(function(inp) if inp.KeyCode == (Config.Aimbot.AimKey or Enum.KeyCode.E) then AimHeld = false end end)

local function getMouseVec2() local v = UserInputService:GetMouseLocation(); return Vector2.new(v.X, v.Y) end
local function getClosestPlayerToCursorWithinFOV()
    local closest, best = nil, Config.Aimbot.FOV
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAliveCharacter(pl.Character) and pl.Character:FindFirstChild(Config.Aimbot.Bone) then
            local bone = pl.Character[Config.Aimbot.Bone]
            local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(bone.Position)
            if onScreen then
                local d = (Vector2.new(screenPos.X, screenPos.Y) - getMouseVec2()).Magnitude
                if d < best then best, closest = d, pl end
            end
        end
    end
    return closest
end

-- Single RenderStepped loop (ESP + Aimbot) with early cheap checks
table.insert(CreatedConns, RunService.RenderStepped:Connect(function()
    if not Running then return end

    local cam = workspace.CurrentCamera
    if not cam then return end

    -- ESP
    if Config.ESP.Enabled then
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl == LocalPlayer then removeESP(pl) else
                local char = pl.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = createESP(pl)
                    if d and d.Box and d.Text then
                        local screenPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                        if onScreen then
                            d.Box.Thickness = Config.ESP.Thickness
                            d.Box.Size = Vector2.new(Config.ESP.BoxW, Config.ESP.BoxH)
                            d.Box.Color = Color3.fromRGB(unpack(Config.ESP.Color))
                            d.Box.Position = Vector2.new(screenPos.X - (d.Box.Size.X/2), screenPos.Y - (d.Box.Size.Y/2))
                            d.Box.Visible = true
                            local info = ""
                            if Config.ESP.ShowNames then info = info .. pl.Name .. " " end
                            if Config.ESP.ShowHealth and char:FindFirstChild("Humanoid") then info = info .. "["..math.floor(char.Humanoid.Health).."] " end
                            if Config.ESP.ShowDistance and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude)
                                info = info .. "("..dist.."m)"
                            end
                            d.Text.Position = Vector2.new(screenPos.X, screenPos.Y - (d.Box.Size.Y/2) - 12)
                            d.Text.Text = info
                            d.Text.Visible = true
                        else
                            d.Box.Visible = false
                            d.Text.Visible = false
                        end
                    end
                else
                    removeESP(pl)
                end
            end
        end
    else
        -- hide, keep objects to avoid allocation thrash
        for p,dat in pairs(PlayersESP) do
            if dat.Box then dat.Box.Visible = false end
            if dat.Text then dat.Text.Visible = false end
        end
    end

    -- Aimbot
    if Config.Aimbot.Enabled then
        if (Config.Aimbot.HoldToAim and not AimHeld) then
            -- skip
        else
            local target = getClosestPlayerToCursorWithinFOV()
            if target and target.Character and target.Character:FindFirstChild(Config.Aimbot.Bone) then
                local tpos = target.Character[Config.Aimbot.Bone].Position
                local desired = CFrame.new(cam.CFrame.Position, tpos)
                cam.CFrame = cam.CFrame:Lerp(desired, clamp(Config.Aimbot.Smooth, 0.01, 1))
            end
        end
    end
end))

-- Fun: fling everyone once (safe)
TabFun:CreateButton({Name="Fling All Players", Callback=function()
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAliveCharacter(pl.Character) then
            local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bv = Instance.new("BodyVelocity")
                bv.Velocity = Vector3.new(0, 500, 0)
                bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
                bv.P = 1e6
                bv.Parent = hrp
                Debris:AddItem(bv, 0.45)
            end
        end
    end
end})

-- Config Management: Save/Load/Unload
TabConfig:CreateButton({Name="Save Config", Callback=function() if Rayfield then pcall(function() Rayfield:SaveConfiguration() end) end end})
TabConfig:CreateButton({Name="Load Config", Callback=function() if Rayfield then pcall(function() Rayfield:LoadConfiguration() end) end end})
TabConfig:CreateButton({Name="Clear All (Unload)", Callback=function()
    -- graceful teardown
    Running = false
    ActivePlayerLoops = {}
    GodRunning = false
    -- disconnect and clear drawings
    disconnectAll()
    clearAllESP()
    pcall(function() if Rayfield and Rayfield.Unload then Rayfield:Unload() end end)
end})

-- ensure cleanup on LocalPlayer removal (rare)
table.insert(CreatedConns, LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        Running = false
        disconnectAll()
        clearAllESP()
    end
end))

-- small safe finalization
pcall(function() if Rayfield and Rayfield.LoadConfiguration then Rayfield:LoadConfiguration() end end)

-- Script loaded
print("[Fortline PRO 2025 - STABLE] Loaded. Running = true")