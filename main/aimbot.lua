--[[
    ESP + AIMBOT + AUTOSHOOT
    СТИЛЬ: Градиентный тёмный фон, оранжевые акценты, скруглённые углы.
    Функции: ESP (настраиваемый размер, цвета, радужный режим), Aimbot (FOV, плавность),
    автострельба (одиночная/непрерывная), перетаскиваемая кнопка, горячие клавиши.
    Управление: кнопка-шестерёнка (перетаскивается), RightShift – показать/скрыть панель.
]]

-- ========== НАСТРОЙКИ ПО УМОЛЧАНИЮ ==========
local DefaultSettings = {
    ESP = {
        Enabled = true,
        BoxColor = Color3.new(1, 0.5, 0),     -- оранжевый
        BoxThickness = 2,
        BoxTransparency = 0,
        BoxSizeScale = 1.0,
        RainbowMode = false,
        RainbowSpeed = 2.0,
        ShowName = true,
        ShowDistance = true,
        NameColor = Color3.new(1, 1, 1),
        LineToTarget = true,
        LineColor = Color3.new(1, 0.5, 0),
    },
    Aimbot = {
        Enabled = true,
        Part = "Head",
        FOVRadius = 150,
        Smoothness = 0.25,
        MaxDistance = 300,
        UseInstantTurn = false,
    },
    AutoShoot = {
        Enabled = true,
        Mode = "Continuous",
        ShootDistance = 70,
        Delay = 0.12,
    },
    TeamCheck = {
        Enabled = true,
        ShowTeammates = false,
    },
    Hotkeys = {
        ToggleESP = Enum.KeyCode.F1,
        ToggleAimbot = Enum.KeyCode.F2,
        ToggleAutoShoot = Enum.KeyCode.F3,
    }
}

-- ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Settings = nil
local espObjects = {}
local currentTarget = nil
local lastShootTime = 0
local isShootingNow = false
local rainbowHue = 0

-- GUI элементы
local gui = nil
local draggableButton = nil
local guiVisible = true

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
local function deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then copy[k] = deepCopy(v)
        else copy[k] = v end
    end
    return copy
end

local function IsEnemy(player)
    if player == LocalPlayer then return false end
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then return false end
    if Settings.TeamCheck.Enabled and LocalPlayer.Team and player.Team and LocalPlayer.Team == player.Team then return false end
    return true
end

local function GetTargetPosition(player)
    local char = player.Character
    if not char then return nil end
    local part = char:FindFirstChild(Settings.Aimbot.Part)
    if part then return part.Position end
    local root = char:FindFirstChild("HumanoidRootPart")
    return root and root.Position or nil
end

local function WorldToScreen(pos)
    local vec, onScreen = Camera:WorldToScreenPoint(pos)
    return Vector2.new(vec.X, vec.Y), onScreen
end

local function GetBestTarget()
    local bestTarget = nil
    local bestScore = Settings.Aimbot.FOVRadius > 0 and Settings.Aimbot.FOVRadius or math.huge
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local cameraPos = Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if IsEnemy(player) then
            local targetPos = GetTargetPosition(player)
            if targetPos then
                local dist = (targetPos - cameraPos).Magnitude
                if dist <= Settings.Aimbot.MaxDistance then
                    local screenPos, onScreen = WorldToScreen(targetPos)
                    if onScreen then
                        local score = (screenPos - center).Magnitude
                        if score < bestScore then
                            bestScore = score
                            bestTarget = player
                        end
                    end
                end
            end
        end
    end
    return bestTarget
end

local function AimAt(targetPlayer)
    if not targetPlayer then return end
    local targetPos = GetTargetPosition(targetPlayer)
    if not targetPos then return end
    local cameraPos = Camera.CFrame.Position
    local direction = (targetPos - cameraPos).unit
    local targetCFrame = CFrame.new(cameraPos, cameraPos + direction)
    if Settings.Aimbot.UseInstantTurn then
        Camera.CFrame = targetCFrame
    else
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, Settings.Aimbot.Smoothness)
    end
end

local function Shoot()
    local now = tick()
    if now - lastShootTime >= Settings.AutoShoot.Delay then
        lastShootTime = now
        mouse1press()
        task.wait(0.02)
        mouse1release()
    end
