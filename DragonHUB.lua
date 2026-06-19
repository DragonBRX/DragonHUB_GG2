local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace     = game:GetService("Workspace")
local LP            = Players.LocalPlayer

-- ══════════════════════════════════════════════
-- CARREGAMENTO SEGURO DE MÓDULOS
-- ══════════════════════════════════════════════
local Networking, FruitValueCalc

pcall(function()
    Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
end)

pcall(function()
    FruitValueCalc = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitValueCalc"))
end)

if not Networking then
    warn("[GAG HUB] ERRO CRITICAL: Networking não encontrado. O script não vai funcionar.")
end

-- ══════════════════════════════════════════════
-- ESTADO GLOBAL
-- ══════════════════════════════════════════════
local _HUB = {
    AutoHarvest      = false,
    AutoSell         = false,
    AutoSteal        = false,
    MinMutation      = false,
    StealByDistance  = false,
    UseTeleportSteal = true,
}

-- ══════════════════════════════════════════════
-- FUNÇÕES AUXILIARES
-- ══════════════════════════════════════════════
local Plots = Workspace:WaitForChild("Gardens")

local function getRoot(player)
    if not player or not player.Character then return nil end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.RootPart or nil
end

local function getMyPlot()
    for _, plot in ipairs(Plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == LP.UserId then
            return plot
        end
    end
    return nil
end

local function isNightTime()
    local night = ReplicatedStorage:FindFirstChild("Night")
    return night ~= nil and night.Value == true
end

-- ══════════════════════════════════════════════
-- HARVEST
-- ══════════════════════════════════════════════
local function isGrown(plant)
    local maxAge = plant:GetAttribute("MaxAge")
    local currentAge = plant:GetAttribute("Age")
    if maxAge == nil or currentAge == nil then return false end
    return currentAge >= maxAge
end

local function doAutoHarvest()
    while _HUB.AutoHarvest do
        pcall(function()
            local myPlot = getMyPlot()
            if not myPlot then return end
            
            local plantsFolder = myPlot:FindFirstChild("Plants")
            if not plantsFolder then return end

            for _, plant in ipairs(plantsFolder:GetChildren()) do
                if not _HUB.AutoHarvest then break end
                
                local fruitsFolder = plant:FindFirstChild("Fruits")
                local targets = fruitsFolder and fruitsFolder:GetChildren() or {plant}

                for _, fruit in ipairs(targets) do
                    if fruit:IsA("Model") and isGrown(fruit) then
                        if _HUB.MinMutation and not fruit:GetAttribute("Mutation") then continue end

                        local id = fruit:GetAttribute("PlantId")
                        local fruitid = fruit:GetAttribute("FruitId") or ""
                        
                        if id and Networking and Networking.Garden then
                            Networking.Garden.CollectFruit:Fire(id, fruitid)
                        end
                        task.wait(0.05)
                    end
                end
            end
        end)
        task.wait(1)
    end
end

-- ══════════════════════════════════════════════
-- STEAL
-- ══════════════════════════════════════════════
local function calculateFruitValue(fruit)
    if not FruitValueCalc then return 0 end
    local ok, value = pcall(function()
        local fruitName = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("PlantName")
        local sizeMulti = fruit:GetAttribute("SizeMulti") or fruit:GetAttribute("Age") or 1
        local mutation = fruit:GetAttribute("Mutation")
        return FruitValueCalc(fruitName, sizeMulti, mutation, LP, 1)
    end)
    return ok and (value or 0) or 0
end

local function getStealTarget()
    local bestItem = nil
    local bestValue = 0
    local myPos = getRoot(LP) and getRoot(LP).Position

    for _, plot in ipairs(Plots:GetChildren()) do
        local ownerUserId = plot:GetAttribute("OwnerUserId")
        local owner = Players:GetPlayerByUserId(ownerUserId or 0)
        
        if ownerUserId and ownerUserId ~= LP.UserId then
            if owner and owner.Character then
                local hum = owner.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Sit then continue end 
            end

            local plants = plot:FindFirstChild("Plants")
            if not plants then continue end

            for _, plant in ipairs(plants:GetChildren()) do
                local fruits = plant:FindFirstChild("Fruits")
                local checkFruits = fruits and fruits:GetChildren() or {plant}

                for _, fruit in ipairs(checkFruits) do
                    local harvestPart = fruit:FindFirstChild("HarvestPart")
                    local stealPrompt = harvestPart and harvestPart:FindFirstChild("StealPrompt")
                    
                    if stealPrompt then
                        local val = calculateFruitValue(fruit)
                        local dist = myPos and (harvestPart.Position - myPos).Magnitude or 9999

                        if _HUB.StealByDistance then
                            if dist < (bestValue == 0 and 9999 or bestValue) then
                                bestValue = dist
                                bestItem = fruit
                            end
                        else
                            if val > bestValue then
                                bestValue = val
                                bestItem = fruit
                            end
                        end
                    end
                end
            end
        end
    end
    return bestItem
end

local function returnToPlot()
    local myPlot = getMyPlot()
    if not myPlot then return end
    local ref = myPlot:FindFirstChild("PlotSizeReference")
    local root = getRoot(LP)
    
    if ref and root then
        for i = 1, 3 do
            pcall(function()
                root.CFrame = ref.CFrame
            end)
            task.wait(0.05)
        end
    end
end

local function stealFruit(target)
    if not target then return false end
    local harvestPart = target:FindFirstChild("HarvestPart")
    if not harvestPart then return false end

    local userId = tonumber(target:GetAttribute("UserId"))
    local plantId = target:GetAttribute("PlantId")
    local fruitId = target:GetAttribute("FruitId") or ""

    local root = getRoot(LP)
    if not root then return false end

    for i = 1, 2 do
        root.CFrame = harvestPart.CFrame
        if Networking and Networking.Steal then
            pcall(function()
                Networking.Steal.BeginSteal:Fire(userId, plantId, fruitId)
                task.wait(0.05)
                Networking.Steal.CompleteSteal:Fire()
            end)
        end
        task.wait(0.05)
    end
    
    return true
end

local function doAutoSteal()
    while _HUB.AutoSteal do
        pcall(function()
            if not isNightTime() then return end

            local target = getStealTarget()
            if target then
                stealFruit(target)
                task.wait(0.2)
                returnToPlot()
            end
        end)
        task.wait(0.5)
    end
end

-- ══════════════════════════════════════════════
-- SELL (ATUALIZADO - SEM EQUIPAR TOOL)
-- ══════════════════════════════════════════════

-- Função que tenta vender via Remote direto (de longe)
local function fireSellRemotes()
    if not Networking then return false end
    local sold = false
    for _, moduleData in pairs(Networking) do
        if type(moduleData) == "table" then
            for eventName, eventObj in pairs(moduleData) do
                local lowerName = string.lower(tostring(eventName))
                if lowerName:find("sell") then
                    pcall(function()
                        if type(eventObj) == "table" and type(eventObj.Fire) == "function" then
                            eventObj:Fire() 
                            sold = true
                        elseif typeof(eventObj) == "Instance" and eventObj:IsA("RemoteEvent") then
                            eventObj:FireServer()
                            sold = true
                        elseif typeof(eventObj) == "Instance" and eventObj:IsA("RemoteFunction") then
                            eventObj:InvokeServer()
                            sold = true
                        end
                    end)
                end
            end
        end
    end
    return sold
end

local function doAutoSell()
    while _HUB.AutoSell do
        pcall(function()
            local bp = LP:FindFirstChild("Backpack")
            local char = LP.Character
            local hasFruit = false
            
            -- Mapeia os IDs das frutas que estão no inventário sem precisar equipar
            local fruitIdsToSell = {}
            if bp then
                for _, item in ipairs(bp:GetChildren()) do
                    if item:IsA("Tool") then 
                        hasFruit = true
                        local pid = item:GetAttribute("PlantId")
                        local fid = item:GetAttribute("FruitId") or ""
                        if pid then
                            table.insert(fruitIdsToSell, {PlantId = pid, FruitId = fid})
                        end
                    end
                end
            end
            
            if char then
                for _, item in ipairs(char:GetChildren()) do
                    if item:IsA("Tool") then 
                        hasFruit = true
                        local pid = item:GetAttribute("PlantId")
                        local fid = item:GetAttribute("FruitId") or ""
                        if pid then
                            table.insert(fruitIdsToSell, {PlantId = pid, FruitId = fid})
                        end
                    end
                end
            end
            
            if hasFruit then 
                -- PLANO A: Tentar vender os IDs de longe via Networking
                local soldRemotely = false
                if Networking and Networking.Garden and #fruitIdsToSell > 0 then
                    for _, fruitData in ipairs(fruitIdsToSell) do
                        pcall(function()
                            -- Tenta disparar o remoto de coleta/venda de longe com os dados da Tool
                            if Networking.Garden.CollectFruit then
                                Networking.Garden.CollectFruit:Fire(fruitData.PlantId, fruitData.FruitId)
                                soldRemotely = true
                            end
                        end)
                        task.wait(0.05)
                    end
                end

                -- Tenta os Remotes Genéricos (Busca automaticamente o Sell)
                if not soldRemotely then
                    soldRemotely = fireSellRemotes()
                end
                
                -- PLANO B: Se o server exigir presença física, teleporta para o NPC Steven (ou SellArea)
                if not soldRemotely then
                    local sellArea = nil
                    pcall(function()
                        if Workspace.NPCS:FindFirstChild("Steven") then
                            sellArea = Workspace.NPCS.Steven:FindFirstChild("SellArea") 
                                    or Workspace.NPCS.Steven:FindFirstChild("HumanoidRootPart")
                        end
                    end)
                    
                    if not sellArea then
                        sellArea = Workspace:FindFirstChild("SellArea") or Workspace:FindFirstChild("Sell")
                    end
                    
                    if sellArea and sellArea:IsA("BasePart") then
                        local root = getRoot(LP)
                        if root then
                            root.CFrame = sellArea.CFrame + Vector3.new(0, 3, 0)
                        end
                    end
                end
            end
        end)
        task.wait(1) 
    end
end

-- ══════════════════════════════════════════════
-- TOGGLES
-- ══════════════════════════════════════════════
local function toggleHarvest(state) _HUB.AutoHarvest = state if state then task.spawn(doAutoHarvest) end end
local function toggleSell(state) _HUB.AutoSell = state if state then task.spawn(doAutoSell) end end
local function toggleSteal(state) _HUB.AutoSteal = state if state then task.spawn(doAutoSteal) end end

-- ══════════════════════════════════════════════
-- INTERFACE (UI)
-- ══════════════════════════════════════════════
local function buildUI()
    local old = LP.PlayerGui:FindFirstChild("GAG_HUB")
    if old then old:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "GAG_HUB"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = LP.PlayerGui

    local Main = Instance.new("Frame")
    Main.Size = UDim2.new(0, 280, 0, 360)
    Main.Position = UDim2.new(0, 20, 0.5, -180)
    Main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    Main.BorderSizePixel = 0
    Main.Parent = ScreenGui
    Main.Active = true
    Main.Draggable = true

    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)
    local Stroke = Instance.new("UIStroke", Main)
    Stroke.Color = Color3.fromRGB(80, 200, 100)
    Stroke.Thickness = 1.5

    local Header = Instance.new("Frame")
    Header.Size = UDim2.new(1, 0, 0, 36)
    Header.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    Header.BorderSizePixel = 0
    Header.Parent = Main
    Header.Active = true
    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 8)

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -80, 1, 0)
    Title.Position = UDim2.new(0, 12, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 13
    Title.TextColor3 = Color3.fromRGB(80, 220, 110)
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Text = "DragonHUB - GAG (FIXED)"
    Title.Parent = Header

    local MinBtn = Instance.new("TextButton")
    MinBtn.Size = UDim2.new(0, 28, 0, 28)
    MinBtn.Position = UDim2.new(1, -64, 0, 4)
    MinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    MinBtn.Font = Enum.Font.GothamBold
    MinBtn.TextSize = 16
    MinBtn.TextColor3 = Color3.new(1, 1, 1)
    MinBtn.Text = "-"
    MinBtn.BorderSizePixel = 0
    MinBtn.Parent = Header
    Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position = UDim2.new(1, -32, 0, 4)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 13
    CloseBtn.TextColor3 = Color3.new(1, 1, 1)
    CloseBtn.Text = "X"
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Parent = Header
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

    CloseBtn.Activated:Connect(function()
        ScreenGui:Destroy()
        toggleHarvest(false)
        toggleSell(false)
        toggleSteal(false)
    end)

    local Content = Instance.new("Frame")
    Content.Size = UDim2.new(1, -16, 1, -48)
    Content.Position = UDim2.new(0, 8, 0, 44)
    Content.BackgroundTransparency = 1
    Content.Parent = Main

    local Layout = Instance.new("UIListLayout", Content)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Padding = UDim.new(0, 6)

    local function makeToggle(parent, label, onToggle)
        local Row = Instance.new("TextButton")
        Row.Size = UDim2.new(1, 0, 0, 40)
        Row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        Row.BorderSizePixel = 0
        Row.Text = ""
        Row.Parent = parent
        Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 6)

        local Lbl = Instance.new("TextLabel")
        Lbl.Size = UDim2.new(1, -60, 1, 0)
        Lbl.Position = UDim2.new(0, 10, 0, 0)
        Lbl.BackgroundTransparency = 1
        Lbl.Font = Enum.Font.Gotham
        Lbl.TextSize = 14
        Lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        Lbl.TextXAlignment = Enum.TextXAlignment.Left
        Lbl.Text = label
        Lbl.Parent = Row

        local ToggleFrame = Instance.new("Frame")
        ToggleFrame.Size = UDim2.new(0, 46, 0, 24)
        ToggleFrame.Position = UDim2.new(1, -54, 0.5, -12)
        ToggleFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        ToggleFrame.BorderSizePixel = 0
        ToggleFrame.Parent = Row
        Instance.new("UICorner", ToggleFrame).CornerRadius = UDim.new(1, 0)

        local Ball = Instance.new("Frame")
        Ball.Size = UDim2.new(0, 18, 0, 18)
        Ball.Position = UDim2.new(0, 3, 0.5, -9)
        Ball.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
        Ball.BorderSizePixel = 0
        Ball.Parent = ToggleFrame
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

        Row.Activated:Connect(function() setToggle(not state) end)
        return Row, setToggle
    end

    local function makeSep(parent, text)
        local Sep = Instance.new("TextLabel")
        Sep.Size = UDim2.new(1, 0, 0, 18)
        Sep.BackgroundTransparency = 1
        Sep.Font = Enum.Font.GothamBold
        Sep.TextSize = 10
        Sep.TextColor3 = Color3.fromRGB(80, 200, 100)
        Sep.TextXAlignment = Enum.TextXAlignment.Left
        Sep.Text = "  " .. string.upper(text)
        Sep.Parent = parent
    end

    makeSep(Content, "--- Jardim")
    makeToggle(Content, "Auto Harvest", function(v) toggleHarvest(v) end)
    makeToggle(Content, "Somente Mutation", function(v) _HUB.MinMutation = v end)
    makeToggle(Content, "Auto Sell", function(v) toggleSell(v) end)

    makeSep(Content, "--- PvP")
    makeToggle(Content, "Auto Steal", function(v) toggleSteal(v) end)
    makeToggle(Content, "Priorizar Mais Proximo", function(v) _HUB.StealByDistance = v end)

    local StatusLbl = Instance.new("TextLabel")
    StatusLbl.Size = UDim2.new(1, 0, 0, 30)
    StatusLbl.BackgroundTransparency = 1
    StatusLbl.Font = Enum.Font.Gotham
    StatusLbl.TextSize = 10
    StatusLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
    StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
    StatusLbl.TextWrapped = true
    StatusLbl.Text = "  Aguardando..."
    StatusLbl.Parent = Content

    task.spawn(function()
        while ScreenGui.Parent do
            pcall(function()
                StatusLbl.Text = string.format("  Status: %s", isNightTime() and "Noite (Steal ON)" or "Dia (Steal OFF)")
            end)
            task.wait(2)
        end
    end)

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

-- INIT
buildUI()
print("[GAG HUB] Script atualizado! Auto Sell refinado (Sem precisar segurar Tools).")
