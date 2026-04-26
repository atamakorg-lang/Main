-- ====================================================================================================
--  IRON SHADOW — Silent Aim ELITE v1.4.1 (ULTIMATE EDITION)
--  Developed for Maximum Precision, Stability, and Customization.
--  Universal Raycast Redirection | Advanced Prediction | Multi-Hook Detouring | Backtrack
-- ====================================================================================================

local VERSION = "1.4.1"
local UI_NAME = "IRON_SHADOW_ELITE_" .. tostring(math.random(1000000, 9999999))

-- [[ SERVICES ]] --
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Stats             = game:GetService("Stats")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local Camera            = workspace.CurrentCamera
local LocalPlayer       = Players.LocalPlayer

-- [[ CONFIGURATION ]] --
local CONFIG = {
    ENABLED             = true,
    FOV                 = 150,
    TEAM_CHECK          = false,
    VISIBILITY_CHECK    = true,

    -- Targeting
    TARGET_PART         = "HumanoidRootPart", -- "Head", "HumanoidRootPart", "Random"
    HITBOX_CHANCE       = 100,

    -- Prediction
    PREDICTION_ENABLED  = true,
    PREDICTION_AUTO     = true,
    PREDICTION_AMOUNT   = 0.165,
    PREDICTION_X_ADJ    = 0,
    PREDICTION_Y_ADJ    = 0,
    PREDICTION_Z_ADJ    = 0,

    -- Backtrack (Experimental)
    BACKTRACK_ENABLED   = false,
    BACKTRACK_TIME      = 0.2, -- Seconds

    -- Visuals: FOV
    SHOW_FOV            = true,
    FOV_COLOR           = Color3.fromRGB(255, 0, 0),
    FOV_SIDES           = 64,
    FOV_THICKNESS       = 1.5,
    FOV_TRANSPARENCY    = 0.5,

    -- Visuals: ESP
    ESP_ENABLED         = true,
    ESP_BOX             = true,
    ESP_BOX_FILLED      = false,
    ESP_BOX_COLOR       = Color3.fromRGB(255, 0, 0),
    ESP_NAMES           = true,
    ESP_HEALTH          = true,
    ESP_DISTANCE        = true,
    ESP_MAX_DIST        = 2500,

    -- Visuals: Target
    SHOW_TARGET_DOT     = true,
    TARGET_DOT_COLOR    = Color3.fromRGB(0, 255, 255),
    SHOW_TARGET_LINE    = false,
    TARGET_LINE_COLOR   = Color3.fromRGB(0, 255, 255),

    -- Advanced Engine
    SAFE_UNIT           = true,
    FILTER_CAMERA       = true,
    DETOUR_RAYCAST      = true,
    DETOUR_NAMECALL     = true,
    DETOUR_INDEX        = true,
    REDISTRIBUTE_CHANCE = 100,

    -- UI Style
    ACCENT              = Color3.fromRGB(255, 0, 0),
    BG                  = Color3.fromRGB(10, 10, 12),
    BG2                 = Color3.fromRGB(15, 15, 18),
    PANIC               = false,
}

-- [[ STATE MANAGEMENT ]] --
local espObjects      = {}
local backtrackData   = {}
local currentTarget   = nil
local cachedTargetPos = nil
local cachedMouseRef  = nil
local screenCenter    = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

-- [[ DRAWING API WRAPPER ]] --
local function createDrawing(type, properties)
    local d = Drawing.new(type)

    -- Force clear defaults to ensure NO FILLING
    if type == "Square" or type == "Circle" then
        d.Filled = false
    end
    d.Visible = false
    d.Transparency = 1

    for k, v in pairs(properties) do
        pcall(function() d[k] = v end)
    end

    -- RE-ENFORCE FILLED STATUS
    if type == "Square" or type == "Circle" then
        if properties.Filled ~= nil then
            d.Filled = properties.Filled
        else
            d.Filled = false
        end
    end

    return d
end

-- [[ UTILITIES ]] --
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

local function getScreenPos(worldPos)
    local sp, onScreen, depth = Camera:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), onScreen, depth