end

-- ========== ESP ==========
local function GetRainbowColor()
    rainbowHue = (rainbowHue + Settings.ESP.RainbowSpeed * RunService.RenderStepped:Wait()) % 360
    return Color3.fromHSV(rainbowHue/360, 1, 1)
end

local function UpdateESPColors()
    local boxColor = Settings.ESP.RainbowMode and GetRainbowColor() or Settings.ESP.BoxColor
    local lineColor = Settings.ESP.RainbowMode and GetRainbowColor() or Settings.ESP.LineColor
    for _, esp in pairs(espObjects) do
        esp.box.Color = boxColor
        esp.line.Color = lineColor
        esp.text.Color = Settings.ESP.NameColor
    end
end

local function CreateESP(player)
    local esp = {}
    esp.box = Drawing.new("Square")
    esp.box.Thickness = Settings.ESP.BoxThickness
    esp.box.Filled = false
    esp.box.Color = Settings.ESP.RainbowMode and GetRainbowColor() or Settings.ESP.BoxColor
    esp.box.Transparency = Settings.ESP.BoxTransparency
    esp.box.Visible = false

    esp.line = Drawing.new("Line")
    esp.line.Thickness = 1
    esp.line.Color = Settings.ESP.RainbowMode and GetRainbowColor() or Settings.ESP.LineColor
    esp.line.Visible = false

    esp.text = Drawing.new("Text")
    esp.text.Size = 14
    esp.text.Center = true
    esp.text.Outline = true
    esp.text.OutlineColor = Color3.new(0,0,0)
    esp.text.Color = Settings.ESP.NameColor
    esp.text.Visible = false

    espObjects[player] = esp
end

local function UpdateESP(player)
    local esp = espObjects[player]
    if not esp then return end
    local isEnemy = IsEnemy(player)
    local show = Settings.ESP.Enabled and (isEnemy or Settings.TeamCheck.ShowTeammates)
    if not show then
        esp.box.Visible = false; esp.line.Visible = false; esp.text.Visible = false
        return
    end
    local char = player.Character
    if not char then
        esp.box.Visible = false; esp.line.Visible = false; esp.text.Visible = false
        return
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    if not root and not head then return end
    local rootPos = root and root.Position or head.Position
    local headPos = head and head.Position or rootPos
    local screenHead, headOnScreen = WorldToScreen(headPos)
    local screenRoot, rootOnScreen = WorldToScreen(rootPos)

    if headOnScreen and rootOnScreen then
        local boxHeight = math.abs(screenRoot.Y - screenHead.Y) * Settings.ESP.BoxSizeScale
        if boxHeight < 20 then boxHeight = 40 end
        local boxWidth = boxHeight * 0.6
        local boxX = screenHead.X - boxWidth/2
        local boxY = screenHead.Y - boxHeight * 0.1
        esp.box.Position = Vector2.new(boxX, boxY)
        esp.box.Size = Vector2.new(boxWidth, boxHeight)
        esp.box.Visible = true
    else
        esp.box.Visible = false
    end

    if Settings.ESP.LineToTarget and rootOnScreen then
        local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        esp.line.From = center
        esp.line.To = screenRoot
        esp.line.Visible = true
    else
        esp.line.Visible = false
    end

    if Settings.ESP.ShowName and headOnScreen then
        local dist = (rootPos - Camera.CFrame.Position).Magnitude
        local txt = player.Name
        if Settings.ESP.ShowDistance then txt = txt .. " [" .. math.floor(dist) .. "m]" end
        esp.text.Text = txt
        esp.text.Position = Vector2.new(screenHead.X, screenHead.Y - 20)
        esp.text.Visible = true
    else
        esp.text.Visible = false
    end
end

local function RemoveESP(player)
    local esp = espObjects[player]
    if esp then
        esp.box:Remove(); esp.line:Remove(); esp.text:Remove()
        espObjects[player] = nil
    end
end

