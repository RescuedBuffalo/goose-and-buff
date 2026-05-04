--!strict
-- BUF-92: Run-level HUD.
-- Renders phase + round info from RunUpdate (PREP / WAVE / DEBRIEF
-- countdowns and round indicator) plus the end screen with a Restart
-- button. Per the BUF-92 notes, this is a single ScreenGui swap — we
-- don't try to build a lobby; the Restart button is just respawn for
-- v0.1 (lodge comes in v0.2).
--
-- Countdown trick: the server sends a `deadline` (workspace:GetServerTimeNow()
-- based) on each phase transition rather than per-second tick payloads.
-- The client redraws every Heartbeat so prep / debrief timers stay
-- smooth without flooding the network.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local LocalPlayer = Players.LocalPlayer

local TEXT = Color3.fromRGB(240, 240, 240)
local TEXT_DIM = Color3.fromRGB(170, 170, 180)
local CARD_BG = Color3.fromRGB(28, 30, 38)
local PREP_ACCENT = Color3.fromRGB(120, 180, 255)
local WAVE_ACCENT = Color3.fromRGB(220, 80, 80)
local DEBRIEF_ACCENT = Color3.fromRGB(160, 220, 130)
local WIN_ACCENT = Color3.fromRGB(70, 180, 90)
local LOSS_ACCENT = Color3.fromRGB(200, 70, 70)

local runUpdate = ReplicatedStorage:WaitForChild(Constants.REMOTES.RunUpdate) :: RemoteEvent
local restartRequest = ReplicatedStorage:WaitForChild(Constants.REMOTES.RestartRequest) :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
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

-- ─── Phase banner (top-center) ──────────────────────────────────────────
local banner = Instance.new("Frame")
banner.Name = "PhaseBanner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 0)
banner.Size = UDim2.fromOffset(360, 60)
banner.BackgroundColor3 = CARD_BG
banner.BackgroundTransparency = 0.1
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = screenGui

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = PREP_ACCENT
bannerStroke.Thickness = 2
bannerStroke.Parent = banner
corner(banner, 0)

local bannerPhaseLabel = Instance.new("TextLabel")
bannerPhaseLabel.Name = "Phase"
bannerPhaseLabel.BackgroundTransparency = 1
bannerPhaseLabel.Position = UDim2.new(0, 16, 0, 6)
bannerPhaseLabel.Size = UDim2.new(1, -32, 0, 18)
bannerPhaseLabel.Font = Enum.Font.GothamBold
bannerPhaseLabel.TextSize = 13
bannerPhaseLabel.TextColor3 = PREP_ACCENT
bannerPhaseLabel.TextXAlignment = Enum.TextXAlignment.Left
bannerPhaseLabel.Text = "PREP PHASE"
bannerPhaseLabel.Parent = banner

local bannerRoundLabel = Instance.new("TextLabel")
bannerRoundLabel.Name = "Round"
bannerRoundLabel.BackgroundTransparency = 1
bannerRoundLabel.Position = UDim2.new(1, -16, 0, 6)
bannerRoundLabel.AnchorPoint = Vector2.new(1, 0)
bannerRoundLabel.Size = UDim2.fromOffset(120, 18)
bannerRoundLabel.Font = Enum.Font.Gotham
bannerRoundLabel.TextSize = 12
bannerRoundLabel.TextColor3 = TEXT_DIM
bannerRoundLabel.TextXAlignment = Enum.TextXAlignment.Right
bannerRoundLabel.Text = "ROUND 1 / 3"
bannerRoundLabel.Parent = banner

local bannerCountdown = Instance.new("TextLabel")
bannerCountdown.Name = "Countdown"
bannerCountdown.BackgroundTransparency = 1
bannerCountdown.Position = UDim2.new(0, 16, 0, 22)
bannerCountdown.Size = UDim2.new(1, -32, 0, 32)
bannerCountdown.Font = Enum.Font.GothamBold
bannerCountdown.TextSize = 26
bannerCountdown.TextColor3 = TEXT
bannerCountdown.TextXAlignment = Enum.TextXAlignment.Left
bannerCountdown.Text = "30s"
bannerCountdown.Parent = banner

-- ─── End screen overlay ─────────────────────────────────────────────────
local endOverlay = Instance.new("Frame")
endOverlay.Name = "EndScreen"
endOverlay.Size = UDim2.fromScale(1, 1)
endOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
endOverlay.BackgroundTransparency = 0.35
endOverlay.BorderSizePixel = 0
endOverlay.Visible = false
endOverlay.Parent = screenGui

local endCard = Instance.new("Frame")
endCard.Name = "Card"
endCard.AnchorPoint = Vector2.new(0.5, 0.5)
endCard.Position = UDim2.fromScale(0.5, 0.5)
endCard.Size = UDim2.fromOffset(480, 280)
endCard.BackgroundColor3 = CARD_BG
endCard.BorderSizePixel = 0
endCard.Parent = endOverlay
corner(endCard, 12)
padding(endCard, 28)

local endStroke = Instance.new("UIStroke")
endStroke.Color = WIN_ACCENT
endStroke.Thickness = 3
endStroke.Parent = endCard

local endTitle = Instance.new("TextLabel")
endTitle.Name = "Title"
endTitle.BackgroundTransparency = 1
endTitle.Size = UDim2.new(1, 0, 0, 28)
endTitle.Font = Enum.Font.GothamBold
endTitle.TextSize = 18
endTitle.TextColor3 = WIN_ACCENT
endTitle.TextXAlignment = Enum.TextXAlignment.Center
endTitle.Text = "RUN COMPLETE"
endTitle.Parent = endCard

