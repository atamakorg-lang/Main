-- ====================================================================================================
--  IRON SHADOW — Silent Aim REBORN v1.5.0 (PREMIUM REVISION)
--  The Ultimate Solution for Precision, Reliability, and Visual Clarity.
--  Universal Raycast Detouring | Advanced Hooking Engine | Multi-Method Redirection | No-Fill Logic
-- ====================================================================================================

local VERSION = "1.5.0"
local UI_NAME = "IRON_REBORN_" .. tostring(math.random(10000000, 99999999))

-- [[ OPTIMIZATION & SERVICES ]] --
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Stats             = game:GetService("Stats")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local Camera            = workspace.CurrentCamera
local LocalPlayer       = Players.LocalPlayer

-- [[ INTERNAL LOGGING ]] --
local function debugPrint(...)
    print("[Iron Shadow Debug]", ...)
end

-- [[ CONFIGURATION ]] --
local CONFIG = {
    ENABLED             = true,
    FOV                 = 150,
    TEAM_CHECK          = false,
    VISIBILITY_CHECK    = true,

    -- Targeting
    TARGET_PART         = "HumanoidRootPart", -- "Head", "HumanoidRootPart", "Random"
    PRIORITIZE_HEAD     = false,

    -- Prediction
    PREDICTION_ENABLED  = true,
    PREDICTION_AUTO     = true,
    PREDICTION_AMOUNT   = 0.165,
    PREDICTION_OFFSET   = Vector3.new(0, 0, 0),

    -- Visuals: FOV
    SHOW_FOV            = true,
    FOV_COLOR           = Color3.fromRGB(255, 0, 0),
    FOV_SIDES           = 64,
    FOV_THICKNESS       = 2,
    FOV_TRANSPARENCY    = 0.6,

    -- Visuals: ESP
    ESP_ENABLED         = true,
    ESP_BOX             = true,
    ESP_NAMES           = true,
    ESP_HEALTH          = true,
    ESP_DISTANCE        = true,
    ESP_MAX_DIST        = 2500,
    ESP_BOX_COLOR       = Color3.fromRGB(255, 0, 0),

    -- Visuals: Target
    SHOW_TARGET_DOT     = true,
    TARGET_DOT_COLOR    = Color3.fromRGB(0, 255, 255),
    SHOW_TARGET_LINE    = false,

    -- Engine Settings
    FILTER_CAMERA       = true,
    REDIRECTION_INTENSITY = 1.0, -- 0.0 to 1.0
    REDISTRIBUTE_REMOTES = true,

    -- UI Style
    ACCENT              = Color3.fromRGB(255, 45, 45),
    BG                  = Color3.fromRGB(12, 12, 14),
    BG2                 = Color3.fromRGB(18, 18, 22),
    PANIC               = false,
}

-- [[ STATE MANAGEMENT ]] --
local espObjects      = {}
local currentTarget   = nil
local cachedTargetPos = nil
local cachedMouseRef  = nil
local screenCenter    = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

-- [[ DRAWING API WRAPPER ]] --
local function createDrawing(type, props)
    local d = Drawing.new(type)

    -- Absolute prevention of "filled" artifacts
    if type == "Square" or type == "Circle" then
        d.Filled = false
    end
    d.Visible = false
    d.Transparency = 1

    for k, v in pairs(props) do
        local ok, err = pcall(function() d[k] = v end)
        if not ok then debugPrint("Drawing Prop Error:", k, err) end
    end

    -- Re-enforce Filled=false for outlines
    if (type == "Square" or type == "Circle") and props.Filled == nil then
        d.Filled = false
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

