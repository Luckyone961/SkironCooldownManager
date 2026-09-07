local SCM = select(2, ...)

local Icons = SCM.Icons
local Cache = SCM.Cache
local Utils = SCM.Utils
local Constants = SCM.Constants
local States = SCM.States
local AddChildToGroup = Utils.AddChildToGroup
local GetSpellConfigByCooldownID = Utils.GetSpellConfigByCooldownID
local Cooldowns = SCM.Cooldowns
local TRACKED_BAR_CATEGORY = Enum.CooldownViewerCategory.TrackedBar
local delayedHideSpellIDs = {
	--[450615] = true,
}
local delayedHideSeconds = 0.03

local function OnSetAlpha(self)
	UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
end
function Icons.HideChild(child)
	SCM.StopChildGlows(child)
	SCM:ClearChildPressOverlay(child)

	if child.SCMSpellID and not child.SCMBuffOptions and not child.SCMBuffBar then
		Cache.cachedChildsBySpellID[child.SCMSpellID] = nil
	end

	if child.SCMHidden then
		return
	elseif not child.viewerFrame then
		child.SCMHidden = true
		UIParent.SetAlpha(child, 0)
		return
	end

	SCM:PositionHiddenManagedChild(child)
	child.SCMHidden = true
	UIParent.SetAlpha(child, 0)
	child:EnableMouse(false)
	child:SetMouseClickEnabled(false)
	child:SetMouseMotionEnabled(false)
	if not child.SCMAlphaHook then
		child.SCMAlphaHook = true
		hooksecurefunc(child, "SetAlpha", OnSetAlpha)
	end
end

local function CancelChildHideTimer(child)
	if child.SCMHideTimer then
		child.SCMHideTimer:Cancel()
		child.SCMHideTimer = nil
	end
end

function Icons.ShowChild(child)
	CancelChildHideTimer(child)

	if child.SCMLayoutLimited then
		return
	end

	if child.SCMSpellID and not child.SCMBuffOptions and not child.SCMBuffBar then
		Cache.cachedChildsBySpellID[child.SCMSpellID] = child
	end

	if child.viewerFrame and child.SCMHidden then
		child.SCMHidden = false
		UIParent.SetAlpha(child, 1)
		child:SetMouseClickEnabled(false)

		if SCM.showTooltips then
			child:EnableMouse(true)
			child:SetMouseMotionEnabled(true)
		else
			child:EnableMouse(false)
		end
	end
end

function Icons.SetChildVisibilityState(child, shouldShow, applyNow)
	child.SCMShouldBeVisible = shouldShow and true or false
	if not applyNow then
		return
	end

	child.SCMAppliedVisibility = child.SCMShouldBeVisible and not child.SCMLayoutLimited
	child.SCMAppliedLayoutLimited = child.SCMLayoutLimited and true or false

	if child.viewerFrame then
		if shouldShow and not child.SCMLayoutLimited then
			Icons.ShowChild(child)
		else
			Icons.HideChild(child)
		end
		return
	end
	if not child.SCMShouldBeVisible or child.SCMLayoutLimited then
		SCM.StopChildGlows(child)
	end

	if child.SCMCustom and not child:GetAttribute("statehidden") then
		local shouldBeShown = child.SCMShouldBeVisible and not child.SCMLayoutLimited
		if child:IsShown() == shouldBeShown then
			return
		end

		child.SCMSkipShowValidation = shouldBeShown and true or nil
		child:SetShown(shouldBeShown)
		child.SCMSkipShowValidation = nil
	end
end

function Icons.UpdateChildDesaturation(child, shouldDesaturate, forceDesaturation)
	if child.Icon and child.SCMConfig then
		if forceDesaturation then
			child.Icon.SCMDesaturated = shouldDesaturate
		else
			child.Icon.SCMDesaturated = nil
		end

		if child.Icon.Icon then
			child.Icon.Icon:SetDesaturated(shouldDesaturate)
		else
			child.Icon:SetDesaturated(shouldDesaturate)
		end
	end
end