end

local function getSafeUnit(vector)
    if vector.Magnitude == 0 then return Vector3.new(0, 1, 0) end
    return vector.Unit
end

local function checkVisibility(part, player)
    if not CONFIG.VISIBILITY_CHECK then return true end
    local origin = Camera.CFrame.Position
    local dest = part.Position
    local dir = dest - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}

    local result = workspace:Raycast(origin, dir, params)
    if result then
        return result.Instance:IsDescendantOf(player.Character)
    end
    return true
end

-- [[ BACKTRACK ENGINE ]] --
task.spawn(function()
    while true do
        task.wait(0.01)
        if CONFIG.PANIC then break end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and isAlive(player) then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    if not backtrackData[player] then backtrackData[player] = {} end
                    table.insert(backtrackData[player], {pos = root.Position, time = tick()})

                    while #backtrackData[player] > 0 and (tick() - backtrackData[player][1].time) > CONFIG.BACKTRACK_TIME do
                        table.remove(backtrackData[player], 1)
                    end
                end
            elseif backtrackData[player] then
                backtrackData[player] = nil
            end
        end
    end
end)

-- [[ PREDICTION LOGIC ]] --
local function getPredictedPosition(target)
    if not target.Character then return nil end

    local partName = CONFIG.TARGET_PART
    if partName == "Random" then
        local parts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"}
        partName = parts[math.random(1, #parts)]
    end

    local part = target.Character:FindFirstChild(partName) or target.Character:FindFirstChild("HumanoidRootPart")
    if not part then return nil end

    local basePos = part.Position

    if not CONFIG.PREDICTION_ENABLED then
        return basePos
    end

    local velocity = part.Velocity
    local ping = getPing() / 1000
    local dist = (Camera.CFrame.Position - basePos).Magnitude

    local finalPredict = CONFIG.PREDICTION_AMOUNT
    if CONFIG.PREDICTION_AUTO then
        finalPredict = (dist / 1150) + (ping * 0.85)
    else
        finalPredict = CONFIG.PREDICTION_AMOUNT + (ping * 0.5)
    end

    local verticalAdj = (dist / 500)^2 * 0.5

    local predicted = basePos + (velocity * finalPredict) + Vector3.new(CONFIG.PREDICTION_X_ADJ, CONFIG.PREDICTION_Y_ADJ + verticalAdj, CONFIG.PREDICTION_Z_ADJ)

    return predicted
end

-- [[ TARGET SELECTION ]] --
local function getNearestTarget()
    local bestDist   = CONFIG.FOV
    local bestPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not CONFIG.TEAM_CHECK or player.Team ~= LocalPlayer.Team then
                if isAlive(player) then
                    local char = player.Character
                    local part = char:FindFirstChild(CONFIG.TARGET_PART) or char:FindFirstChild("HumanoidRootPart")
                    if part then
                        local screenPos, onScreen, depth = getScreenPos(part.Position)
                        if onScreen and depth > 0 then
                            local dist = (screenPos - screenCenter).Magnitude
                            if dist < bestDist then
                                if checkVisibility(part, player) then
                                    bestDist = dist
                                    bestPlayer = player
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPlayer
end

-- [[ ENGINE HOOKS ]] --
pcall(function() cachedMouseRef = LocalPlayer:GetMouse() end)

local function isCameraCall()
    if not CONFIG.FILTER_CAMERA then return false end
    local stack = debug.traceback():lower()
    if stack:find("camera") or stack:find("control") or stack:find("collision") then
        if stack:find("module") or stack:find("common") or stack:find("input") then
            return true
        end
    end
    return false
end

-- Index Detour
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() and CONFIG.ENABLED and not CONFIG.PANIC and cachedTargetPos then
        if self == cachedMouseRef and not isCameraCall() then
            if key == "Hit" then
                return CFrame.new(cachedTargetPos)
            elseif key == "Target" then
                return currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild(CONFIG.TARGET_PART)
            end
        end
    end
    return oldIndex(self, key)
end)

-- Namecall Detour
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
                    args[2] = getSafeUnit(diff) * direction.Magnitude
                end
            end
        elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
            if not isCameraCall() then
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local origin = ray.Origin
                    local direction = ray.Direction
                    local diff = (cachedTargetPos - origin)
                    args[1] = Ray.new(origin, getSafeUnit(diff) * direction.Magnitude)
                end
            end
        elseif (method == "ScreenPointToRay" or method == "ViewportPointToRay") and self == Camera then
            local result = oldNamecall(self, ...)
            if typeof(result) == "Ray" then
                local origin = result.Origin
                local diff = (cachedTargetPos - origin)
                return Ray.new(origin, getSafeUnit(diff) * result.Direction.Magnitude)
            end
        elseif method == "FireServer" and self:IsA("RemoteEvent") then
            for i = 1, #args do
                local arg = args[i]
                if typeof(arg) == "Vector3" then
                    local screenPos, onScreen = getScreenPos(arg)
                    if onScreen and (screenPos - screenCenter).Magnitude < CONFIG.FOV * 2 then
                        args[i] = cachedTargetPos
                    end
                elseif typeof(arg) == "CFrame" then
                    local screenPos, onScreen = getScreenPos(arg.Position)
                    if onScreen and (screenPos - screenCenter).Magnitude < CONFIG.FOV * 2 then
                        args[i] = CFrame.new(cachedTargetPos)
                    end
                end
            end
        end
    end

    return oldNamecall(self, unpack(args))
end)

