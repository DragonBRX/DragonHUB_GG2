local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP            = Players.LocalPlayer

-- Módulos do jogo (necessários pro Steal real)
local Networking     = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
local FruitValueCalc = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitValueCalc"))

-- ══════════════════════════════════════════════
-- ESTADO GLOBAL
-- ══════════════════════════════════════════════
local _HUB = {
    AutoHarvest      = false,
    AutoSell         = false,
    AutoSteal        = false,
    StealOwn         = false,
    MinMutation      = false,
    StealByDistance  = false, -- false = prioriza valor (padrão), true = prioriza o mais próximo
    UseTeleportSteal = false, -- false = anda de verdade (mais seguro, mais lento), true = teleporte (rápido, mais arriscado)
}

local function getChar()
    return LP.Character
end

local function getRoot(player)
    local char = player and player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    return hum and hum.RootPart
end

local function getMyPlot()
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    for _, plot in ipairs(gardens:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == LP.UserId then
            return plot
        end
    end
end

local function isNightTime()
    local night = ReplicatedStorage:FindFirstChild("Night")
    return night ~= nil and night.Value == true
end

local function isPlotUnlocked(player)
    -- checa se o dono do plot está bloqueando fisicamente a área (anti-steal do próprio jogo)
    if not player then return true end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return true end

    local plot
    for _, p in ipairs(gardens:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == player.UserId then
            plot = p
            break
        end
    end
    if not plot then return true end

    local visual = plot:FindFirstChild("Visual")
    local area   = visual and visual:FindFirstChild("PlotSizeReferenceVisual")
    if not area then return true end

    local char = player.Character
    if not char then return true end

    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInBox(area.CFrame, area.Size)
    end)
    if not ok or not parts then return true end

    for _, touching in ipairs(parts) do
        if touching:IsDescendantOf(char) then
            return false -- bloqueado
        end
    end
    return true
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
-- STEAL (remote real: Networking.Steal.BeginSteal/CompleteSteal)
-- ══════════════════════════════════════════════
local function calculateFruitValue(fruit)
    local ok, value = pcall(function()
        local fruitName      = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("PlantName")
        local sizeMultiplier = fruit:GetAttribute("SizeMulti") or fruit:GetAttribute("Age")
        local mutation       = fruit:GetAttribute("Mutation")
        return FruitValueCalc(fruitName, sizeMultiplier, mutation, LP, 1)
    end)
    return ok and value or 0
end

-- pega todos os alvos roubáveis, ordenados por valor (padrão) ou distância (opcional)
local function getStealTargetsSorted()
    local results = {}
    local myId    = LP.UserId
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end

    local myRoot = getRoot(LP)
    local myPos  = myRoot and myRoot.Position

    for _, plot in ipairs(gardens:GetChildren()) do
        local ownerUserId = plot:GetAttribute("OwnerUserId")
        if not ownerUserId or ownerUserId == myId then continue end

        local owner = Players:GetPlayerByUserId(ownerUserId)
        -- pula se o dono não estiver mais no server (plot pode estar com lixo residual)
        local plants = plot:FindFirstChild("Plants")
        if not plants then continue end

        local function checkFruit(fruitObj)
            local harvestPart = fruitObj:FindFirstChild("HarvestPart")
            local stealPrompt = harvestPart and harvestPart:FindFirstChild("StealPrompt")
            if not stealPrompt then return end

            local value    = calculateFruitValue(fruitObj)
            local distance = myPos and (harvestPart.Position - myPos).Magnitude or 0

            table.insert(results, {
                fruit       = fruitObj,
                harvestPart = harvestPart,
                value       = value,
                distance    = distance,
                userId      = ownerUserId,
                owner       = owner,
            })
        end

        for _, plant in ipairs(plants:GetChildren()) do
            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    checkFruit(fruit)
                end
            else
                checkFruit(plant)
            end
        end
    end

    if _HUB.StealByDistance then
        table.sort(results, function(a, b) return a.distance < b.distance end)
    else
        table.sort(results, function(a, b) return a.value > b.value end)
    end
    return results
end

-- move o personagem de verdade até uma posição (sem CFrame/teleporte)
-- retorna true se chegou, false se timeout ou personagem sumiu
local function walkTo(position, timeout)
    timeout = timeout or 8
    local char = getChar()
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return false end

    hum:MoveTo(position)

    local start = tick()
    local reached = false
    local conn

    conn = hum.MoveToFinished:Connect(function(success)
        reached = true
    end)

    while tick() - start < timeout do
        if reached then break end
        if not _HUB.AutoSteal then break end
        -- recalcula distância pra considerar "chegou" mesmo sem o evento disparar
        local curRoot = char and char:FindFirstChild("HumanoidRootPart")
        if curRoot and (curRoot.Position - position).Magnitude < 4 then
            break
        end
        task.wait(0.1)
    end

    if conn then conn:Disconnect() end
    return true
end

-- teleporta direto via CFrame (rápido, mais arriscado/instável)
local function teleportTo(position)
    local root = getRoot(LP)
    if not root then return false end
    root.CFrame = CFrame.new(position)
    task.wait(0.05) -- pequeno respiro pro servidor processar a posição
    return true
end

-- escolhe entre andar ou teleportar de acordo com a opção do menu
local function goTo(position, timeout)
    if _HUB.UseTeleportSteal then
        return teleportTo(position)
    end
    return walkTo(position, timeout)
end

local function stealFruit(target)
    local fruit       = target.fruit
    local harvestPart = target.harvestPart
    if not harvestPart then return false end

    local userId  = tonumber(fruit:GetAttribute("UserId")) or target.userId
    local plantId = fruit:GetAttribute("PlantId")
    local fruitId = fruit:GetAttribute("FruitId") or ""

    -- se o dono estiver bloqueando fisicamente a área, pula esse alvo
    if target.owner and not isPlotUnlocked(target.owner) then
        return false
    end

    -- vai até a fruta (andando ou teleportando, conforme a opção escolhida)
    local arrived = goTo(harvestPart.Position, 6)
    if not arrived or not _HUB.AutoSteal then return false end

    -- checa se ainda existe e ainda é roubável (pode ter sido pego por outro jogador)
    if not harvestPart.Parent or not harvestPart:FindFirstChild("StealPrompt") then
        return false
    end

    Networking.Steal.BeginSteal:Fire(userId, plantId, fruitId)
    task.wait(0.1)
    Networking.Steal.CompleteSteal:Fire()
    return true
end

-- volta pro próprio jardim pra fruta roubada contar (andando ou teleportando)
local function returnToPlot()
    pcall(function()
        local myPlot = getMyPlot()
        local ref    = myPlot and myPlot:FindFirstChild("PlotSizeReference")
        if ref then
            goTo(ref.Position, 10)
        end
    end)
end

local function doAutoSteal()
    while _HUB.AutoSteal do
        pcall(function()
            if not isNightTime() then
                return -- só funciona de noite, igual a mecânica do jogo
            end

            local targets = getStealTargetsSorted()
            if #targets == 0 then return end

            -- rouba UM fruto por vez e corre de volta antes de tentar o próximo,
            -- porque ficar carregando vários ao mesmo tempo aumenta a chance de
            -- alguém te acertar e perder tudo no caminho
            local best = targets[1]
            local ok = stealFruit(best)
            if ok then
                returnToPlot()
            end
        end)
        task.wait(0.5)
    end
end

-- ══════════════════════════════════════════════
-- SELL
-- ══════════════════════════════════════════════
local function doSell()
    pcall(function()
        for _, gui in ipairs(LP.PlayerGui:GetChildren()) do
            local tb = gui:FindFirstChild("TeleportButtons")
            if tb then
                local btn = tb:FindFirstChild("SellButton")
                if btn then 
                    firesignal(btn.MouseButton1Click) 
                    firesignal(btn.Activated)
                end
            end
        end
    end)
end

local function doAutoSell()
    while _HUB.AutoSell do
        pcall(function()
            local bp = LP:FindFirstChild("Backpack")
            if not bp then return end
            local hasFruit = false
            for _, item in ipairs(bp:GetChildren()) do
                if item:GetAttribute("HarvestedFruit") then
                    hasFruit = true
                    break
                end
            end
            local char = getChar()
            if char then
                for _, item in ipairs(char:GetChildren()) do
                    if item:GetAttribute("HarvestedFruit") then
                        hasFruit = true
                        break
                    end
                end
            end
            if hasFruit then doSell() end
        end)
        task.wait(3)
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
    Title.Text               = "DragonHUB - GROW A GARDEN 2"
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

    -- Funcao de criacao de toggle (Usando TextButton para 100% de precisao no toque)
    local function makeToggle(parent, label, onToggle)
        local Row = Instance.new("TextButton")
        Row.Size             = UDim2.new(1, 0, 0, 40)
        Row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        Row.BorderSizePixel  = 0
        Row.Text             = ""
        Row.AutoButtonColor  = true
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

        -- O evento Activated e perfeito para mobile e PC, corrigindo o problema do clique
        Row.Activated:Connect(function()
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
    makeToggle(Content, "Priorizar Mais Proximo", function(v) _HUB.StealByDistance = v end)
    makeToggle(Content, "Steal por Teleporte", function(v) _HUB.UseTeleportSteal = v end)

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
                    "  Prontos: %d  |  Backpack: %d  |  %s",
                    readyCount, fruitCount, isNightTime() and "Noite (Steal ON)" or "Dia (Steal OFF)"
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