local function OnShow(child)
	UIParent.SetAlpha(child, child.SCMHidden and 0 or 1)
	if child.SCMGroup and (child.SCMChanged or child.SCMBuffBar) then
		if child.SCMBuffBar and child.SCMSpellID and (not SCM.OptionsFrame or not SCM.OptionsFrame:IsShown()) then
			if Constants.FakeAuras[child.SCMSpellID] then
				child.SCMFakeAuraInstanceID = true
			end

			if child.SCMFakeAuraInstanceID and child.SCMUseFixedDuration then
				child.SCMFixedDuration = GetTime() + Constants.FakeAuras[child.SCMSpellID]
			end
		end

		SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup, child.SCMGlobal, child.viewerFrame and child.viewerFrame.SCMUpdateScope)
	end
end

local function OnHide(child)
	SCM:ClearChildPressOverlay(child)

	local shouldRefresh = child.SCMGroup and (child.SCMChanged or child.SCMBuffBar)
	if shouldRefresh then
		if child.SCMBuffBar then
			if child.SCMFakeAuraInstanceID and child.SCMFixedDuration and GetTime() < child.SCMFixedDuration then
				shouldRefresh = false
			elseif child:IsShown() and child.Cooldown and child.Cooldown:IsVisible() then
				shouldRefresh = false
			else
				child.SCMFixedDuration = nil
				child.SCMFakeAuraInstanceID = nil
			end
		end

		if shouldRefresh then
			SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup, child.SCMGlobal, child.viewerFrame and child.viewerFrame.SCMUpdateScope)
		end
	end

	SCM.StopChildGlows(child)
end

local function OnSetDesaturated(iconTexture)
	local parent = iconTexture:GetParent()
	if not parent.SCMCustom and not iconTexture.SCMSkipUpdate and iconTexture.SCMDesaturated ~= nil then
		iconTexture.SCMSkipUpdate = true
		iconTexture:SetDesaturated(iconTexture.SCMDesaturated)
		iconTexture.SCMSkipUpdate = nil
	end
end

function Icons.SetupIconHooks(child)
	if child.SCMShowHook then
		return
	end
	child.SCMShowHook = true

	child:HookScript("OnShow", OnShow)
	child:HookScript("OnHide", OnHide)

	if child.Icon and child.Icon.SetDesaturated then
		hooksecurefunc(child.Icon, "SetDesaturated", OnSetDesaturated)
	end
end

function Icons.SetupRegularIconHooks(child, options)
	Icons.SetupIconHooks(child)
	Cooldowns.SetupCooldownHooks(child, options)
end

local function SetBuffBarActiveState(child)
	local isActive = child.isActive
	if not issecretvalue(isActive) then
		if isActive then
			OnShow(child)
		else
			OnHide(child)
		end
	end
end

function Icons.SetupBuffBarHooks(child)
	if child.SCMSpellID and Constants.FakeAuras[child.SCMSpellID] then
		child.SCMUseFixedDuration = type(Constants.FakeAuras[child.SCMSpellID]) == "number" and Constants.FakeAuras[child.SCMSpellID]
	else
		child.SCMFakeAuraInstanceID = nil
		child.SCMUseFixedDuration = nil
	end

	if not child.SCMShowHook then
		child.SCMShowHook = true
		hooksecurefunc(child, "OnActiveStateChanged", SetBuffBarActiveState)
		child:HookScript("OnShow", OnShow)
		child:HookScript("OnHide", OnHide)
	end
end