-- [[ ESP SYSTEM ]] --
local function createPlayerESP(player)
    if espObjects[player] then return end
    espObjects[player] = {
        boxOutline  = createDrawing("Square", {Thickness = 3, Color = Color3.new(0,0,0), Filled = false}),
        box         = createDrawing("Square", {Thickness = 1, Color = CONFIG.ESP_BOX_COLOR, Filled = false}),
        name        = createDrawing("Text",   {Size = 13, Color = Color3.new(1,1,1), Outline = true, Center = true}),
        healthBar   = createDrawing("Square", {Thickness = 1, Filled = true}),
    }
end

local function removePlayerESP(player)
    if not espObjects[player] then return end
    for _, d in pairs(espObjects[player]) do pcall(function() d:Remove() end) end
    espObjects[player] = nil
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not CONFIG.ESP_ENABLED or CONFIG.PANIC or (CONFIG.TEAM_CHECK and player.Team == LocalPlayer.Team) then
                removePlayerESP(player)
            else
                if not espObjects[player] then createPlayerESP(player) end
                local objs = espObjects[player]
                local char = player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum  = char and char:FindFirstChildOfClass("Humanoid")

                if root and hum and hum.Health > 0 then
                    local screenPos, onScreen, depth = getScreenPos(root.Position)
                    local distance = (Camera.CFrame.Position - root.Position).Magnitude

                    if onScreen and depth > 0 and distance <= CONFIG.ESP_MAX_DIST then
                        local size = Vector2.new(2200 / depth, 3200 / depth)
                        local pos  = Vector2.new(screenPos.X - size.X / 2, screenPos.Y - size.Y / 2)

                        objs.boxOutline.Position = pos; objs.boxOutline.Size = size; objs.boxOutline.Visible = CONFIG.ESP_BOX
                        objs.box.Position = pos; objs.box.Size = size; objs.box.Visible = CONFIG.ESP_BOX
                        objs.box.Color = (currentTarget == player) and Color3.new(1,1,0) or CONFIG.ESP_BOX_COLOR
                        objs.box.Filled = false -- ABSOLUTELY NO FILLING

                        local info = player.Name
                        if CONFIG.ESP_DISTANCE then info = info .. " [" .. math.floor(distance) .. "m]" end
                        objs.name.Text = info; objs.name.Position = Vector2.new(screenPos.X, pos.Y - 15); objs.name.Visible = CONFIG.ESP_NAMES

                        if CONFIG.ESP_HEALTH then
                            local hp = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
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

