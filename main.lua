--==================================================
-- Push to Talk by Kixdev
-- Default: PUSH TO TALK ON
-- Hold bound key/mouse = talk
-- Release = stop talking
-- PTT OFF = normal open mic (no hotkey needed)
-- Hide / Show UI = comma (,)
-- Supports: Keyboard + Mouse1 / Mouse2
-- UI forced to front
--==================================================

--==================== SINGLE INSTANCE CLEANUP ====================
do
	local oldCleanup = rawget(_G, "__KIX_PTT_CLEANUP__")
	if type(oldCleanup) == "function" then
		pcall(oldCleanup)
	end
end

--==================== SERVICES ====================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==================== STATE ====================
local connections = {}
local destroyed = false

local uiHidden = false
local bindingMode = false
local bindingArmTime = 0

local pttEnabled = true
local isTransmitting = false

local voiceChecked = false
local voiceEnabled = false
local audioInput = nil
local lastFindTry = 0

local activeSources = {
	bind = false,
	hold = false,
}

local currentBinding = {
	kind = "KeyCode",
	value = Enum.KeyCode.V
}

--==================== HELPERS ====================
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function disconnectAll()
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
end

local function safeDestroy(obj)
	if obj and obj.Parent then
		pcall(function()
			obj:Destroy()
		end)
	end
end

local function bindingToText(binding)
	if not binding or not binding.value then
		return "NONE"
	end

	if binding.kind == "KeyCode" then
		return tostring(binding.value.Name):upper()
	elseif binding.kind == "MouseButton" then
		if binding.value == Enum.UserInputType.MouseButton1 then
			return "MOUSE1"
		elseif binding.value == Enum.UserInputType.MouseButton2 then
			return "MOUSE2"
		elseif binding.value == Enum.UserInputType.MouseButton3 then
			return "MOUSE3"
		end
	end

	return "UNKNOWN"
end

local function inputToBinding(input)
	if not input then
		return nil
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
			return {
				kind = "KeyCode",
				value = input.KeyCode
			}
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3 then
		return {
			kind = "MouseButton",
			value = input.UserInputType
		}
	end

	return nil
end

local function bindingMatchesInput(binding, input)
	if not binding or not input then
		return false
	end

	if binding.kind == "KeyCode" then
		return input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == binding.value
	elseif binding.kind == "MouseButton" then
		return input.UserInputType == binding.value
	end

	return false
end

local function isAudioDeviceInput(obj)
	local ok, result = pcall(function()
		return obj and obj:IsA("AudioDeviceInput")
	end)
	return ok and result
end

local function findLocalAudioInput()
	for _, child in ipairs(LocalPlayer:GetChildren()) do
		if isAudioDeviceInput(child) then
			return child
		end
	end

	for _, desc in ipairs(LocalPlayer:GetDescendants()) do
		if isAudioDeviceInput(desc) then
			return desc
		end
	end

	return nil
end

local function refreshVoiceEnabled()
	local ok, result = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId)
	end)

	voiceChecked = true
	voiceEnabled = ok and result == true
	return voiceEnabled
end

local function ensureAudioInput()
	if audioInput and audioInput.Parent and isAudioDeviceInput(audioInput) then
		return audioInput
	end

	audioInput = findLocalAudioInput()
	return audioInput
end

local function anySourceActive()
	for _, v in pairs(activeSources) do
		if v then
			return true
		end
	end
	return false
end

--==================== UI ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KIX_PTT_GUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999999
pcall(function()
	screenGui.OnTopOfCoreBlur = true
end)
screenGui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 220, 0, 276)
main.Position = UDim2.new(0, 24, 0.5, -138)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
main.BorderSizePixel = 0
main.ZIndex = 100
main.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 18)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Thickness = 1.2
mainStroke.Color = Color3.fromRGB(60, 60, 70)
mainStroke.Transparency = 0.12
mainStroke.Parent = main

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 48)
topBar.BackgroundTransparency = 1
topBar.ZIndex = 101
topBar.Parent = main

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 6)
title.Size = UDim2.new(1, -24, 0, 18)
title.Font = Enum.Font.GothamBold
title.Text = "Push to Talk by Kixdev"
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 102
title.Parent = topBar

