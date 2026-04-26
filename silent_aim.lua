-- ============================================================
--  IRON SHADOW — Silent Aim v1.3.4 (FINAL STABLE)
--  Optimized for Stability | Universal Raycast Support | Mobile
-- ============================================================

local VERSION = "1.3.4"
local UI_NAME = "SA_" .. tostring(math.random(100000, 999999))

-- [[ SERVICES ]] --
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Stats             = game:GetService("Stats")
local Camera            = workspace.CurrentCamera
local LocalPlayer       = Players.LocalPlayer

-- [[ CONFIG ]] --
local CONFIG = {
    ENABLED         = true,
    FOV             = 150,
    TEAM_CHECK      = false,
    TARGET_PART     = "HumanoidRootPart",
    SHOW_FOV        = true,
    FOV_COLOR       = Color3.fromRGB(220, 50, 50),

    -- Prediction
    PREDICTION_ENABLED = true,
    PREDICTION_AUTO    = true,
    PREDICTION_AMOUNT  = 0.165,

    -- ESP Settings
    ESP_ENABLED     = true,
    ESP_BOX         = true,
    ESP_NAMES       = true,
    ESP_HEALTH      = true,
    ESP_MAX_DIST    = 1000,

    -- Advanced (Safety)
    SAFE_UNIT       = true,
    FILTER_CAMERA   = true,

    -- Colors & UI
    ACCENT          = Color3.fromRGB(220, 50, 50),
    BG              = Color3.fromRGB(14, 14, 18),
    BG2             = Color3.fromRGB(20, 20, 26),
    PANIC           = false,
}

-- [[ STATE ]] --
local espObjects    = {}
local currentTarget = nil
local cachedTargetPos = nil
local cachedMouseRef  = nil

-- [[ UTILS ]] --
local function getPing()
    local ok, v = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return (ok and type(v) == "number") and v or 0
end

local function isAlive(player)
    if not player or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getScreenCenter()
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end

local function getScreenPos(worldPos)
    local sp, onScreen, depth = Camera:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), onScreen, sp.Z
end

local function getSafeUnit(vector)
    if vector.Magnitude == 0 then return Vector3.new(0, 1, 0) end
    return vector.Unit
end

-- [[ PREDICTION LOGIC ]] --
local function getPredictedPosition(target)
    if not target.Character then return nil end
    local part = target.Character:FindFirstChild(CONFIG.TARGET_PART) or target.Character:FindFirstChild("HumanoidRootPart")
    if not part then return nil end

    if not CONFIG.PREDICTION_ENABLED then
        return part.Position
    end

    local velocity = part.Velocity
    local ping = getPing() / 1000
    local dist = (Camera.CFrame.Position - part.Position).Magnitude

    local finalPredict = CONFIG.PREDICTION_AMOUNT
    if CONFIG.PREDICTION_AUTO then
        finalPredict = (dist / 1000) + (ping * 0.8)
    else
        finalPredict = CONFIG.PREDICTION_AMOUNT + (ping * 0.5)
    end

    if velocity.Magnitude < 0.1 then
        return part.Position
    end

    return part.Position + (velocity * finalPredict)
end

-- [[ TARGET SELECTION ]] --
local function getNearestTarget()
    local center     = getScreenCenter()
    local bestDist   = CONFIG.FOV
    local bestPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (not CONFIG.TEAM_CHECK or player.Team ~= LocalPlayer.Team) then
            if isAlive(player) then
                local char = player.Character
                local part = char:FindFirstChild(CONFIG.TARGET_PART) or char:FindFirstChild("HumanoidRootPart")
                if part then
                    local screenPos, onScreen, depth = getScreenPos(part.Position)
                    if onScreen and depth > 0 then
                        local dist = (screenPos - center).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestPlayer = player
                        end
                    end
                end
            end
        end
    end
    return bestPlayer
end

-- [[ HOOKING ENGINE ]] --
pcall(function() cachedMouseRef = LocalPlayer:GetMouse() end)

local function isCameraCall()
    if not CONFIG.FILTER_CAMERA then return false end
    local stack = debug.traceback():lower()
    -- Relaxed check to ensure weapon scripts aren't accidentally filtered
    return (stack:find("camera") and (stack:find("module") or stack:find("control")))