-- [[ VISUALS: FOV & INDICATORS ]] --
local fovCircle = createDrawing("Circle", {
    Thickness    = CONFIG.FOV_THICKNESS,
    Color        = CONFIG.FOV_COLOR,
    NumSides     = CONFIG.FOV_SIDES,
    Transparency = CONFIG.FOV_TRANSPARENCY,
    Filled       = false
})

local targetDot = createDrawing("Circle", {
    Radius    = 4,
    Color     = CONFIG.TARGET_DOT_COLOR,
    Filled    = true,
    Visible   = false
})

local targetLine = createDrawing("Line", {
    Thickness = 1,
    Color     = CONFIG.TARGET_LINE_COLOR,
    Visible   = false
})

-- [[ USER INTERFACE ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = UI_NAME; ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

local MobileBtn = Instance.new("TextButton")
MobileBtn.Size = UDim2.new(0,55,0,55); MobileBtn.Position = UDim2.new(0,20,0.5,-27)
MobileBtn.BackgroundColor3 = CONFIG.BG; MobileBtn.TextColor3 = CONFIG.ACCENT
MobileBtn.Text = "ELITE"; MobileBtn.Font = Enum.Font.GothamBold; MobileBtn.TextSize = 14
MobileBtn.Parent = ScreenGui
Instance.new("UICorner", MobileBtn).CornerRadius = UDim.new(1,0)
local btnStroke = Instance.new("UIStroke", MobileBtn); btnStroke.Color = CONFIG.ACCENT; btnStroke.Thickness = 2

do
    local dragging, dragStart, startPos
    MobileBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = MobileBtn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local delta = i.Position - dragStart
            MobileBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function() dragging = false end)
end

local Win = Instance.new("Frame")
Win.Size = UDim2.new(0,300,0,420); Win.Position = UDim2.new(0.5,-150,0.5,-210)
Win.BackgroundColor3 = CONFIG.BG; Win.Visible = false; Win.Parent = ScreenGui
Instance.new("UICorner", Win)
local winStroke = Instance.new("UIStroke", Win); winStroke.Color = CONFIG.ACCENT; winStroke.Thickness = 2

local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1,0,0,40); TBar.BackgroundColor3 = CONFIG.BG2; TBar.Parent = Win
Instance.new("UICorner", TBar)

local TLabel = Instance.new("TextLabel")
TLabel.Size = UDim2.new(1,-40,1,0); TLabel.Position = UDim2.new(0,15,0,0); TLabel.BackgroundTransparency = 1
TLabel.Text = "IRON SHADOW ELITE v" .. VERSION; TLabel.TextColor3 = Color3.new(1,1,1); TLabel.Font = "GothamBold"; TLabel.TextSize = 15; TLabel.TextXAlignment = "Left"; TLabel.Parent = TBar

local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1,0,1,-45); Content.Position = UDim2.new(0,0,0,45); Content.BackgroundTransparency = 1; Content.CanvasSize = UDim2.new(0,0,0,850); Content.ScrollBarThickness = 2; Content.Parent = Win
local layout = Instance.new("UIListLayout", Content); layout.HorizontalAlignment = "Center"; layout.Padding = UDim.new(0,6)
Instance.new("UIPadding", Content).PaddingTop = UDim.new(0,5)

local function addToggle(txt, configKey, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.92,0,0,34); b.BackgroundColor3 = CONFIG.BG2; b.Text = txt..": "..(CONFIG[configKey] and "ON" or "OFF")
    b.TextColor3 = CONFIG[configKey] and CONFIG.ACCENT or Color3.new(0.7,0.7,0.7); b.Font = "GothamBold"; b.TextSize = 12; b.Parent = Content
    Instance.new("UICorner", b)
    b.MouseButton1Click:Connect(function()
        CONFIG[configKey] = not CONFIG[configKey]
        b.Text = txt..": "..(CONFIG[configKey] and "ON" or "OFF")
        b.TextColor3 = CONFIG[configKey] and CONFIG.ACCENT or Color3.new(0.7,0.7,0.7)
        if cb then cb(CONFIG[configKey]) end
    end)