local reminderLabel = Instance.new("TextLabel")
reminderLabel.Name = "ReminderLabel"
reminderLabel.BackgroundTransparency = 1
reminderLabel.Position = UDim2.new(0, 12, 0, 24)
reminderLabel.Size = UDim2.new(1, -24, 0, 22)
reminderLabel.Font = Enum.Font.Gotham
reminderLabel.Text = "Don't forget to enable your in-game mic."
reminderLabel.TextWrapped = true
reminderLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
reminderLabel.TextSize = 11
reminderLabel.TextXAlignment = Enum.TextXAlignment.Left
reminderLabel.TextYAlignment = Enum.TextYAlignment.Top
reminderLabel.ZIndex = 102
reminderLabel.Parent = topBar

local micButton = Instance.new("TextButton")
micButton.Name = "MicButton"
micButton.AutoButtonColor = false
micButton.Text = ""
micButton.Size = UDim2.new(0, 86, 0, 86)
micButton.Position = UDim2.new(0.5, -43, 0, 68)
micButton.BackgroundColor3 = Color3.fromRGB(35, 170, 85)
micButton.BorderSizePixel = 0
micButton.ZIndex = 105
micButton.Parent = main

local micCorner = Instance.new("UICorner")
micCorner.CornerRadius = UDim.new(1, 0)
micCorner.Parent = micButton

local micStroke = Instance.new("UIStroke")
micStroke.Thickness = 2
micStroke.Color = Color3.fromRGB(120, 255, 170)
micStroke.Transparency = 0.06
micStroke.Parent = micButton

local micGlow = Instance.new("Frame")
micGlow.Name = "Glow"
micGlow.AnchorPoint = Vector2.new(0.5, 0.5)
micGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
micGlow.Size = UDim2.new(1, 18, 1, 18)
micGlow.BackgroundColor3 = Color3.fromRGB(70, 255, 120)
micGlow.BackgroundTransparency = 0.82
micGlow.BorderSizePixel = 0
micGlow.Visible = false
micGlow.ZIndex = 104
micGlow.Parent = micButton

local micGlowCorner = Instance.new("UICorner")
micGlowCorner.CornerRadius = UDim.new(1, 0)
micGlowCorner.Parent = micGlow

local micIcon = Instance.new("TextLabel")
micIcon.Name = "MicIcon"
micIcon.BackgroundTransparency = 1
micIcon.Size = UDim2.new(1, 0, 1, 0)
micIcon.Font = Enum.Font.GothamBold
micIcon.Text = "MIC"
micIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
micIcon.TextSize = 25
micIcon.ZIndex = 106
micIcon.Parent = micButton

local slash = Instance.new("Frame")
slash.Name = "Slash"
slash.AnchorPoint = Vector2.new(0.5, 0.5)
slash.Position = UDim2.new(0.5, 0, 0.5, 0)
slash.Size = UDim2.new(0, 66, 0, 5)
slash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
slash.BorderSizePixel = 0
slash.Rotation = -35
slash.Visible = false
slash.ZIndex = 107
slash.Parent = micButton

local slashCorner = Instance.new("UICorner")
slashCorner.CornerRadius = UDim.new(1, 0)
slashCorner.Parent = slash

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.new(0, 12, 0, 162)
statusLabel.Size = UDim2.new(1, -24, 0, 18)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Text = "PUSH TO TALK ON"
statusLabel.TextColor3 = Color3.fromRGB(130, 255, 165)
statusLabel.TextSize = 13
statusLabel.ZIndex = 102
statusLabel.Parent = main

local bindLabel = Instance.new("TextLabel")
bindLabel.Name = "BindLabel"
bindLabel.BackgroundTransparency = 1
bindLabel.Position = UDim2.new(0, 12, 0, 188)
bindLabel.Size = UDim2.new(1, -24, 0, 18)
bindLabel.Font = Enum.Font.Gotham
bindLabel.Text = "Hotkey: V"
bindLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
bindLabel.TextSize = 12
bindLabel.ZIndex = 102
bindLabel.Parent = main

local bindButton = Instance.new("TextButton")
bindButton.Name = "BindButton"
bindButton.AutoButtonColor = false
bindButton.Position = UDim2.new(0.5, -62, 0, 214)
bindButton.Size = UDim2.new(0, 124, 0, 24)
bindButton.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
bindButton.BorderSizePixel = 0
bindButton.Text = "Bind Hotkey"
bindButton.Font = Enum.Font.GothamBold
bindButton.TextSize = 12
bindButton.TextColor3 = Color3.fromRGB(245, 245, 245)
bindButton.ZIndex = 103
bindButton.Parent = main

