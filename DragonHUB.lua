local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LP            = Players.LocalPlayer

-- ══════════════════════════════════════════════
-- ESTADO GLOBAL
-- ══════════════════════════════════════════════
local _HUB = {
    AutoHarvest    = false,
    AutoSell       = false,
    AutoSteal      = false,
    StealOwn       = false,
    MinMutation    = false,
}

local function getChar()
    return LP.Character
end

-- ══════════════════════════════════════════════
-- HARVEST
-- ══════════════════════════════════════════════
local function getHarvestableByUserId(userId)
    local results = {}
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end

    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if not plants then continue end
        for _, plant in ipairs(plants:GetChildren()) do
            local plantUserId = plant:GetAttribute("UserId")
            if userId and tostring(plantUserId) ~= tostring(userId) then continue end

            local function checkFruit(fruitObj)
                if not fruitObj:HasTag("Harvestable") then return end
                if _HUB.MinMutation and not fruitObj:GetAttribute("Mutation") then return end
                
                local harvestPart = fruitObj:FindFirstChild("HarvestPart")
                if harvestPart then
                    local prompt = harvestPart:FindFirstChild("HarvestPrompt")
                    if prompt then
                        table.insert(results, {prompt = prompt})
                    end
                end
            end

            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    checkFruit(fruit)
                end
            end
            checkFruit(plant)
        end
    end
    return results
end

local function doAutoHarvest()
    while _HUB.AutoHarvest do
        pcall(function()
            local myId = LP.UserId
            local targets = getHarvestableByUserId(_HUB.StealOwn and myId or nil)
            for _, t in ipairs(targets) do
                if not _HUB.AutoHarvest then break end
                fireproximityprompt(t.prompt)
                task.wait(0.05)
            end
        end)
        task.wait(1)
    end
end

-- ══════════════════════════════════════════════
-- STEAL
-- ══════════════════════════════════════════════
local function getStealTargets()
    local results = {}
    local myId    = tostring(LP.UserId)
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end

    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if not plants then continue end
        for _, plant in ipairs(plants:GetChildren()) do
            local plantUserId = plant:GetAttribute("UserId")
            if tostring(plantUserId) == myId then continue end

            local function checkSteal(fruitObj)
                local harvestPart = fruitObj:FindFirstChild("HarvestPart")
                if harvestPart then
                    local prompt = harvestPart:FindFirstChild("StealPrompt")
                    if prompt and prompt.Enabled then
                        table.insert(results, {prompt = prompt})
                    end
                end
            end

            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    checkSteal(fruit)
                end
            end
            checkSteal(plant)
        end
    end
    return results
end

local function doAutoSteal()
    while _HUB.AutoSteal do
        pcall(function()
            local targets = getStealTargets()
            for _, t in ipairs(targets) do
                if not _HUB.AutoSteal then break end
                fireproximityprompt(t.prompt)
                task.wait(0.1)
            end
        end)
        task.wait(1.5)
    end
end

-- ══════════════════════════════════════════════
-- SELL
-- ══════════════════════════════════════════════
local function doSell()
    pcall(function()
        -- Procura o botao de vender em toda a interface e ativa todos os eventos possiveis
        for _, v in ipairs(LP.PlayerGui:GetDescendants()) do
            if v.Name == "SellButton" and v:IsA("TextButton") then
                firesignal(v.MouseButton1Click)
                firesignal(v.Activated)
                firesignal(v.MouseButton1Down)
                firesignal(v.MouseButton1Up)
                break
            end
        end
    end)
end

local function doAutoSell()
    while _HUB.AutoSell do
        doSell()
        task.wait(2)
    end
end

-- ══════════════════════════════════════════════
-- TOGGLES
-- ══════════════════════════════════════════════
local function toggleHarvest(state)
    _HUB.AutoHarvest = state
    if state then task.spawn(doAutoHarvest) end
end

local function toggleSell(state)
    _HUB.AutoSell = state
    if state then task.spawn(doAutoSell) end
end

local function toggleSteal(state)
    _HUB.AutoSteal = state
    if state then task.spawn(doAutoSteal) end
end