-- ========== ПЕРЕДВИГАЕМАЯ КНОПКА ==========
local function CreateDraggableButton()
    local btn = Instance.new("ImageButton")
    btn.Size = UDim2.new(0, 55, 0, 55)
    btn.Position = UDim2.new(0, 20, 0.5, -27)
    btn.BackgroundColor3 = Color3.fromRGB(30,30,40)
    btn.BackgroundTransparency = 0.1
    btn.Image = "rbxassetid://6031094773"
    btn.ImageColor3 = Color3.fromRGB(255,140,0)
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = btn
    -- добавим лёгкую тень
    local shadow = Instance.new("UIShadowEffect")
    shadow.Enabled = true
    btn.Parent = game:GetService("CoreGui")
    
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = btn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    btn.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            local newX = startPos.X.Offset + delta.X
            local newY = startPos.Y.Offset + delta.Y
            btn.Position = UDim2.new(0, newX, 0, newY)
        end
    end)
    
    btn.MouseButton1Click:Connect(function()
        guiVisible = not guiVisible
        if gui then gui.Enabled = guiVisible end
    end)
    
    return btn
end

-- ========== СОЗДАНИЕ GUI С ГРАДИЕНТАМИ И ОРАНЖЕВЫМИ АКЦЕНТАМИ ==========
local function CreateGradientFrame(parent, colorTop, colorBottom, transparency)
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = colorTop
    frame.BackgroundTransparency = transparency or 0
    frame.BorderSizePixel = 0
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorTop),
        ColorSequenceKeypoint.new(1, colorBottom)
    })
    gradient.Parent = frame
    frame.Parent = parent
    return frame
end