end

local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() and CONFIG.ENABLED and not CONFIG.PANIC and cachedTargetPos then
        if self == cachedMouseRef and not isCameraCall() then
            if key == "Hit" then
                return CFrame.new(cachedTargetPos)
            elseif key == "Target" then
                local part = currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild(CONFIG.TARGET_PART)
                return part
            end
        end
    end
    return oldIndex(self, key)
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if not checkcaller() and CONFIG.ENABLED and not CONFIG.PANIC and cachedTargetPos then
        if (method == "Raycast" or method == "Spherecast" or method == "Blockcast" or method == "Shapecast") and self == workspace then
            if not isCameraCall() then
                local origin = args[1]
                local direction = args[2]
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local diff = (cachedTargetPos - origin)
                    local targetDir = getSafeUnit(diff)
                    -- Always redirect if Silent Aim is active and targeting
                    args[2] = targetDir * direction.Magnitude
                end
            end
        elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
            if not isCameraCall() then
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local origin = ray.Origin
                    local direction = ray.Direction
                    local diff = (cachedTargetPos - origin)
                    local targetDir = getSafeUnit(diff)
                    args[1] = Ray.new(origin, targetDir * direction.Magnitude)
                end
            end
        elseif (method == "ScreenPointToRay" or method == "ViewportPointToRay") and self == Camera then
            local result = oldNamecall(self, ...)
            if typeof(result) == "Ray" then
                local origin = result.Origin
                local diff = (cachedTargetPos - origin)
                local targetDir = getSafeUnit(diff)
                return Ray.new(origin, targetDir * result.Direction.Magnitude)
            end
        elseif method == "FireServer" and self:IsA("RemoteEvent") then
            for i = 1, #args do
                local arg = args[i]
                if typeof(arg) == "Vector3" then
                    local screenPos, onScreen = getScreenPos(arg)
                    if onScreen and (screenPos - getScreenCenter()).Magnitude < CONFIG.FOV * 2 then
                        args[i] = cachedTargetPos
                    end
                elseif typeof(arg) == "CFrame" then
                    local screenPos, onScreen = getScreenPos(arg.Position)
                    if onScreen and (screenPos - getScreenCenter()).Magnitude < CONFIG.FOV * 2 then
                        args[i] = CFrame.new(cachedTargetPos)
                    end
                end
            end
        end
    end

    return oldNamecall(self, unpack(args))
end)

-- [[ ESP & DRAWING ]] --
local function newDrawing(type, props)
    local d = Drawing.new(type)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function createESP(player)
    if espObjects[player] then return end
    espObjects[player] = {
        -- Explicitly set Filled = false to prevent blocking vision
        boxOutline  = newDrawing("Square",  {Thickness=3, Color=Color3.new(0,0,0), Filled=false, Visible=false}),
        box         = newDrawing("Square",  {Thickness=1, Color=CONFIG.ACCENT, Filled=false, Visible=false}),
        name        = newDrawing("Text",    {Size=13, Color=Color3.new(1,1,1), Outline=true, Center=true, Visible=false}),
        healthBar   = newDrawing("Square",  {Thickness=1, Filled=true, Visible=false}),
    }
end

local function removeESP(player)
    if not espObjects[player] then return end
    for _, d in pairs(espObjects[player]) do pcall(function() d:Remove() end) end
    espObjects[player] = nil
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not CONFIG.ESP_ENABLED or CONFIG.PANIC or (CONFIG.TEAM_CHECK and player.Team == LocalPlayer.Team) then
                removeESP(player)
            else
                if not espObjects[player] then createESP(player) end
                local objs = espObjects[player]
                local char = player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum  = char and char:FindFirstChildOfClass("Humanoid")

                if root and hum and hum.Health > 0 then
                    local screenPos, onScreen, depth = getScreenPos(root.Position)
                    if onScreen and depth > 0 then
                        local size = Vector2.new(2000 / depth, 3000 / depth)
                        local pos  = Vector2.new(screenPos.X - size.X / 2, screenPos.Y - size.Y / 2)

                        objs.boxOutline.Position = pos; objs.boxOutline.Size = size; objs.boxOutline.Visible = CONFIG.ESP_BOX
                        objs.box.Position = pos; objs.box.Size = size; objs.box.Visible = CONFIG.ESP_BOX
                        objs.box.Color = (currentTarget == player) and Color3.new(1,1,0) or CONFIG.ACCENT

                        objs.name.Text = player.Name; objs.name.Position = Vector2.new(screenPos.X, pos.Y - 15); objs.name.Visible = CONFIG.ESP_NAMES

                        if CONFIG.ESP_HEALTH then
                            local hp = hum.Health / hum.MaxHealth
                            objs.healthBar.Position = Vector2.new(pos.X - 5, pos.Y + (size.Y * (1-hp)))
                            objs.healthBar.Size = Vector2.new(2, size.Y * hp)
                            objs.healthBar.Color = Color3.fromHSV(hp * 0.3, 1, 1)
                            objs.healthBar.Visible = true
                        else objs.healthBar.Visible = false end
                    else for _, d in pairs(objs) do d.Visible = false end end
                else for _, d in pairs(objs) do d.Visible = false end end
            end
        end
    end
