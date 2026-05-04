--!strict
-- BUF-91: First-hit info reveal HUD — the spine mechanic.
-- The targeted player sees a panel with the full wave composition
-- (name, enemies, formations). The other two see redacted teammate
-- portraits with hero name, "IN COMBAT" badge, and sector-core HP %.
-- Composition is NEVER auto-shared — voice is the only relay.
--
-- This script only renders. Visibility filtering happens server-side in
-- WaveDirector:getVisibleStateForPlayer; the payload we receive already
-- has `composition` stripped for non-targeted players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Sectors = require(ReplicatedStorage.Data.Sectors)

local LocalPlayer = Players.LocalPlayer

local SECTOR_COLORS: { [string]: Color3 } = {}
for heroId, layout in pairs(Sectors.byHero) do
	SECTOR_COLORS[heroId] = layout.coreColor
end

local DEFAULT_ACCENT = Color3.fromRGB(200, 200, 200)
local DANGER = Color3.fromRGB(220, 60, 60)
local CARD_BG = Color3.fromRGB(28, 30, 38)
local TEXT = Color3.fromRGB(240, 240, 240)
local TEXT_DIM = Color3.fromRGB(170, 170, 180)

local stateUpdate = ReplicatedStorage:WaitForChild(Constants.REMOTES.StateUpdate) :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CombatHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

-- ─── First-hit reveal panel ──────────────────────────────────────────────
local revealPanel = Instance.new("Frame")
revealPanel.Name = "WaveReveal"
revealPanel.AnchorPoint = Vector2.new(0.5, 0)
revealPanel.Position = UDim2.new(0.5, 0, 0, 24)
revealPanel.Size = UDim2.fromOffset(420, 220)
revealPanel.BackgroundColor3 = CARD_BG
revealPanel.BackgroundTransparency = 0.05
revealPanel.BorderSizePixel = 0
revealPanel.Visible = false
revealPanel.Parent = screenGui
corner(revealPanel, 10)
padding(revealPanel, 14)

local revealStroke = Instance.new("UIStroke")
revealStroke.Color = DANGER
revealStroke.Thickness = 2
revealStroke.Parent = revealPanel

local revealHeader = Instance.new("TextLabel")
revealHeader.Name = "Header"
revealHeader.BackgroundTransparency = 1
revealHeader.Size = UDim2.new(1, 0, 0, 18)
revealHeader.Font = Enum.Font.GothamBold
revealHeader.TextSize = 13
revealHeader.TextXAlignment = Enum.TextXAlignment.Left
revealHeader.TextColor3 = DANGER
revealHeader.Text = "▲ WAVE INCOMING"
revealHeader.Parent = revealPanel

local waveNameLabel = Instance.new("TextLabel")
waveNameLabel.Name = "WaveName"
waveNameLabel.BackgroundTransparency = 1
waveNameLabel.Position = UDim2.new(0, 0, 0, 22)
waveNameLabel.Size = UDim2.new(1, 0, 0, 32)
waveNameLabel.Font = Enum.Font.GothamBold
waveNameLabel.TextSize = 24
waveNameLabel.TextXAlignment = Enum.TextXAlignment.Left
waveNameLabel.TextColor3 = TEXT
waveNameLabel.Text = ""
waveNameLabel.Parent = revealPanel

local enemyList = Instance.new("Frame")
enemyList.Name = "EnemyList"
enemyList.BackgroundTransparency = 1
enemyList.Position = UDim2.new(0, 0, 0, 64)
enemyList.Size = UDim2.new(1, 0, 1, -64)
enemyList.Parent = revealPanel

local enemyListLayout = Instance.new("UIListLayout")
enemyListLayout.SortOrder = Enum.SortOrder.LayoutOrder
enemyListLayout.Padding = UDim.new(0, 4)
enemyListLayout.Parent = enemyList

local function clearChildren(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderEnemyRow(comp: any, index: number)
	local row = Instance.new("Frame")
	row.Name = "Enemy_" .. tostring(index)
	row.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 26)
	row.LayoutOrder = index
	row.Parent = enemyList
	corner(row, 4)

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Size = UDim2.new(0, 50, 1, 0)
	count.Font = Enum.Font.GothamBold
	count.TextSize = 16
	count.TextColor3 = DANGER
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = "×" .. tostring(comp.count)
	count.Parent = row

	local typeLabel = Instance.new("TextLabel")
	typeLabel.Name = "Type"
	typeLabel.BackgroundTransparency = 1
	typeLabel.Position = UDim2.new(0, 60, 0, 0)
	typeLabel.Size = UDim2.new(0.5, -60, 1, 0)
	typeLabel.Font = Enum.Font.GothamMedium
	typeLabel.TextSize = 15
	typeLabel.TextColor3 = TEXT
	typeLabel.TextXAlignment = Enum.TextXAlignment.Left
	typeLabel.Text = comp.type
	typeLabel.Parent = row

	local formation = Instance.new("TextLabel")
	formation.Name = "Formation"
	formation.BackgroundTransparency = 1
	formation.Position = UDim2.new(0.5, 0, 0, 0)
	formation.Size = UDim2.new(0.5, -8, 1, 0)
	formation.Font = Enum.Font.Gotham
	formation.TextSize = 13
	formation.TextColor3 = TEXT_DIM
	formation.TextXAlignment = Enum.TextXAlignment.Right
	formation.Text = comp.formation
	formation.Parent = row