local function CreateSettingsGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OrangeAimbotGUI"
    screenGui.Parent = game:GetService("CoreGui")
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = guiVisible

    -- Основное окно с градиентом (тёмный)
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 360, 0, 520)
    mainFrame.Position = UDim2.new(0, 90, 0, 90)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BackgroundTransparency = 0
    mainFrame.BorderSizePixel = 0
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 16)
    mainCorner.Parent = mainFrame
    -- градиент фона (чёрный -> тёмно-серый)
    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20,20,28)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(35,35,45))
    })
    bgGradient.Parent = mainFrame
    mainFrame.Parent = screenGui

    -- Заголовок с оранжевым градиентом
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 45)
    titleBar.BackgroundColor3 = Color3.fromRGB(255,100,0)
    titleBar.BackgroundTransparency = 0
    titleBar.BorderSizePixel = 0
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 16)
    titleCorner.Parent = titleBar
    -- отдельно нижние углы скроем, чтобы они не торчали
    local titleCorner2 = Instance.new("UICorner")
    titleCorner2.CornerRadius = UDim.new(0, 0)
    titleCorner2.Parent = titleBar -- не нужно, просто для идеи
    -- градиент заголовка: оранжевый -> тёмно-оранжевый
    local headerGrad = Instance.new("UIGradient")
    headerGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 70, 0))
    })
    headerGrad.Parent = titleBar
    titleBar.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -50, 1, 0)
    titleLabel.Position = UDim2.new(0, 15, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚡ ORANGE AIMBOT v3"
    titleLabel.TextColor3 = Color3.fromRGB(255,255,255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Font = Enum.Font.GothamSemibold
    titleLabel.TextSize = 18
    titleLabel.TextStrokeTransparency = 0.5
    titleLabel.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 35, 1, -10)
    closeBtn.Position = UDim2.new(1, -40, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(50,50,60)
    closeBtn.BackgroundTransparency = 0.3
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 150, 100)
    closeBtn.TextSize = 22
    closeBtn.Font = Enum.Font.GothamBold
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeBtn
    closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function()
        guiVisible = false
        screenGui.Enabled = false
    end)

    -- Скролл-фрейм с закруглением
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -55)
    scroll.Position = UDim2.new(0, 8, 0, 52)
    scroll.BackgroundColor3 = Color3.fromRGB(25,25,35)
    scroll.BackgroundTransparency = 0.5
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 850)
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Color3.fromRGB(255,120,0)
    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 12)
    scrollCorner.Parent = scroll
    scroll.Parent = mainFrame

    local uiList = Instance.new("UIListLayout")
    uiList.Padding = UDim.new(0, 6)
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Parent = scroll

    -- Вспомогательные функции создания элементов в стиле оранжевый/тёмный
    local function AddSection(text)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 34)
        section.BackgroundColor3 = Color3.fromRGB(45,45,55)
        section.BackgroundTransparency = 0.4
        local secCorner = Instance.new("UICorner")
        secCorner.CornerRadius = UDim.new(0, 8)
        secCorner.Parent = section
        local grad = Instance.new("UIGradient")
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(55,55,65)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(35,35,45))
        })
        grad.Parent = section
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -10, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = "  " .. text
        label.TextColor3 = Color3.fromRGB(255, 180, 80)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 15
        label.Parent = section
        
        section.Parent = scroll
        return section
    end

    local function AddToggle(text, getter, setter)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 34)
        frame.BackgroundTransparency = 1
        frame.Parent = scroll
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(220,220,230)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.Parent = frame
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 65, 0, 26)
        btn.Position = UDim2.new(1, -72, 0.5, -13)
        btn.BackgroundColor3 = getter() and Color3.fromRGB(255,100,0) or Color3.fromRGB(80,80,90)
        btn.Text = getter() and "ON" or "OFF"
        btn.TextColor3 = Color3.new(1,1,1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 14)
        btnCorner.Parent = btn
        btn.Parent = frame
        
        btn.MouseButton1Click:Connect(function()
            setter(not getter())
            btn.BackgroundColor3 = getter() and Color3.fromRGB(255,100,0) or Color3.fromRGB(80,80,90)
            btn.Text = getter() and "ON" or "OFF"
            if text:find("ESP") or text:find("радужный") then
                UpdateESPColors()
            end
        end)
        return btn
    end

    local function AddSlider(text, minVal, maxVal, getter, setter, format)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 52)
        frame.BackgroundTransparency = 1
        frame.Parent = scroll
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 20)
        label.BackgroundTransparency = 1
        label.Text = text .. ": " .. format(getter())
        label.TextColor3 = Color3.fromRGB(220,220,230)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.Parent = frame
        
        local sliderBg = Instance.new("Frame")
        sliderBg.Size = UDim2.new(1, -20, 0, 4)
        sliderBg.Position = UDim2.new(0, 10, 0, 28)
        sliderBg.BackgroundColor3 = Color3.fromRGB(60,60,70)
        sliderBg.BorderSizePixel = 0
        local sliderCorner = Instance.new("UICorner")
        sliderCorner.CornerRadius = UDim.new(1,0)
        sliderCorner.Parent = sliderBg
        sliderBg.Parent = frame
        
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((getter()-minVal)/(maxVal-minVal), 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(255,120,0)
        fill.BorderSizePixel = 0
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1,0)
        fillCorner.Parent = fill
        fill.Parent = sliderBg
        
        local dragBtn = Instance.new("TextButton")
        dragBtn.Size = UDim2.new(0, 14, 0, 14)
        dragBtn.Position = UDim2.new((getter()-minVal)/(maxVal-minVal), -7, 0.5, -7)
        dragBtn.BackgroundColor3 = Color3.fromRGB(255,180,80)
        dragBtn.Text = ""
        dragBtn.AutoButtonColor = false
        local dragCorner = Instance.new("UICorner")
        dragCorner.CornerRadius = UDim.new(1,0)
        dragCorner.Parent = dragBtn
        dragBtn.Parent = sliderBg
        
        local dragging = false
        dragBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
        end)
        dragBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        dragBtn.MouseMoved:Connect(function()
            if dragging then
                local rel = (Mouse.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
                local newVal = math.clamp(minVal + rel * (maxVal - minVal), minVal, maxVal)
                setter(newVal)
                label.Text = text .. ": " .. format(newVal)
                fill.Size = UDim2.new((newVal-minVal)/(maxVal-minVal), 0, 1, 0)
                dragBtn.Position = UDim2.new((newVal-minVal)/(maxVal-minVal), -7, 0.5, -7)
                if text:find("Box Size") then UpdateESPColors() end
            end
        end)
        return sliderBg
    end

    -- Заполнение секций
    AddSection("ОСНОВНЫЕ")
    AddToggle("🔘 Включить ESP", function() return Settings.ESP.Enabled end, function(v) Settings.ESP.Enabled = v end)
    AddToggle("🎯 Включить Aimbot", function() return Settings.Aimbot.Enabled end, function(v) Settings.Aimbot.Enabled = v end)
    AddToggle("🔫 Автострельба", function() return Settings.AutoShoot.Enabled end, function(v) Settings.AutoShoot.Enabled = v end)
    AddToggle("👥 Командная проверка", function() return Settings.TeamCheck.Enabled end, function(v) Settings.TeamCheck.Enabled = v end)

    AddSection("✨ ESP НАСТРОЙКИ")
    AddSlider("Размер бокса", 0.5, 2.0, function() return Settings.ESP.BoxSizeScale end, function(v) Settings.ESP.BoxSizeScale = v end, function(v) return string.format("%.2f",v) end)
    AddSlider("Толщина контура", 1, 4, function() return Settings.ESP.BoxThickness end, function(v) Settings.ESP.BoxThickness = v; UpdateESPColors() end, function(v) return tostring(v) end)
    AddToggle("🌈 Радужные контуры", function() return Settings.ESP.RainbowMode end, function(v) Settings.ESP.RainbowMode = v; UpdateESPColors() end)
    AddSlider("Скорость радуги", 0.5, 10, function() return Settings.ESP.RainbowSpeed end, function(v) Settings.ESP.RainbowSpeed = v end, function(v) return string.format("%.1f",v) end)
    AddToggle("Показывать имя", function() return Settings.ESP.ShowName end, function(v) Settings.ESP.ShowName = v end)
    AddToggle("Показывать дистанцию", function() return Settings.ESP.ShowDistance end, function(v) Settings.ESP.ShowDistance = v end)
    AddToggle("Линия к цели", function() return Settings.ESP.LineToTarget end, function(v) Settings.ESP.LineToTarget = v end)

    AddSection("🎯 AIMBOT")
    AddSlider("FOV радиус (пикс)", 0, 500, function() return Settings.Aimbot.FOVRadius end, function(v) Settings.Aimbot.FOVRadius = v end, function(v) tostring(math.floor(v)) end)
    AddSlider("Макс. дистанция", 50, 500, function() return Settings.Aimbot.MaxDistance end, function(v) Settings.Aimbot.MaxDistance = v end, function(v) tostring(math.floor(v)) end)
    AddSlider("Плавность", 0, 1, function() return Settings.Aimbot.Smoothness end, function(v) Settings.Aimbot.Smoothness = v end, function(v) string.format("%.2f",v) end)
    AddToggle("Мгновенный поворот", function() return Settings.Aimbot.UseInstantTurn end, function(v) Settings.Aimbot.UseInstantTurn = v end)

    AddSection("🔫 АВТОСТРЕЛЬБА")
    AddSlider("Дистанция стрельбы", 10, 200, function() return Settings.AutoShoot.ShootDistance end, function(v) Settings.AutoShoot.ShootDistance = v end, function(v) tostring(math.floor(v)) end)
    AddSlider("Задержка (сек)", 0.05, 0.5, function() return Settings.AutoShoot.Delay end, function(v) Settings.AutoShoot.Delay = v end, function(v) string.format("%.2f",v) end)
    
    local modeFrame = Instance.new("Frame")
    modeFrame.Size = UDim2.new(1, 0, 0, 34)
    modeFrame.BackgroundTransparency = 1
    modeFrame.Parent = scroll
    local modeLabel = Instance.new("TextLabel")
    modeLabel.Size = UDim2.new(0.6, 0, 1, 0)
    modeLabel.BackgroundTransparency = 1
    modeLabel.Text = "Режим стрельбы:"
    modeLabel.TextColor3 = Color3.fromRGB(220,220,230)
    modeLabel.TextXAlignment = Enum.TextXAlignment.Left
    modeLabel.Font = Enum.Font.Gotham
    modeLabel.TextSize = 13
    modeLabel.Parent = modeFrame
    local modeBtn = Instance.new("TextButton")
    modeBtn.Size = UDim2.new(0, 100, 0, 28)
    modeBtn.Position = UDim2.new(1, -108, 0.5, -14)
    modeBtn.BackgroundColor3 = Color3.fromRGB(255,100,0)
    modeBtn.Text = Settings.AutoShoot.Mode
    modeBtn.TextColor3 = Color3.new(1,1,1)
    modeBtn.Font = Enum.Font.GothamBold
    modeBtn.TextSize = 12
    local modeCorner = Instance.new("UICorner")
    modeCorner.CornerRadius = UDim.new(0, 14)
    modeCorner.Parent = modeBtn
    modeBtn.Parent = modeFrame
    modeBtn.MouseButton1Click:Connect(function()
        Settings.AutoShoot.Mode = (Settings.AutoShoot.Mode == "Single") and "Continuous" or "Single"
        modeBtn.Text = Settings.AutoShoot.Mode
    end)

    AddSection("🔧 СБРОС")
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1, -20, 0, 36)
    resetBtn.Position = UDim2.new(0, 10, 0, 0)
    resetBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 20)
    resetBtn.Text = "Сбросить все настройки"
    resetBtn.TextColor3 = Color3.new(1,1,1)
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 14
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 10)
    resetCorner.Parent = resetBtn
    resetBtn.Parent = scroll
    resetBtn.MouseButton1Click:Connect(function()
        Settings = deepCopy(DefaultSettings)
        screenGui:Destroy()
        if draggableButton then draggableButton:Destroy() end
        gui = CreateSettingsGUI()
        draggableButton = CreateDraggableButton()
        UpdateESPColors()
    end)

    return screenGui