-- ══════════════════════════════════════════════
-- INTERFACE
-- ══════════════════════════════════════════════
local function buildUI()
    local old = LP.PlayerGui:FindFirstChild("GAG_HUB")
    if old then old:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name            = "GAG_HUB"
    ScreenGui.ResetOnSpawn    = false
    ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent          = LP.PlayerGui

    local Main = Instance.new("Frame")
    Main.Name                = "Main"
    Main.Size                = UDim2.new(0, 280, 0, 360)
    Main.Position            = UDim2.new(0, 20, 0.5, -180)
    Main.BackgroundColor3    = Color3.fromRGB(15, 15, 20)
    Main.BorderSizePixel     = 0
    Main.Parent              = ScreenGui
    Main.Active = true

    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)

    local Stroke = Instance.new("UIStroke", Main)
    Stroke.Color     = Color3.fromRGB(80, 200, 100)
    Stroke.Thickness = 1.5

    local Header = Instance.new("Frame")
    Header.Name              = "Header"
    Header.Size              = UDim2.new(1, 0, 0, 36)
    Header.BackgroundColor3  = Color3.fromRGB(20, 20, 28)
    Header.BorderSizePixel   = 0
    Header.Parent            = Main
    Header.Active = true

    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 8)

    local Title = Instance.new("TextLabel")
    Title.Size               = UDim2.new(1, -80, 1, 0)
    Title.Position           = UDim2.new(0, 12, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Font               = Enum.Font.GothamBold
    Title.TextSize           = 13
    Title.TextColor3         = Color3.fromRGB(80, 220, 110)
    Title.TextXAlignment     = Enum.TextXAlignment.Left
    Title.Text               = "GROW A GARDEN HUB"
    Title.Parent             = Header

    -- Botao Minimizar
    local MinBtn = Instance.new("TextButton")
    MinBtn.Size             = UDim2.new(0, 28, 0, 28)
    MinBtn.Position         = UDim2.new(1, -64, 0, 4)
    MinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    MinBtn.Font             = Enum.Font.GothamBold
    MinBtn.TextSize         = 16
    MinBtn.TextColor3       = Color3.new(1, 1, 1)
    MinBtn.Text             = "-"
    MinBtn.BorderSizePixel  = 0
    MinBtn.Parent           = Header
    Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

    -- Botao fechar
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size             = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position         = UDim2.new(1, -32, 0, 4)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseBtn.Font             = Enum.Font.GothamBold
    CloseBtn.TextSize         = 13
    CloseBtn.TextColor3       = Color3.new(1, 1, 1)
    CloseBtn.Text             = "X"
    CloseBtn.BorderSizePixel  = 0
    CloseBtn.Parent           = Header
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

    CloseBtn.Activated:Connect(function()
        ScreenGui:Destroy()
        toggleHarvest(false)
        toggleSell(false)
        toggleSteal(false)
    end)

    -- Arrastar (Mobile e PC)
    local dragging, dragInput, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos  = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    Header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    local Content = Instance.new("Frame")
    Content.Name              = "Content"
    Content.Size              = UDim2.new(1, -16, 1, -48)
    Content.Position          = UDim2.new(0, 8, 0, 44)
    Content.BackgroundTransparency = 1
    Content.Parent            = Main

    local Layout = Instance.new("UIListLayout", Content)
    Layout.SortOrder    = Enum.SortOrder.LayoutOrder
    Layout.Padding      = UDim.new(0, 6)

    -- Funcao de criacao de toggle (Com camada invisivel para capturar 100% dos toques)
    local function makeToggle(parent, label, onToggle)
        local Row = Instance.new("Frame")
        Row.Size             = UDim2.new(1, 0, 0, 40)
        Row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        Row.BorderSizePixel  = 0
        Row.Parent           = parent
        Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 6)

        local Lbl = Instance.new("TextLabel")
        Lbl.Size             = UDim2.new(1, -60, 1, 0)
        Lbl.Position         = UDim2.new(0, 10, 0, 0)
        Lbl.BackgroundTransparency = 1
        Lbl.Font             = Enum.Font.Gotham
        Lbl.TextSize         = 14
        Lbl.TextColor3       = Color3.fromRGB(220, 220, 220)
        Lbl.TextXAlignment   = Enum.TextXAlignment.Left
        Lbl.Text             = label
        Lbl.Parent           = Row

        local ToggleFrame = Instance.new("Frame")
        ToggleFrame.Size             = UDim2.new(0, 46, 0, 24)
        ToggleFrame.Position         = UDim2.new(1, -54, 0.5, -12)
        ToggleFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        ToggleFrame.BorderSizePixel  = 0
        ToggleFrame.Parent           = Row
        Instance.new("UICorner", ToggleFrame).CornerRadius = UDim.new(1, 0)

        local Ball = Instance.new("Frame")
        Ball.Size             = UDim2.new(0, 18, 0, 18)
        Ball.Position         = UDim2.new(0, 3, 0.5, -9)
        Ball.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
        Ball.BorderSizePixel  = 0
        Ball.Parent           = ToggleFrame
        Instance.new("UICorner", Ball).CornerRadius = UDim.new(1, 0)

        -- Camada invisivel que fica por cima de tudo para garantir o clique
        local ClickLayer = Instance.new("TextButton")
        ClickLayer.Size = UDim2.new(1, 0, 1, 0)
        ClickLayer.BackgroundTransparency = 1
        ClickLayer.Text = ""
        ClickLayer.Parent = Row
        ClickLayer.ZIndex = 5

        local state = false
        local function setToggle(val)
            state = val
            local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
            if state then
                TweenService:Create(ToggleFrame, tweenInfo, {BackgroundColor3 = Color3.fromRGB(80, 200, 100)}):Play()
                TweenService:Create(Ball, tweenInfo, {Position = UDim2.new(0, 25, 0.5, -9), BackgroundColor3 = Color3.new(1,1,1)}):Play()
            else
                TweenService:Create(ToggleFrame, tweenInfo, {BackgroundColor3 = Color3.fromRGB(60, 60, 70)}):Play()
                TweenService:Create(Ball, tweenInfo, {Position = UDim2.new(0, 3, 0.5, -9), BackgroundColor3 = Color3.fromRGB(180, 180, 180)}):Play()
            end
            onToggle(state)
        end

        -- Ativacao perfeita para Mobile e PC
        ClickLayer.Activated:Connect(function()
            setToggle(not state)
        end)

        return Row, setToggle
    end

    local function makeSep(parent, text)
        local Sep = Instance.new("TextLabel")
        Sep.Size             = UDim2.new(1, 0, 0, 18)
        Sep.BackgroundTransparency = 1
        Sep.Font             = Enum.Font.GothamBold
        Sep.TextSize         = 10
        Sep.TextColor3       = Color3.fromRGB(80, 200, 100)
        Sep.TextXAlignment   = Enum.TextXAlignment.Left
        Sep.Text             = "  " .. string.upper(text)
        Sep.Parent           = parent
    end

    makeSep(Content, "--- Jardim")
    makeToggle(Content, "Auto Harvest", function(v) toggleHarvest(v) end)
    makeToggle(Content, "Somente Mutation", function(v) _HUB.MinMutation = v end)
    makeToggle(Content, "Auto Sell", function(v) toggleSell(v) end)

    makeSep(Content, "--- PvP")
    makeToggle(Content, "Auto Steal", function(v) toggleSteal(v) end)

    makeSep(Content, "--- Info")

    local StatusLbl = Instance.new("TextLabel")
    StatusLbl.Size             = UDim2.new(1, 0, 0, 30)
    StatusLbl.BackgroundTransparency = 1
    StatusLbl.Font             = Enum.Font.Gotham
    StatusLbl.TextSize         = 10
    StatusLbl.TextColor3       = Color3.fromRGB(150, 150, 160)
    StatusLbl.TextXAlignment   = Enum.TextXAlignment.Left
    StatusLbl.TextWrapped      = true
    StatusLbl.Text             = "  Aguardando..."
    StatusLbl.Parent           = Content

    task.spawn(function()
        while ScreenGui.Parent do
            pcall(function()
                local gardens  = workspace:FindFirstChild("Gardens")

                local readyCount = 0
                if gardens then
                    for _, plot in ipairs(gardens:GetChildren()) do
                        local plants = plot:FindFirstChild("Plants")
                        if plants then
                            for _, plant in ipairs(plants:GetChildren()) do
                                if plant:GetAttribute("UserId") == LP.UserId then
                                    local fruits = plant:FindFirstChild("Fruits")
                                    if fruits then
                                        for _, fruit in ipairs(fruits:GetChildren()) do
                                            if fruit:HasTag("Harvestable") then
                                                readyCount += 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                local bp = LP:FindFirstChild("Backpack")
                local fruitCount = 0
                if bp then
                    for _, item in ipairs(bp:GetChildren()) do
                        if item:GetAttribute("HarvestedFruit") then
                            fruitCount += 1
                        end
                    end
                end

                StatusLbl.Text = string.format(
                    "  Prontos: %d  |  Backpack: %d",
                    readyCount, fruitCount
                )
            end)
            task.wait(2)
        end
    end)

    -- Sistema de Minimizar
    local isMinimized = false
    MinBtn.Activated:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            Content.Visible = false
            Main.Size = UDim2.new(0, 280, 0, 36)
            MinBtn.Text = "+"
        else
            Content.Visible = true
            Main.Size = UDim2.new(0, 280, 0, 360)
            MinBtn.Text = "-"
        end
    end)
end

-- ══════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════
buildUI()
print("[GAG HUB] Carregado com sucesso!")