end

local function addSlider(txt, min, max, configKey, factor, cb)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0.92,0,0,48); f.BackgroundColor3 = CONFIG.BG2; f.Parent = Content
    Instance.new("UICorner", f)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,22); l.BackgroundTransparency = 1; l.Text = txt..": "..CONFIG[configKey]; l.TextColor3 = Color3.new(1,1,1); l.TextSize = 11; l.Font = "Gotham"; l.Parent = f
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0.85,0,0,5); bar.Position = UDim2.new(0.075,0,0.65,0); bar.BackgroundColor3 = Color3.new(0.2,0.2,0.2); bar.Parent = f
    local fill = Instance.new("Frame")
    local currentVal = CONFIG[configKey]
    local startP = (currentVal - min) / (max - min)
    fill.Size = UDim2.new(math.clamp(startP, 0, 1),0,1,0); fill.BackgroundColor3 = CONFIG.ACCENT; fill.Parent = bar

    local function updateSlider(input)
        local p = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = min + p*(max-min)
        if factor >= 1 then val = math.floor(val) end
        fill.Size = UDim2.new(p,0,1,0); l.Text = txt..": "..tostring(val); CONFIG[configKey] = val
        if cb then cb(val) end
    end
    local draggingSlider = false
    f.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = true; updateSlider(input) end end)
    UserInputService.InputChanged:Connect(function(input) if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateSlider(input) end end)
    UserInputService.InputEnded:Connect(function() draggingSlider = false end)
end

addToggle("Silent Aim Enabled", "ENABLED")
addToggle("Team Check", "TEAM_CHECK")
addToggle("Visibility Check", "VISIBILITY_CHECK")
addSlider("FOV Radius", 10, 800, "FOV", 1)
addSlider("FOV Transparency", 0, 1, "FOV_TRANSPARENCY", 0.1)
addToggle("Show FOV Circle", "SHOW_FOV")
addToggle("ESP Enabled", "ESP_ENABLED")
addToggle("ESP Boxes", "ESP_BOX")
addToggle("Prediction Enabled", "PREDICTION_ENABLED")
addToggle("Auto Prediction", "PREDICTION_AUTO")
addToggle("Target Dot", "SHOW_TARGET_DOT")
addToggle("Target Line", "SHOW_TARGET_LINE")
addToggle("Filter Camera", "FILTER_CAMERA")

MobileBtn.MouseButton1Click:Connect(function() Win.Visible = not Win.Visible end)

-- [[ RUNTIME CORE ]] --
RunService.RenderStepped:Connect(function()
    if CONFIG.PANIC then return end
    screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    currentTarget = CONFIG.ENABLED and getNearestTarget() or nil
    cachedTargetPos = currentTarget and getPredictedPosition(currentTarget) or nil

    -- Visual: FOV
    if CONFIG.SHOW_FOV and CONFIG.ENABLED then
        fovCircle.Position     = screenCenter
        fovCircle.Radius       = CONFIG.FOV
        fovCircle.Transparency = CONFIG.FOV_TRANSPARENCY
        fovCircle.Visible      = true
        fovCircle.Color        = currentTarget and Color3.new(1, 1, 0) or CONFIG.FOV_COLOR
        fovCircle.Filled       = false
    else
        fovCircle.Visible  = false
    end

    -- Visual: Indicators
    if cachedTargetPos then
        local sp, onScreen = getScreenPos(cachedTargetPos)

        if CONFIG.SHOW_TARGET_DOT and onScreen then
            targetDot.Position = sp
            targetDot.Visible  = true
        else
            targetDot.Visible  = false
        end

        if CONFIG.SHOW_TARGET_LINE and onScreen then
            targetLine.From    = screenCenter
            targetLine.To      = sp
            targetLine.Visible = true
        else
            targetLine.Visible = false
        end
    else
        targetDot.Visible  = false
        targetLine.Visible = false
    end

    updateESP()
end)

print("[Iron Shadow Elite] v"..VERSION.." Initialized. Visual fixes applied.")
