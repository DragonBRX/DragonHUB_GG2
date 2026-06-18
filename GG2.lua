
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local LP            = Players.LocalPlayer
local Mouse         = LP:GetMouse()

-- ══════════════════════════════════════════════
-- ESTADO GLOBAL
-- ══════════════════════════════════════════════
local _HUB = {
    AutoHarvest    = false,
    AutoSell       = false,
    AutoBuy        = false,
    AutoSteal      = false,
    AutoPet        = false,
    StealOwn       = false, -- roubar só do próprio jardim
    MinMutation    = false, -- só colher com mutation
    Connections    = {},
}

-- ══════════════════════════════════════════════
-- UTILITÁRIOS
-- ══════════════════════════════════════════════
local function fireButton(parent, name)
    pcall(function()
        local gui = LP.PlayerGui
        local function findBtn(root)
            for _, v in ipairs(root:GetDescendants()) do
                if v.Name == name then
                    firesignal(v.MouseButton1Click)
                    return true
                end
            end
        end
        findBtn(gui)
    end)
end

local function fireProximity(prompt)
    pcall(function()
        firetouchinterest(LP.Character.HumanoidRootPart, prompt.Parent, 0)
        fireproximityprompt(prompt)
        firetouchinterest(LP.Character.HumanoidRootPart, prompt.Parent, 1)
    end)
end

local function getChar()
    return LP.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ══════════════════════════════════════════════
-- HARVEST - colher frutas prontas
-- ══════════════════════════════════════════════
local function getHarvestableByUserId(userId)
    -- colhe do jardim do userId especificado (nil = todos)
    local results = {}
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end

    for _, plot in ipairs(gardens:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if not plants then continue end
        for _, plant in ipairs(plants:GetChildren()) do
            -- filtro por userId se especificado
            local plantUserId = plant:GetAttribute("UserId")
            if userId and tostring(plantUserId) ~= tostring(userId) then continue end

            -- checa se tem Harvestable (fruto pronto)
            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    if fruit:HasTag("Harvestable") then
                        -- pula se só quer mutation e não tem
                        if _HUB.MinMutation and not fruit:GetAttribute("Mutation") then continue end
                        local harvestPart = fruit:FindFirstChild("HarvestPart")
                        if harvestPart then
                            local prompt = harvestPart:FindFirstChild("HarvestPrompt")
                            if prompt then
                                table.insert(results, {fruit = fruit, prompt = prompt})
                            end
                        end
                    end
                end
            end

            -- algumas plantas têm HarvestPart direto (sem Fruits folder)
            local hp = plant:FindFirstChild("HarvestPart")
            if hp then
                local prompt = hp:FindFirstChild("HarvestPrompt")
                if prompt then
                    table.insert(results, {fruit = plant, prompt = prompt})
                end
            end
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
                fireProximity(t.prompt)
                task.wait(0.05)
            end
        end)
        task.wait(1)
    end
end

-- ══════════════════════════════════════════════
-- STEAL - roubar frutas de outros
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
            -- não roubar do próprio jardim
            if tostring(plantUserId) == myId then continue end

            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    local harvestPart = fruit:FindFirstChild("HarvestPart")
                    if harvestPart then
                        local prompt = harvestPart:FindFirstChild("StealPrompt")
                        if prompt and prompt.Enabled then
                            table.insert(results, {fruit = fruit, prompt = prompt})
                        end
                    end
                end
            end

            -- plantas sem Fruits folder
            local hp = plant:FindFirstChild("HarvestPart")
            if hp then
                local prompt = hp:FindFirstChild("StealPrompt")
                if prompt and prompt.Enabled then
                    table.insert(results, {fruit = plant, prompt = prompt})
                end
            end
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
                fireProximity(t.prompt)
                task.wait(0.1)
            end
        end)
        task.wait(1.5)
    end
end

-- ══════════════════════════════════════════════
-- SELL - vender tudo no backpack
-- ══════════════════════════════════════════════
local function doSell()
    pcall(function()
        -- clica no botão SellButton da UI TeleportButtons
        for _, gui in ipairs(LP.PlayerGui:GetChildren()) do
            local tb = gui:FindFirstChild("TeleportButtons")
            if tb then
                local btn = tb:FindFirstChild("SellButton")
                if btn then firesignal(btn.MouseButton1Click) end
            end
        end
    end)
end