local bindCorner = Instance.new("UICorner")
bindCorner.CornerRadius = UDim.new(0, 10)
bindCorner.Parent = bindButton

local bindStroke = Instance.new("UIStroke")
bindStroke.Thickness = 1
bindStroke.Color = Color3.fromRGB(75, 75, 90)
bindStroke.Transparency = 0.2
bindStroke.Parent = bindButton

local holdButton = Instance.new("TextButton")
holdButton.Name = "HoldButton"
holdButton.AutoButtonColor = false
holdButton.Position = UDim2.new(0.5, -78, 0, 244)
holdButton.Size = UDim2.new(0, 156, 0, 26)
holdButton.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
holdButton.BorderSizePixel = 0
holdButton.Text = "HOLD TO TALK"
holdButton.Font = Enum.Font.GothamBold
holdButton.TextSize = 12
holdButton.TextColor3 = Color3.fromRGB(255, 255, 255)
holdButton.ZIndex = 103
holdButton.Parent = main

local holdCorner = Instance.new("UICorner")
holdCorner.CornerRadius = UDim.new(0, 10)
holdCorner.Parent = holdButton

local holdStroke = Instance.new("UIStroke")
holdStroke.Thickness = 1
holdStroke.Color = Color3.fromRGB(95, 95, 110)
holdStroke.Transparency = 0.15
holdStroke.Parent = holdButton

--==================== DRAG ====================
do
	local dragging = false
	local dragStart
	local startPos

	local function updateDrag(input)
		local delta = input.Position - dragStart
		main.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end

	connect(topBar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = main.Position

			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if changed then
						changed:Disconnect()
					end
				end
			end)
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			updateDrag(input)
		end
	end)
end

--==================== VISUAL ====================
local function updateBindText(extra)
	local txt = "Hotkey: " .. bindingToText(currentBinding)
	if extra and extra ~= "" then
		txt = txt .. "  |  " .. extra
	end
	bindLabel.Text = txt
end

local function updateVisual()
	if bindingMode then
		statusLabel.Text = "PRESS A KEY / MOUSE"
		statusLabel.TextColor3 = Color3.fromRGB(255, 220, 130)

		micButton.BackgroundColor3 = Color3.fromRGB(180, 130, 30)
		micStroke.Color = Color3.fromRGB(255, 210, 120)
		micGlow.Visible = false
		slash.Visible = false

		holdButton.BackgroundColor3 = Color3.fromRGB(55, 55, 68)
		holdStroke.Color = Color3.fromRGB(255, 210, 120)
		return
	end

	if pttEnabled then
		statusLabel.Text = "PUSH TO TALK ON"
		statusLabel.TextColor3 = Color3.fromRGB(130, 255, 165)

		micButton.BackgroundColor3 = Color3.fromRGB(35, 170, 85)
		micStroke.Color = Color3.fromRGB(120, 255, 170)
		slash.Visible = false
		micGlow.Visible = isTransmitting

		if activeSources.hold then
			holdButton.BackgroundColor3 = Color3.fromRGB(35, 170, 85)
			holdStroke.Color = Color3.fromRGB(120, 255, 170)
		else
			holdButton.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
			holdStroke.Color = Color3.fromRGB(95, 95, 110)
		end
	else
		statusLabel.Text = "PUSH TO TALK OFF"
		statusLabel.TextColor3 = Color3.fromRGB(255, 150, 150)

		micButton.BackgroundColor3 = Color3.fromRGB(145, 40, 40)
		micStroke.Color = Color3.fromRGB(255, 120, 120)
		slash.Visible = true
		micGlow.Visible = false

		holdButton.BackgroundColor3 = Color3.fromRGB(55, 28, 28)
		holdStroke.Color = Color3.fromRGB(140, 75, 75)
	end
end

--==================== MIC APPLY ====================
local function applyMicState()
	if destroyed then
		return
	end

	if not voiceChecked then
		refreshVoiceEnabled()
	end

	local inputObj = ensureAudioInput()
	isTransmitting = pttEnabled and anySourceActive()

	if not voiceEnabled or not inputObj then
		updateVisual()
		return
	end

	if pttEnabled then
		pcall(function()
			inputObj.Muted = not isTransmitting
		end)
	else
		pcall(function()
			inputObj.Muted = false
		end)
	end

	updateVisual()
end

local function setSourceActive(sourceName, isActive)
	activeSources[sourceName] = isActive and true or false
	applyMicState()
end