end

-- ========== ОСНОВНОЙ ЦИКЛ ==========
local function OnRender()
    if Settings.ESP.RainbowMode then UpdateESPColors() end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if not espObjects[player] then CreateESP(player) end
        UpdateESP(player)
    end
    for player, _ in pairs(espObjects) do
        if not player or not player.Parent then RemoveESP(player) end
    end
    
    if Settings.Aimbot.Enabled then
        local target = GetBestTarget()
        if target then
            currentTarget = target
            AimAt(currentTarget)
            if Settings.AutoShoot.Enabled then
                local pos = GetTargetPosition(currentTarget)
                if pos and (pos - Camera.CFrame.Position).Magnitude <= Settings.AutoShoot.ShootDistance then
                    if Settings.AutoShoot.Mode == "Continuous" then
                        Shoot()
                    elseif Settings.AutoShoot.Mode == "Single" and not isShootingNow then
                        isShootingNow = true
                        Shoot()
                        task.wait(Settings.AutoShoot.Delay + 0.1)
                        isShootingNow = false
                    end
                else
                    isShootingNow = false
                end
            end
        else
            currentTarget = nil
            isShootingNow = false
        end
    end
end

-- ========== ГОРЯЧИЕ КЛАВИШИ ==========
local function SetupHotkeys()
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Settings.Hotkeys.ToggleESP then
            Settings.ESP.Enabled = not Settings.ESP.Enabled
            print("ESP: " .. (Settings.ESP.Enabled and "ON" or "OFF"))
        elseif input.KeyCode == Settings.Hotkeys.ToggleAimbot then
            Settings.Aimbot.Enabled = not Settings.Aimbot.Enabled
            print("Aimbot: " .. (Settings.Aimbot.Enabled and "ON" or "OFF"))
        elseif input.KeyCode == Settings.Hotkeys.ToggleAutoShoot then
            Settings.AutoShoot.Enabled = not Settings.AutoShoot.Enabled
            print("AutoShoot: " .. (Settings.AutoShoot.Enabled and "ON" or "OFF"))
        elseif input.KeyCode == Enum.KeyCode.RightShift then
            guiVisible = not guiVisible
            if gui then gui.Enabled = guiVisible end
        end
    end)
end

-- ========== ЗАПУСК ==========
Settings = deepCopy(DefaultSettings)
draggableButton = CreateDraggableButton()
gui = CreateSettingsGUI()
guiVisible = true
SetupHotkeys()

RunService.RenderStepped:Connect(OnRender)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then CreateESP(player) end
end
Players.PlayerAdded:Connect(CreateESP)
Players.PlayerRemoving:Connect(RemoveESP)

print("✅ ORANGE STYLE ESP+AIMBOT загружен! Перетащите оранжевую шестерёнку. RightShift – скрыть/показать панель.")