local function doAutoSell()
    while _HUB.AutoSell do
        pcall(function()
            -- verifica se tem frutas no backpack
            local bp = LP:FindFirstChild("Backpack")
            if not bp then return end
            local hasFruit = false
            for _, item in ipairs(bp:GetChildren()) do
                if item:GetAttribute("HarvestedFruit") then
                    hasFruit = true
                    break
                end
            end
            -- também checa o personagem (item equipado)
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
-- PET - capturar WildPets
-- ══════════════════════════════════════════════
local function getWildPets()
    local results = {}
    local wildPetRef = workspace:FindFirstChild("Map") and
                       workspace.Map:FindFirstChild("WildPetRef")
    if not wildPetRef then return results end

    for _, pet in ipairs(wildPetRef:GetChildren()) do
        local ownerId = pet:GetAttribute("OwnerUserId")
        if ownerId == 0 or ownerId == nil then
            -- pet livre para capturar
            local prompt = pet:FindFirstChild("ProximityPrompt") or
                           pet.Parent:FindFirstChild("ProximityPrompt")
            table.insert(results, {
                part     = pet,
                name     = pet:GetAttribute("PetName"),
                rarity   = pet:GetAttribute("Rarity"),
                price    = pet:GetAttribute("Price"),
                prompt   = prompt,
            })
        end
    end
    return results
end

local function doAutoPet()
    while _HUB.AutoPet do
        pcall(function()
            local pets = getWildPets()
            for _, p in ipairs(pets) do
                if not _HUB.AutoPet then break end
                if p.prompt then
                    fireProximity(p.prompt)
                    task.wait(0.1)
                else
                    -- tenta firear ProximityPrompt na região do pet
                    for _, desc in ipairs(p.part:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            fireProximity(desc)
                            break
                        end
                    end
                end
            end
        end)
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

local function togglePet(state)
    _HUB.AutoPet = state
    if state then task.spawn(doAutoPet) end
end

-- ══════════════════════════════════════════════
-- INTERFACE (estilo DragonHUB)
-- ══════════════════════════════════════════════
local function buildUI()
    -- Remove UI anterior se existir
    local old = LP.PlayerGui:FindFirstChild("GAG_HUB")
    if old then old:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name            = "GAG_HUB"
    ScreenGui.ResetOnSpawn    = false
    ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent          = LP.PlayerGui

    -- Janela principal
    local Main = Instance.new("Frame")
    Main.Name                = "Main"
    Main.Size                = UDim2.new(0, 280, 0, 360)
    Main.Position            = UDim2.new(0, 20, 0.5, -180)
    Main.BackgroundColor3    = Color3.fromRGB(15, 15, 20)
    Main.BorderSizePixel     = 0
    Main.Parent              = ScreenGui

    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)

    -- Borda colorida (verde jardim)
    local Stroke = Instance.new("UIStroke", Main)
    Stroke.Color     = Color3.fromRGB(80, 200, 100)
    Stroke.Thickness = 1.5

    -- Header
    local Header = Instance.new("Frame")
    Header.Name              = "Header"
    Header.Size              = UDim2.new(1, 0, 0, 36)
    Header.BackgroundColor3  = Color3.fromRGB(20, 20, 28)
    Header.BorderSizePixel   = 0
    Header.Parent            = Main

    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 8)

    local Title = Instance.new("TextLabel")
    Title.Size               = UDim2.new(1, -40, 1, 0)
    Title.Position           = UDim2.new(0, 12, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Font               = Enum.Font.GothamBold
    Title.TextSize           = 13
    Title.TextColor3         = Color3.fromRGB(80, 220, 110)
    Title.TextXAlignment     = Enum.TextXAlignment.Left
    Title.Text               = "🌱  GROW A GARDEN HUB"
    Title.Parent             = Header

    -- Botão fechar
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size             = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position         = UDim2.new(1, -32, 0, 4)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseBtn.Font             = Enum.Font.GothamBold
    CloseBtn.TextSize         = 12
    CloseBtn.TextColor3       = Color3.new(1, 1, 1)
    CloseBtn.Text             = "✕"
    CloseBtn.BorderSizePixel  = 0
    CloseBtn.Parent           = Header
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
    CloseBtn.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
        toggleHarvest(false)
        toggleSell(false)
        toggleSteal(false)
        togglePet(false)
    end)

    -- Drag
    local dragging, dragInput, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = input.Position
            startPos  = Main.Position
        end
    end)
    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Container de botões
    local Content = Instance.new("Frame")
    Content.Name              = "Content"
    Content.Size              = UDim2.new(1, -16, 1, -48)
    Content.Position          = UDim2.new(0, 8, 0, 44)
    Content.BackgroundTransparency = 1
    Content.Parent            = Main

    local Layout = Instance.new("UIListLayout", Content)
    Layout.SortOrder    = Enum.SortOrder.LayoutOrder
    Layout.Padding      = UDim.new(0, 6)

    -- Função de criação de toggle
    local function makeToggle(parent, label, icon, onToggle)
        local Row = Instance.new("Frame")
        Row.Size             = UDim2.new(1, 0, 0, 38)
        Row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        Row.BorderSizePixel  = 0
        Row.Parent           = parent
        Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 6)

        local Lbl = Instance.new("TextLabel")
        Lbl.Size             = UDim2.new(1, -60, 1, 0)
        Lbl.Position         = UDim2.new(0, 10, 0, 0)
        Lbl.BackgroundTransparency = 1
        Lbl.Font             = Enum.Font.Gotham
        Lbl.TextSize         = 12
        Lbl.TextColor3       = Color3.fromRGB(220, 220, 220)
        Lbl.TextXAlignment   = Enum.TextXAlignment.Left
        Lbl.Text             = icon .. "  " .. label
        Lbl.Parent           = Row

        local ToggleFrame = Instance.new("Frame")
        ToggleFrame.Size             = UDim2.new(0, 42, 0, 22)
        ToggleFrame.Position         = UDim2.new(1, -50, 0.5, -11)
        ToggleFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        ToggleFrame.BorderSizePixel  = 0
        ToggleFrame.Parent           = Row
        Instance.new("UICorner", ToggleFrame).CornerRadius = UDim.new(1, 0)

        local Ball = Instance.new("Frame")
        Ball.Size             = UDim2.new(0, 16, 0, 16)
        Ball.Position         = UDim2.new(0, 3, 0.5, -8)
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
                TweenService:Create(Ball, tweenInfo, {Position = UDim2.new(0, 23, 0.5, -8), BackgroundColor3 = Color3.new(1,1,1)}):Play()
            else
                TweenService:Create(ToggleFrame, tweenInfo, {BackgroundColor3 = Color3.fromRGB(60, 60, 70)}):Play()
                TweenService:Create(Ball, tweenInfo, {Position = UDim2.new(0, 3, 0.5, -8), BackgroundColor3 = Color3.fromRGB(180, 180, 180)}):Play()
            end
            onToggle(state)
        end

        ToggleFrame.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                setToggle(not state)
            end
        end)
        Row.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                setToggle(not state)
            end
        end)

        return Row, setToggle
    end

    -- Separator label
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

    makeSep(Content, "─── Jardim")
    makeToggle(Content, "Auto Harvest", "🌾", function(v) toggleHarvest(v) end)
    makeToggle(Content, "Só com Mutation", "✨", function(v) _HUB.MinMutation = v end)
    makeToggle(Content, "Auto Sell", "💰", function(v) toggleSell(v) end)

    makeSep(Content, "─── PvP")
    makeToggle(Content, "Auto Steal", "🥷", function(v) toggleSteal(v) end)

    makeSep(Content, "─── Pets")
    makeToggle(Content, "Auto Capturar Pet", "🐾", function(v) togglePet(v) end)

    makeSep(Content, "─── Info")

    -- Status label
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

    -- Atualiza status a cada 2s
    task.spawn(function()
        while ScreenGui.Parent do
            pcall(function()
                local gardens  = workspace:FindFirstChild("Gardens")
                local wildPets = workspace:FindFirstChild("Map") and
                                 workspace.Map:FindFirstChild("WildPetRef")

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

                local petCount = 0
                if wildPets then
                    for _, pet in ipairs(wildPets:GetChildren()) do
                        if (pet:GetAttribute("OwnerUserId") or 0) == 0 then
                            petCount += 1
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
                    "  🌾 Prontos: %d  |  🎒 Backpack: %d  |  🐾 Pets: %d",
                    readyCount, fruitCount, petCount
                )
            end)
            task.wait(2)
        end
    end)

    -- Footer
    local Footer = Instance.new("TextLabel")
    Footer.Size             = UDim2.new(1, 0, 0, 16)
    Footer.Position         = UDim2.new(0, 0, 1, -18)
    Footer.BackgroundTransparency = 1
    Footer.Font             = Enum.Font.Gotham
    Footer.TextSize         = 9
    Footer.TextColor3       = Color3.fromRGB(60, 60, 80)
    Footer.Text             = "GAG HUB  |  Shift Dir = ocultar"
    Footer.Parent           = Main

    -- Shift para ocultar/mostrar
    game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            Content.Visible = not Content.Visible
            Main.Size = Content.Visible
                and UDim2.new(0, 280, 0, 360)
                or  UDim2.new(0, 280, 0, 38)
        end
    end)
end

-- ══════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════
buildUI()
print("[GAG HUB] Carregado com sucesso!")