local function GetOrCacheChildren(viewer)
	if not Cache.cachedViewerChildren[viewer] or (viewer:GetNumChildren() ~= #Cache.cachedViewerChildren[viewer]) then
		Cache.cachedViewerChildren[viewer] = { viewer:GetChildren() }
	end

	return Cache.cachedViewerChildren[viewer]
end

--TODO: Yep, this requires a rework
local function GetConfiguredGroupForCategory(childData, categoryIndex)
	if not (childData and childData.source and categoryIndex ~= nil) then
		return
	end

	if categoryIndex == Enum.CooldownViewerCategory.Essential or categoryIndex == Enum.CooldownViewerCategory.Utility then
		if childData.source[Enum.CooldownViewerCategory.EquipSlotEssential] then
			return childData.source[Enum.CooldownViewerCategory.EquipSlotEssential]
		elseif childData.source[Enum.CooldownViewerCategory.SpecAgnosticEssential] then
			return childData.source[Enum.CooldownViewerCategory.SpecAgnosticEssential]
		end
	end

	if categoryIndex == Enum.CooldownViewerCategory.TrackedBuff or categoryIndex == Enum.CooldownViewerCategory.TrackedBar then
		return childData.source[Enum.CooldownViewerCategory.EquipSlotTracked] or childData.source[Enum.CooldownViewerCategory.SpecAgnosticTracked] or childData.source[categoryIndex]
	end

	local pairedCategory = Utils.GetPairedSource(categoryIndex)
	return childData.source[categoryIndex] or (pairedCategory and childData.source[pairedCategory])
end

function Icons.IsViewerLayoutDirty(viewer)
	local children = Cache.cachedViewerChildren[viewer]
	if not children or viewer:GetNumChildren() ~= #children then
		return true
	end

	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	for _, child in ipairs(children) do
		if child.GetCooldownID then
			local cooldownID = child:GetCooldownID()
			if cooldownID ~= child.SCMCooldownID then
				if child.SCMCooldownID then
					return true
				end

				local _, childData = GetSpellConfigByCooldownID(SCM.spellConfig, cooldownID)
				local group = GetConfiguredGroupForCategory(childData, categoryIndex)
				if group and childData.anchorGroup and childData.anchorGroup[group] then
					return true
				end
			end
		end
	end
end

function Icons.CollectScopedAnchorGroups(updateScope, config, viewerUpdateMapping)
	if updateScope == "all" then
		return
	end

	local viewerData = viewerUpdateMapping[updateScope]
	local targetGroups = viewerData and Cache.cachedScopedAnchorGroups[updateScope]
	if not targetGroups then
		return
	end

	wipe(targetGroups)

	local viewer = _G[viewerData.frameName]
	local spellConfig = config and config.spellConfig
	local defaultConfig = SCM.defaultCooldownViewerConfig
	if not (viewer and spellConfig and defaultConfig) then
		return targetGroups
	end

	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	if not categoryIndex then
		return targetGroups
	end

	for _, child in ipairs(GetOrCacheChildren(viewer)) do
		if child.GetCooldownID then
			local cooldownID = child:GetCooldownID()
			local _, childData = GetSpellConfigByCooldownID(SCM.spellConfig, cooldownID)
			local group = GetConfiguredGroupForCategory(childData, categoryIndex)
			if group then
				targetGroups[group] = true
			end
		end
	end

	return targetGroups
end

function Icons.ExpandScopedAnchorGroups(viewer, viewerData, scopedAnchorGroups)
	if not (viewerData and scopedAnchorGroups) or viewerData.isBuffBar then
		return
	end

	local children = GetOrCacheChildren(viewer)
	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	local defaultCooldownIDs = SCM.defaultCooldownViewerConfig.cooldownIDs
	if not defaultCooldownIDs then
		return
	end

	for _, child in ipairs(children) do
		if child.Icon and child.GetCooldownID then
			local oldCooldownID = child.SCMCooldownID
			local oldGroup = child.SCMGroup
			local cooldownID = child:GetCooldownID()
			local _, childData = GetSpellConfigByCooldownID(SCM.spellConfig, cooldownID)

			if not (cooldownID and childData) then
				if oldGroup then
					Cache.cachedAnchorStates[oldGroup].layoutSignature = nil
					scopedAnchorGroups[oldGroup] = true
				end
			else
				local group = GetConfiguredGroupForCategory(childData, categoryIndex)
				local groupConfig = childData.anchorGroup[group]
				if not (group and groupConfig) then
					if oldGroup then
						Cache.cachedAnchorStates[oldGroup].layoutSignature = nil
						scopedAnchorGroups[oldGroup] = true
					end
				elseif oldCooldownID ~= cooldownID or oldGroup ~= group then
					child.SCMCooldownID = nil
					child.SCMState = nil

					if oldGroup then
						Cache.cachedAnchorStates[oldGroup].layoutSignature = nil
						scopedAnchorGroups[oldGroup] = true
					end
					local state = Cache.cachedAnchorStates[group]
					if state then
						state.layoutSignature = nil
					end
					scopedAnchorGroups[group] = true
				end
			end
		end
	end
end

local function ProcessBuffIcon(child, options, refreshOptions, refreshGlowOptions)
	Cooldowns.SetupBuffIconHooks(child, options)
	child.SCMBuffOptions = options

	local isInactive
	if not issecretvalue(child.isActive) then
		isInactive = not child.isActive
	elseif child.SCMCheckCooldownFrame then
		isInactive = not child.Cooldown:IsVisible() and not child.SCMFixedDuration
	else
		isInactive = not child.auraInstanceID or not child.auraDataUnit
	end

	States.SetActiveState(child, not isInactive, true, refreshOptions, refreshGlowOptions)

	local canShowInactive = not SCM.isHideWhenInactiveEnabled
	local stateVisible = child.SCMState.Visibility
	local shouldShow = SCM.simulateBuffs or ((not isInactive or canShowInactive) and stateVisible)
	local wasVisible = child.SCMShouldBeVisible

	child.SCMChanged = child.SCMChanged or wasVisible ~= shouldShow
	Icons.SetChildVisibilityState(child, shouldShow, true)
end

local function ProcessRegularIcon(child, options, refreshOptions, refreshGlowOptions)
	Icons.SetupRegularIconHooks(child, options)
	local isActive = (child.Cooldown and child.Cooldown:GetUseAuraDisplayTime()) or false
	Cooldowns.OverrideRegularAuraCooldown(child.Cooldown, child, options)

	States.SyncState(child, isActive, Cooldowns.GetChildCooldown(child), true, refreshOptions, refreshGlowOptions)

	local shouldShow = child.SCMState.Visibility
	child.SCMChanged = child.SCMChanged or child.SCMShouldBeVisible ~= shouldShow
	Icons.SetChildVisibilityState(child, shouldShow, true)
	child.SCMIconOptions = options
end

local function ProcessBuffBar(child, options, refreshOptions, refreshGlowOptions)
	Icons.SetupBuffBarHooks(child)
	Cooldowns.SetupPandemicHooks(child, options)
	child.SCMBuffBarOptions = options

	local isInactive
	if not issecretvalue(child.isActive) then
		isInactive = not child.isActive
	else
		isInactive = not child.auraInstanceID and not child.SCMFakeAuraInstanceID
	end

	States.SetActiveState(child, not isInactive, true, refreshOptions, refreshGlowOptions)

	local forceShow = options.disableBuffBarHideWhenInactive
	local stateVisible = child.SCMState.Visibility
	local shouldShow = SCM.simulateBuffs or ((not isInactive or forceShow) and stateVisible)
	local wasVisible = child.SCMShouldBeVisible

	child.SCMChanged = child.SCMChanged or wasVisible ~= shouldShow
	Icons.SetChildVisibilityState(child, shouldShow, true)
end

local function ProcessSingleChild(child, validChildren, categoryIndex, isBuffIcon, options, refreshOptions, refreshGlowOptions)
	if not child.Icon then
		return
	end

	local activeScopedAnchorGroups = Cache.activeScopedAnchorGroups
	local cooldownID = child:GetCooldownID() or child.SCMCooldownID
	local categoryConfig = categoryIndex and SCM.defaultCooldownViewerConfig[categoryIndex]
	local info = categoryConfig and (categoryConfig[cooldownID] or SCM.defaultCooldownViewerConfig.cooldownIDs[cooldownID])
	local spellID = info and (info.overrideTooltipSpellID or info.overrideSpellID or info.spellID)

	if info and info.linkedSpellIDs and #info.linkedSpellIDs == 1 then
		child.SCMLinkedSpellID = info.linkedSpellIDs[1]
	end

	local configID, childData = GetSpellConfigByCooldownID(SCM.spellConfig, cooldownID)
	if not (cooldownID and info and childData) then
		if child.SCMConfig then
			Utils.ResetChildSCMState(child)
		end

		if not child.SCMHidden then
			Icons.SetChildVisibilityState(child, false, true)
		end
		return
	end

	child.SCMSpellID = spellID

	local group = GetConfiguredGroupForCategory(childData, categoryIndex)
	local groupConfig = childData.anchorGroup and childData.anchorGroup[group]
	if not group or not groupConfig then
		if child.SCMConfig then
			Utils.ResetChildSCMState(child)
		end

		if not child.SCMHidden then
			Icons.SetChildVisibilityState(child, false, true)
		end
		return
	end

	AddChildToGroup(validChildren, group, child)

	child.SCMChanged = child.SCMChanged or (not child.SCMConfig or child.SCMConfig ~= groupConfig) or (not child.SCMCooldownID or child.SCMCooldownID ~= cooldownID)
	child.SCMConfig = groupConfig
	child.SCMOrder = groupConfig.order
	child.SCMCooldownID = cooldownID
	child.SCMConfigID = configID
	child.SCMGroup = group
	child.SCMSpellCategoryID = info.spellCategoryID
	child.SCMEquipSlot = info.equipSlot

	if activeScopedAnchorGroups and not activeScopedAnchorGroups[group] and (child.SCMBuffOptions or child.SCMIconOptions) then
		return
	end

	if isBuffIcon then
		ProcessBuffIcon(child, options, refreshOptions, refreshGlowOptions)
	else
		ProcessRegularIcon(child, options, refreshOptions, refreshGlowOptions)
	end

	if not InCombatLockdown() then
		RegisterAttributeDriver(child, "state-visibility", SCM:GetVisibilityConditions(SCM.db.profile.options))
	end
end

local function ProcessSingleBuffBarChild(child, validChildren, categoryIndex, options, refreshOptions, refreshGlowOptions)
	if not child.GetCooldownID then
		return
	end

	local activeScopedAnchorGroups = Cache.activeScopedAnchorGroups
	local cooldownID = child:GetCooldownID() or child.SCMCooldownID
	local categoryConfig = categoryIndex and SCM.defaultCooldownViewerConfig[categoryIndex]
	local info = categoryConfig and (categoryConfig[cooldownID] or SCM.defaultCooldownViewerConfig.cooldownIDs[cooldownID])
	local spellID = info and (info.overrideSpellID or info.spellID)
	if info and info.linkedSpellIDs and #info.linkedSpellIDs == 1 then
		child.SCMLinkedSpellID = info.linkedSpellIDs[1]
	end

	child.SCMSpellID = spellID

	local configID, childData = GetSpellConfigByCooldownID(SCM.spellConfig, cooldownID)
	if not (cooldownID and spellID and childData) then
		if child.SCMConfig then
			Utils.ResetChildSCMState(child)
		end
		if not child.SCMHidden then
			Icons.SetChildVisibilityState(child, false, true)
		end
		return
	end

	local group = childData.source[TRACKED_BAR_CATEGORY]
	local groupConfig = childData.anchorGroup and childData.anchorGroup[group]
	if not (group and groupConfig) then
		if child.SCMConfig then
			Utils.ResetChildSCMState(child)
		end
		if not child.SCMHidden then
			Icons.SetChildVisibilityState(child, false, true)
		end
		return
	end

	AddChildToGroup(validChildren, group, child)

	child.SCMChanged = child.SCMChanged or (not child.SCMConfig or child.SCMConfig ~= groupConfig) or (not child.SCMCooldownID or child.SCMCooldownID ~= cooldownID)
	child.SCMConfig = groupConfig
	child.SCMOrder = groupConfig.order
	child.SCMCooldownID = cooldownID
	child.SCMConfigID = configID
	child.SCMGroup = group
	child.SCMBuffBar = true

	if activeScopedAnchorGroups and not activeScopedAnchorGroups[group] then
		return
	end

	ProcessBuffBar(child, options, refreshOptions, refreshGlowOptions)
end

function Icons.ProcessChildren(viewer, validChildren, viewerData, refreshOptions, refreshGlowOptions)
	if not (viewer and viewerData) then
		return
	end

	local children = GetOrCacheChildren(viewer)
	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	local options = SCM.db.profile.options
	viewer.SCMUpdateScope = viewerData.updateScope

	if viewerData.isBuffBar then
		for _, child in ipairs(children) do
			ProcessSingleBuffBarChild(child, validChildren, categoryIndex, options, refreshOptions, refreshGlowOptions)
		end
		return
	end

	local isBuffIcon = viewerData.isBuffIcon
	for _, child in ipairs(children) do
		ProcessSingleChild(child, validChildren, categoryIndex, isBuffIcon, options, refreshOptions, refreshGlowOptions)
	end
end
