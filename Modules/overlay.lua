local SCM = select(2, ...)
local Cache = SCM.Cache

local blizzardActionButtonHooksSet
local ellesmereUIActionButtonHooksSet
local hookedActionButtonLibraries = {}
local pressedChildrenByButtonKey = {}
local pressCountsByChild = {}

function SCM:ClearChildPressOverlay(child)
	if not pressCountsByChild[child] then
		return
	end

	for key, pressedChild in pairs(pressedChildrenByButtonKey) do
		if pressedChild == child then
			pressedChildrenByButtonKey[key] = nil
		end
	end
	pressCountsByChild[child] = nil
	child.SCMPressOverlay:Hide()
end

local function ReleasePressOverlay(key)
	local child = pressedChildrenByButtonKey[key]
	if not child then
		return
	end

	pressedChildrenByButtonKey[key] = nil
	local count = pressCountsByChild[child] - 1
	if count > 0 then
		pressCountsByChild[child] = count
	else
		pressCountsByChild[child] = nil
		child.SCMPressOverlay:Hide()
	end
end

local function GetChildForAction(action)
	local actionType, actionID, actionSubType = GetActionInfo(action)

	local spellID
	if actionType == "spell" or actionSubType == "spell" then
		spellID = FindSpellOverrideByID(actionID) or actionID
	elseif actionType == "macro" then
		spellID = GetMacroSpell(actionID)
	end

	if spellID then
		local child = Cache.cachedChildsBySpellID[spellID]
		if child and child.SCMPressOverlay then
			return child
		end
	end
end

local function PressOverlay(key, action)
	if not action then
		return
	end

	if pressedChildrenByButtonKey[key] then
		return
	end

	local child = GetChildForAction(action)
	if not child then
		return
	end

	pressedChildrenByButtonKey[key] = child
	pressCountsByChild[child] = (pressCountsByChild[child] or 0) + 1
	child.SCMPressOverlay:Show()
end

local function OnLABActionButtonPostClick(button, _, down)
	if down then
		if SCM.db.profile.options.pressOverlay and button._state_type == "action" then
			PressOverlay(button, button._state_action)
		end
		return
	end

	ReleasePressOverlay(button)
end

local function HookLABActionButton(button)
	if button.SCMPressOverlayHooked then
		return
	end

	button.SCMPressOverlayHooked = true
	button:HookScript("PostClick", OnLABActionButtonPostClick)
end

local function OnLABActionButtonCreated(_, button)
	HookLABActionButton(button)
end

local function SetLABActionButtonHooks(library)
	if not library or hookedActionButtonLibraries[library] then
		return
	end

	library.RegisterCallback(SCM, "OnButtonCreated", OnLABActionButtonCreated)
	for button in pairs(library.buttonRegistry) do
		HookLABActionButton(button)
	end
	hookedActionButtonLibraries[library] = true
end

local function SetBlizzardActionButtonHooks()
	if blizzardActionButtonHooksSet then
		return
	end

	blizzardActionButtonHooksSet = true

	hooksecurefunc("ActionButtonDown", function(id)
		if not SCM.db.profile.options.pressOverlay then
			return
		end

		local actionButton = GetActionButtonForID(id)
		if actionButton then
			PressOverlay(id, actionButton.action)
		end
	end)

	hooksecurefunc("ActionButtonUp", function(id)
		ReleasePressOverlay(id)
	end)

	hooksecurefunc("MultiActionButtonDown", function(barName, id)
		if not SCM.db.profile.options.pressOverlay then
			return
		end

		local bar = _G[barName]
		if bar then
			PressOverlay(barName .. id, bar.actionButtons[id].action)
		end
	end)

	hooksecurefunc("MultiActionButtonUp", function(barName, id)
		ReleasePressOverlay(barName .. id)
	end)
end

local function OnEllesmereUIActionButtonPress(button, down)
	if down then
		if SCM.db.profile.options.pressOverlay then
			local action = button:GetAttribute("action") or button.action
			PressOverlay(button, action)
		end
		return
	end

	ReleasePressOverlay(button)
end

local function SetEllesmereUIActionButtonHooks()
	if ellesmereUIActionButtonHooksSet then
		return
	end

	ellesmereUIActionButtonHooksSet = true
	if _EUI_OnActionButtonPress then
		hooksecurefunc("_EUI_OnActionButtonPress", OnEllesmereUIActionButtonPress)
	end
end

local function ClearPressOverlays()
	for child in pairs(pressCountsByChild) do
		child.SCMPressOverlay:Hide()
	end
	wipe(pressCountsByChild)
	wipe(pressedChildrenByButtonKey)
end

function SCM:ApplyPressOverlayOptions()
	if not SCM.db.profile.options.pressOverlay then
		ClearPressOverlays()
		return
	end

	SetLABActionButtonHooks(LibStub("LibActionButton-1.0", true))
	SetLABActionButtonHooks(LibStub("LibActionButton-1.0-ElvUI", true))
	SetBlizzardActionButtonHooks()

	if C_AddOns.IsAddOnLoaded("EllesmereUIActionBars") then
		SetEllesmereUIActionButtonHooks()
	end
end