-- [[ PREDICTION LOGIC ]] --
local function getPredictedPosition(target)
    if not target.Character then return nil end

    local partName = CONFIG.TARGET_PART
    if partName == "Random" then
        local parts = {"Head", "HumanoidRootPart", "UpperTorso"}
        partName = parts[math.random(1, #parts)]
    end

    local part = target.Character:FindFirstChild(partName) or target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Head")
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
        -- High-precision dynamic prediction curve
        finalPredict = (dist / 1000) * 0.95 + (ping * 1.05)
    else
        finalPredict = CONFIG.PREDICTION_AMOUNT + (ping * 0.5)
    end

    -- Basic ballistics compensation (Y drop)
    local verticalAdj = (dist / 400)^1.8 * 0.4

    local predicted = basePos + (velocity * finalPredict) + Vector3.new(0, verticalAdj, 0) + CONFIG.PREDICTION_OFFSET

    return predicted
end

-- [[ TARGET SELECTION ]] --
local function getNearestTarget()
    local bestDist   = CONFIG.FOV
    local bestPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) then
            if not CONFIG.TEAM_CHECK or player.Team ~= LocalPlayer.Team then
                local char = player.Character
                local part = char:FindFirstChild(CONFIG.TARGET_PART) or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")

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
    return bestPlayer
end

-- [[ HOOKING ENGINE ]] --
pcall(function() cachedMouseRef = LocalPlayer:GetMouse() end)

local function isCameraCall()
    if not CONFIG.FILTER_CAMERA then return false end
    local stack = debug.traceback():lower()

    -- Refined stack detection: ignore common weapon modules
    if stack:find("camera") or stack:find("viewport") then
        if stack:find("control") or stack:find("interpolat") or stack:find("shaking") or stack:find("bobbing") then
            return true
        end
    end
    return false
end

-- 1. Detour: Index
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() and CONFIG.ENABLED and not CONFIG.PANIC and cachedTargetPos then
        if self == cachedMouseRef and not isCameraCall() then
            if key == "Hit" then
                return CFrame.new(cachedTargetPos)
            elseif key == "Target" then
                return currentTarget and currentTarget.Character and (currentTarget.Character:FindFirstChild(CONFIG.TARGET_PART) or currentTarget.Character:FindFirstChild("Head"))
            end
        end
    end
    return oldIndex(self, key)
end)

-- 2. Detour: Namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if not checkcaller() and CONFIG.ENABLED and not CONFIG.PANIC and cachedTargetPos then
        -- Universal Raycasting Hooks
        if (method == "Raycast" or method == "Spherecast" or method == "Blockcast" or method == "Shapecast") and self == workspace then
            if not isCameraCall() then
                local origin = args[1]
                local direction = args[2]
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local targetDir = getSafeUnit(cachedTargetPos - origin)
                    args[2] = targetDir * direction.Magnitude
                end
            end

        -- Legacy Raycasting Hooks
        elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
            if not isCameraCall() then
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local targetDir = getSafeUnit(cachedTargetPos - ray.Origin)
                    args[1] = Ray.new(ray.Origin, targetDir * ray.Direction.Magnitude)
                end
            end

        -- Camera Projection Hooks (Critical for modern FPS)
        elseif (method == "ScreenPointToRay" or method == "ViewportPointToRay") and self == Camera then
            local result = oldNamecall(self, ...)
            if typeof(result) == "Ray" then
                local targetDir = getSafeUnit(cachedTargetPos - result.Origin)
                return Ray.new(result.Origin, targetDir * result.Direction.Magnitude)
            end

        -- Remote Redirection (FireServer)
        elseif method == "FireServer" and self:IsA("RemoteEvent") and CONFIG.REDISTRIBUTE_REMOTES then
            for i = 1, #args do
                local arg = args[i]
                if typeof(arg) == "Vector3" then
                    local _, onScreen = getScreenPos(arg)
                    if onScreen and (arg - Camera.CFrame.Position).Magnitude > 5 then
                        args[i] = cachedTargetPos
                    end
                elseif typeof(arg) == "CFrame" then
                    local _, onScreen = getScreenPos(arg.Position)
                    if onScreen and (arg.Position - Camera.CFrame.Position).Magnitude > 5 then
                        args[i] = CFrame.new(cachedTargetPos) * (arg - arg.Position)
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
        boxOutline  = createDrawing("Square", {Thickness = 3, Color = Color3.new(0,0,0)}),
        box         = createDrawing("Square", {Thickness = 1, Color = CONFIG.ESP_BOX_COLOR}),
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

                        -- Box logic - re-enforced unfilled
                        objs.boxOutline.Position = pos; objs.boxOutline.Size = size; objs.boxOutline.Visible = CONFIG.ESP_BOX
                        objs.box.Position = pos; objs.box.Size = size; objs.box.Visible = CONFIG.ESP_BOX
                        objs.box.Color = (currentTarget == player) and Color3.new(1,1,0) or CONFIG.ESP_BOX_COLOR
                        objs.box.Filled = false
                        objs.boxOutline.Filled = false

                        -- Info
                        local info = player.Name
                        if CONFIG.ESP_DISTANCE then info = info .. " [" .. math.floor(distance) .. "m]" end
                        objs.name.Text = info; objs.name.Position = Vector2.new(screenPos.X, pos.Y - 15); objs.name.Visible = CONFIG.ESP_NAMES

                        -- Health
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
    Radius    = 5,
    Color     = CONFIG.TARGET_DOT_COLOR,
    Filled    = true,
    Visible   = false
})