local endResult = Instance.new("TextLabel")
endResult.Name = "Result"
endResult.BackgroundTransparency = 1
endResult.Position = UDim2.new(0, 0, 0, 36)
endResult.Size = UDim2.new(1, 0, 0, 70)
endResult.Font = Enum.Font.GothamBold
endResult.TextSize = 56
endResult.TextColor3 = TEXT
endResult.TextXAlignment = Enum.TextXAlignment.Center
endResult.Text = "VICTORY"
endResult.Parent = endCard

local endSubtitle = Instance.new("TextLabel")
endSubtitle.Name = "Subtitle"
endSubtitle.BackgroundTransparency = 1
endSubtitle.Position = UDim2.new(0, 0, 0, 116)
endSubtitle.Size = UDim2.new(1, 0, 0, 24)
endSubtitle.Font = Enum.Font.Gotham
endSubtitle.TextSize = 15
endSubtitle.TextColor3 = TEXT_DIM
endSubtitle.TextXAlignment = Enum.TextXAlignment.Center
endSubtitle.Text = ""
endSubtitle.Parent = endCard

local restartButton = Instance.new("TextButton")
restartButton.Name = "Restart"
restartButton.AnchorPoint = Vector2.new(0.5, 1)
restartButton.Position = UDim2.new(0.5, 0, 1, 0)
restartButton.Size = UDim2.fromOffset(220, 48)
restartButton.BackgroundColor3 = WIN_ACCENT
restartButton.BorderSizePixel = 0
restartButton.AutoButtonColor = true
restartButton.Font = Enum.Font.GothamBold
restartButton.TextSize = 18
restartButton.TextColor3 = TEXT
restartButton.Text = "RETURN TO LOBBY"
restartButton.Parent = endCard
corner(restartButton, 8)

restartButton.Activated:Connect(function()
	-- v0.1: server respawns the player. We don't optimistically hide
	-- the overlay — a respawn that races a network drop would leave
	-- the user with a blank UI; let the next RunUpdate dictate state.
	restartRequest:FireServer()
end)

-- ─── State ──────────────────────────────────────────────────────────────
type RunStatus = {
	phase: string,
	round: number,
	totalRounds: number,
	deadline: number?,
	result: string?,
}

local currentStatus: RunStatus? = nil

local PHASE_LABELS: { [string]: string } = {
	prep = "PREP PHASE",
	wave = "WAVE INCOMING",
	debrief = "DEBRIEF",
}

local PHASE_ACCENTS: { [string]: Color3 } = {
	prep = PREP_ACCENT,
	wave = WAVE_ACCENT,
	debrief = DEBRIEF_ACCENT,
}

local function applyTransientPhase(status: RunStatus)
	endOverlay.Visible = false
	banner.Visible = true

	local accent = PHASE_ACCENTS[status.phase] or TEXT_DIM
	bannerStroke.Color = accent
	bannerPhaseLabel.TextColor3 = accent
	bannerPhaseLabel.Text = PHASE_LABELS[status.phase] or string.upper(status.phase)
	bannerRoundLabel.Text = string.format("ROUND %d / %d", status.round, status.totalRounds)

	if status.phase == "wave" then
		-- Wave duration is variable (depends on enemy clears), so we
		-- just say "in progress" instead of trying to count down.
		bannerCountdown.Text = "in progress"
	end
	-- Countdown text for prep/debrief is filled by the Heartbeat tick.
end

local function applyEndScreen(status: RunStatus)
	banner.Visible = false
	endOverlay.Visible = true

	local isWin = status.result == "win"
	local accent = if isWin then WIN_ACCENT else LOSS_ACCENT
	endStroke.Color = accent
	endTitle.TextColor3 = accent
	endTitle.Text = if isWin then "RUN COMPLETE" else "RUN ENDED"
	endResult.Text = if isWin then "VICTORY" else "DEFEAT"
	endSubtitle.Text = if isWin
		then string.format("All %d rounds cleared.", status.totalRounds)
		else string.format("A core fell on round %d.", status.round)
	restartButton.BackgroundColor3 = accent
end

local function applyStatus(status: RunStatus?)
	currentStatus = status
	if not status then
		banner.Visible = false
		endOverlay.Visible = false
		return
	end
	if status.phase == "victory" or status.phase == "defeat" then
		applyEndScreen(status)
	else
		applyTransientPhase(status)
	end
end

runUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	applyStatus(payload :: RunStatus)
end)

-- Ask the server for the current status. The server also broadcasts on
-- join, but that send races our OnClientEvent:Connect; this handshake
-- guarantees we don't sit on a blank HUD if the join-time push was lost.
runUpdate:FireServer()

-- Smooth countdown for prep/debrief phases. We redraw every Heartbeat
-- against the server-provided deadline rather than running our own
-- timer (no drift, recovers cleanly across phase changes).
RunService.Heartbeat:Connect(function()
	local status = currentStatus
	if not status then return end
	local deadline = status.deadline
	if not deadline then return end
	if status.phase ~= "prep" and status.phase ~= "debrief" then return end
	local remaining = math.max(0, deadline - workspace:GetServerTimeNow())
	bannerCountdown.Text = string.format("%ds", math.ceil(remaining))
end)