end

local function renderRevealPanel(composition: any)
	if not composition then
		revealPanel.Visible = false
		clearChildren(enemyList)
		return
	end
	waveNameLabel.Text = composition.name or ""
	clearChildren(enemyList)
	for i, enemy in ipairs(composition.enemies) do
		renderEnemyRow(enemy, i)
	end
	revealPanel.Visible = true
end

-- ─── Teammate portraits ─────────────────────────────────────────────────
local teammatePanel = Instance.new("Frame")
teammatePanel.Name = "Teammates"
teammatePanel.AnchorPoint = Vector2.new(0, 0)
teammatePanel.Position = UDim2.new(0, 24, 0, 120)
teammatePanel.Size = UDim2.fromOffset(240, 320)
teammatePanel.BackgroundTransparency = 1
teammatePanel.Visible = false
teammatePanel.Parent = screenGui

local teammateLayout = Instance.new("UIListLayout")
teammateLayout.SortOrder = Enum.SortOrder.LayoutOrder
teammateLayout.Padding = UDim.new(0, 10)
teammateLayout.Parent = teammatePanel

local function renderTeammateCard(teammate: any, index: number)
	local accent = SECTOR_COLORS[teammate.heroId] or DEFAULT_ACCENT

	local card = Instance.new("Frame")
	card.Name = "Teammate_" .. teammate.heroId
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 78)
	card.LayoutOrder = index
	card.Parent = teammatePanel
	corner(card, 8)
	padding(card, 10)

	local stripe = Instance.new("Frame")
	stripe.Name = "AccentStripe"
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.AnchorPoint = Vector2.new(0, 0)
	stripe.Position = UDim2.new(0, 0, 0, 0)
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "HeroName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 8, 0, 0)
	nameLabel.Size = UDim2.new(1, -8, 0, 22)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = TEXT
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = teammate.name
	nameLabel.Parent = card

	local badge = Instance.new("TextLabel")
	badge.Name = "InCombatBadge"
	badge.BackgroundColor3 = DANGER
	badge.BackgroundTransparency = if teammate.inCombat then 0 else 1
	badge.BorderSizePixel = 0
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 0, 0, 2)
	badge.Size = UDim2.fromOffset(86, 18)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.TextColor3 = if teammate.inCombat then Color3.new(1, 1, 1) else DANGER
	badge.Text = "IN COMBAT"
	badge.Visible = teammate.inCombat
	badge.Parent = card
	corner(badge, 4)

	-- HP bar
	local pct = 0
	if teammate.coreMaxHp and teammate.coreMaxHp > 0 then
		pct = math.clamp(teammate.coreHp / teammate.coreMaxHp, 0, 1)
	end

	local barBg = Instance.new("Frame")
	barBg.Name = "HpBarBg"
	barBg.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
	barBg.BorderSizePixel = 0
	barBg.Position = UDim2.new(0, 8, 0, 32)
	barBg.Size = UDim2.new(1, -8, 0, 14)
	barBg.Parent = card
	corner(barBg, 4)

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = accent
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.new(pct, 0, 1, 0)
	barFill.Parent = barBg
	corner(barFill, 4)

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HpLabel"
	hpLabel.BackgroundTransparency = 1
	hpLabel.Position = UDim2.new(0, 8, 0, 50)
	hpLabel.Size = UDim2.new(1, -8, 0, 16)
	hpLabel.Font = Enum.Font.Gotham
	hpLabel.TextSize = 12
	hpLabel.TextColor3 = TEXT_DIM
	hpLabel.TextXAlignment = Enum.TextXAlignment.Left
	hpLabel.Text = string.format("Core HP  %d%%", math.floor(pct * 100 + 0.5))
	hpLabel.Parent = card
end

local function renderTeammates(state: any)
	clearChildren(teammatePanel)
	if not state.selfHeroId then
		teammatePanel.Visible = false
		return
	end
	for i, teammate in ipairs(state.teammates) do
		renderTeammateCard(teammate, i)
	end
	teammatePanel.Visible = #state.teammates > 0
end

-- ─── State application ──────────────────────────────────────────────────
local function applyState(state: any)
	if typeof(state) ~= "table" then
		return
	end
	renderRevealPanel(state.composition)
	renderTeammates(state)
end

stateUpdate.OnClientEvent:Connect(applyState)