--==================== BINDING ====================
local function startBinding()
	bindingMode = true
	bindingArmTime = tick() + 0.15
	bindButton.Text = "Listening..."
	updateBindText("press key / mouse")
	updateVisual()
end

local function finishBinding(newBinding)
	if newBinding then
		currentBinding = newBinding
	end

	bindingMode = false
	bindButton.Text = "Bind Hotkey"
	updateBindText()
	applyMicState()
end

--==================== HOLD BUTTON ====================
local function beginHoldButton()
	if bindingMode then
		return
	end
	if not pttEnabled then
		return
	end
	setSourceActive("hold", true)
end

local function endHoldButton()
	setSourceActive("hold", false)
end

--==================== INIT ====================
refreshVoiceEnabled()
ensureAudioInput()
updateBindText()
applyMicState()

--==================== UI EVENTS ====================
connect(bindButton.MouseButton1Click, function()
	startBinding()
end)

connect(micButton.MouseButton1Click, function()
	pttEnabled = not pttEnabled

	if not pttEnabled then
		activeSources.bind = false
		activeSources.hold = false
	end

	applyMicState()
end)

connect(holdButton.MouseButton1Down, function()
	beginHoldButton()
end)

connect(holdButton.MouseButton1Up, function()
	endHoldButton()
end)

connect(holdButton.MouseLeave, function()
	endHoldButton()
end)

connect(holdButton.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		beginHoldButton()
	end
end)

connect(holdButton.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		endHoldButton()
	end
end)

--==================== INPUT EVENTS ====================
connect(UserInputService.InputBegan, function(input, gameProcessed)
	if destroyed then
		return
	end

	if bindingMode then
		if tick() < bindingArmTime then
			return
		end

		local newBinding = inputToBinding(input)
		if newBinding then
			finishBinding(newBinding)
		elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
			finishBinding(nil)
		end
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Comma then
		uiHidden = not uiHidden
		main.Visible = not uiHidden
		return
	end

	if bindingMatchesInput(currentBinding, input) then
		setSourceActive("bind", true)
		return
	end

	if gameProcessed then
		return
	end
end)

connect(UserInputService.InputEnded, function(input)
	if destroyed then
		return
	end

	if bindingMode then
		return
	end

	if bindingMatchesInput(currentBinding, input) then
		setSourceActive("bind", false)
	end
end)

connect(UserInputService.WindowFocusReleased, function()
	activeSources.bind = false
	activeSources.hold = false
	applyMicState()
end)

--==================== WATCH FOR AUDIO INPUT ====================
connect(LocalPlayer.ChildAdded, function(child)
	if isAudioDeviceInput(child) then
		audioInput = child
		applyMicState()
	end
end)

connect(LocalPlayer.DescendantAdded, function(desc)
	if isAudioDeviceInput(desc) then
		audioInput = desc
		applyMicState()
	end
end)

--==================== RENDER LOOP ====================
connect(RunService.RenderStepped, function()
	if destroyed then
		return
	end

	local now = tick()

	if voiceEnabled and (not audioInput or not audioInput.Parent) and now - lastFindTry > 2 then
		lastFindTry = now
		ensureAudioInput()
		applyMicState()
	end

	if micGlow.Visible then
		local s = 1 + (math.sin(now * 8) * 0.07)
		micGlow.Size = UDim2.new(s, 18, s, 18)
		micGlow.BackgroundTransparency = 0.72 + ((math.sin(now * 8) + 1) * 0.08)
	else
		micGlow.Size = UDim2.new(1, 18, 1, 18)
		micGlow.BackgroundTransparency = 0.82
	end
end)

--==================== CLEANUP ====================
local function cleanup()
	if destroyed then
		return
	end
	destroyed = true

	pcall(function()
		if audioInput and audioInput.Parent then
			audioInput.Muted = true
		end
	end)

	disconnectAll()
	safeDestroy(screenGui)
	_G.__KIX_PTT_CLEANUP__ = nil
end

_G.__KIX_PTT_CLEANUP__ = cleanup

print("[KIX PTT] Loaded.")
print("[KIX PTT] Default state: PUSH TO TALK ON")
print("[KIX PTT] PTT OFF = normal open mic")
print("[KIX PTT] Current bind:", bindingToText(currentBinding))
print("[KIX PTT] Supported mouse binds: Mouse1 / Mouse2 / Mouse3")
print("[KIX PTT] Press comma (,) to hide/show UI.")
print("[KIX PTT] UI forced to front with high DisplayOrder/ZIndex.")