-- [[ USER INTERFACE ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = UI_NAME; ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

local MobileBtn = Instance.new("TextButton")
MobileBtn.Size = UDim2.new(0,55,0,55); MobileBtn.Position = UDim2.new(0,20,0.5,-27)
MobileBtn.BackgroundColor3 = CONFIG.BG; MobileBtn.TextColor3 = CONFIG.ACCENT
MobileBtn.Text = "REBORN"; MobileBtn.Font = Enum.Font.GothamBold; MobileBtn.TextSize = 14
MobileBtn.Parent = ScreenGui
Instance.new("UICorner", MobileBtn).CornerRadius = UDim.new(1,0)
local btnStroke = Instance.new("UIStroke", MobileBtn); btnStroke.Color = CONFIG.ACCENT; btnStroke.Thickness = 2

-- Draggable Logic
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
TBar.Size = UDim2.new(1,0,0,40); TLabel.Size = UDim2.new(1,-40,1,0); TLabel.Position = UDim2.new(0,15,0,0); TLabel.BackgroundTransparency = 1
TLabel.Text = "IRON SHADOW REBORN v" .. VERSION; TLabel.TextColor3 = Color3.new(1,1,1); TLabel.Font = "GothamBold"; TLabel.TextSize = 15; TLabel.TextXAlignment = "Left"; TLabel.Parent = TBar

local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1,0,1,-45); Content.Position = UDim2.new(0,0,0,45); Content.BackgroundTransparency = 1; Content.CanvasSize = UDim2.new(0,0,0,900); Content.ScrollBarThickness = 2; Content.Parent = Win
local layout = Instance.new("UIListLayout", Content); layout.HorizontalAlignment = "Center"; layout.Padding = UDim.new(0,6)
Instance.new("UIPadding", Content).PaddingTop = UDim.new(0,5)

local function addToggle(txt, configKey)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.92,0,0,34); b.BackgroundColor3 = CONFIG.BG2; b.Text = txt..": "..(CONFIG[configKey] and "ON" or "OFF")
    b.TextColor3 = CONFIG[configKey] and CONFIG.ACCENT or Color3.new(0.7,0.7,0.7); b.Font = "GothamBold"; b.TextSize = 12; b.Parent = Content
    Instance.new("UICorner", b)
    b.MouseButton1Click:Connect(function()
        CONFIG[configKey] = not CONFIG[configKey]
        b.Text = txt..": "..(CONFIG[configKey] and "ON" or "OFF")
        b.TextColor3 = CONFIG[configKey] and CONFIG.ACCENT or Color3.new(0.7,0.7,0.7)
    end)
end

local function addSlider(txt, min, max, configKey)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0.92,0,0,48); f.BackgroundColor3 = CONFIG.BG2; f.Parent = Content
    Instance.new("UICorner", f)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,22); l.BackgroundTransparency = 1; l.Text = txt..": "..CONFIG[configKey]; l.TextColor3 = Color3.new(1,1,1); l.TextSize = 11; l.Font = "Gotham"; l.Parent = f
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0.85,0,0,5); bar.Position = UDim2.new(0.075,0,0.65,0); bar.BackgroundColor3 = Color3.new(0.2,0.2,0.2); bar.Parent = f
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(math.clamp((CONFIG[configKey]-min)/(max-min), 0, 1),0,1,0); fill.BackgroundColor3 = CONFIG.ACCENT; fill.Parent = bar

    local function updateSlider(input)
        local p = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = min + p*(max-min)
        if max > 10 then val = math.floor(val) end
        fill.Size = UDim2.new(p,0,1,0); l.Text = txt..": "..tostring(val); CONFIG[configKey] = val
    end
    local draggingSlider = false
    f.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingSlider = true; updateSlider(input) end end)
    UserInputService.InputChanged:Connect(function(input) if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateSlider(input) end end)
    UserInputService.InputEnded:Connect(function() draggingSlider = false end)
end

addToggle("Silent Aim Enabled", "ENABLED")
addToggle("Team Check", "TEAM_CHECK")
addToggle("Visibility Check", "VISIBILITY_CHECK")
addSlider("FOV Radius", 10, 800, "FOV")
addSlider("FOV Transparency", 0, 1, "FOV_TRANSPARENCY")
addToggle("Show FOV", "SHOW_FOV")
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

    -- Visual: FOV - Re-enforce No Fill
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
    else
        targetDot.Visible  = false
    end

    updateESP()
end)

debugPrint("Iron Shadow Reborn v"..VERSION.." Initialized.")