end

-- [[ FOV ]] --
local fovDraw = newDrawing("Circle", {Thickness=1, Color=CONFIG.FOV_COLOR, NumSides=64, Visible=false})

-- [[ UI ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = UI_NAME; ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

local MobileBtn = Instance.new("TextButton")
MobileBtn.Size = UDim2.new(0,50,0,50); MobileBtn.Position = UDim2.new(0,20,0.5,-25)
MobileBtn.BackgroundColor3 = CONFIG.BG; MobileBtn.TextColor3 = CONFIG.ACCENT
MobileBtn.Text = "MENU"; MobileBtn.Font = "GothamBold"; MobileBtn.TextSize = 12; MobileBtn.Parent = ScreenGui
Instance.new("UICorner", MobileBtn).CornerRadius = UDim.new(1,0)

local Win = Instance.new("Frame")
Win.Size = UDim2.new(0,250,0,300); Win.Position = UDim2.new(0.5,-125,0.5,-150)
Win.BackgroundColor3 = CONFIG.BG; Win.Visible = false; Win.Parent = ScreenGui
Instance.new("UICorner", Win)

local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1,0,1,0); Content.BackgroundTransparency = 1; Content.CanvasSize = UDim2.new(0,0,0,500); Content.Parent = Win
local layout = Instance.new("UIListLayout", Content); layout.HorizontalAlignment = "Center"; layout.Padding = UDim.new(0,5)

local function addToggle(txt, def, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.9,0,0,30); b.BackgroundColor3 = CONFIG.BG2; b.Text = txt..": "..(def and "ON" or "OFF")
    b.TextColor3 = def and CONFIG.ACCENT or Color3.new(1,1,1); b.Font = "Gotham"; b.TextSize = 12; b.Parent = Content
    Instance.new("UICorner", b)
    b.MouseButton1Click:Connect(function()
        def = not def
        b.Text = txt..": "..(def and "ON" or "OFF")
        b.TextColor3 = def and CONFIG.ACCENT or Color3.new(1,1,1)
        cb(def)
    end)
end

addToggle("Silent Aim", CONFIG.ENABLED, function(v) CONFIG.ENABLED = v end)
addToggle("Team Check", CONFIG.TEAM_CHECK, function(v) CONFIG.TEAM_CHECK = v end)
addToggle("Prediction", CONFIG.PREDICTION_ENABLED, function(v) CONFIG.PREDICTION_ENABLED = v end)
addToggle("ESP", CONFIG.ESP_ENABLED, function(v) CONFIG.ESP_ENABLED = v end)

MobileBtn.MouseButton1Click:Connect(function() Win.Visible = not Win.Visible end)

-- [[ LOOP ]] --
RunService.RenderStepped:Connect(function()
    currentTarget = CONFIG.ENABLED and getNearestTarget() or nil
    cachedTargetPos = currentTarget and getPredictedPosition(currentTarget) or nil

    if CONFIG.SHOW_FOV and CONFIG.ENABLED then
        fovDraw.Position = getScreenCenter(); fovDraw.Radius = CONFIG.FOV; fovDraw.Visible = true
    else fovDraw.Visible = false end

    updateESP()
end)

print("[Iron Shadow] v"..VERSION.." Stable.")
