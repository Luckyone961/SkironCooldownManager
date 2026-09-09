local addonName, SCM = ...

local Cache = SCM.Cache
local Utils = SCM.Utils
local ToGlobalGroup = Utils.ToGlobalGroup
local ToBuffBarGroup = Utils.ToBuffBarGroup
local AddChildToGroup = Utils.AddChildToGroup
local CustomIcons = SCM.CustomIcons

local Icons = SCM.Icons
local Utils = SCM.Utils
local CDM = SCM.CDM

local UPDATE_SCOPE = {
	ALL = "all",
	ESSENTIAL = "essential",
	UTILITY = "utility",
	ESSENTIAL_UTILITY = "essentialUtility",
	BUFF = "buff",
	BUFF_BAR = "buffBar",
}
CDM.UPDATE_SCOPE = UPDATE_SCOPE

local VIEWER_UPDATE_MAPPING = {
	[UPDATE_SCOPE.ESSENTIAL] = {
		frameName = "EssentialCooldownViewer",
		updateScope = UPDATE_SCOPE.ESSENTIAL,
		isBuffIcon = false,
	},
	[UPDATE_SCOPE.UTILITY] = {
		frameName = "UtilityCooldownViewer",
		updateScope = UPDATE_SCOPE.UTILITY,
		isBuffIcon = false,
	},
	[UPDATE_SCOPE.BUFF] = {
		frameName = "BuffIconCooldownViewer",
		updateScope = UPDATE_SCOPE.BUFF,
		isBuffIcon = true,
	},
	[UPDATE_SCOPE.BUFF_BAR] = {
		frameName = "BuffBarCooldownViewer",
		updateScope = UPDATE_SCOPE.BUFF_BAR,
		isBuffBar = true,
	},
}

local VIEWER_PROCESS_ORDER = {
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.ESSENTIAL],
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.UTILITY],
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.BUFF],
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.BUFF_BAR],
}

local VIEWER_PROCESS_ORDER_BY_SCOPE = {
	[UPDATE_SCOPE.ALL] = VIEWER_PROCESS_ORDER,
	[UPDATE_SCOPE.ESSENTIAL] = { VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.ESSENTIAL] },
	[UPDATE_SCOPE.UTILITY] = { VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.UTILITY] },
	[UPDATE_SCOPE.BUFF] = { VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.BUFF] },
	[UPDATE_SCOPE.BUFF_BAR] = { VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.BUFF_BAR] },
}

function SCM:Debug(...)
	local options = self.db.profile.options
	if not options.debug then
		return
	end

	local debugGroup = tonumber(options.debugGroup)
	if debugGroup and debugGroup > 0 then
		local matchedGroup = false
		local numArgs = select("#", ...)
		for index = 1, numArgs - 1 do
			if (select(index, ...)) == "group" and tonumber((select(index + 1, ...))) == debugGroup then
				matchedGroup = true
				break
			end
		end

		if not matchedGroup then
			return
		end
	end

	print(addonName, ...)
end

local function IsScopedGroup(scopedAnchorGroups, group)
	return not scopedAnchorGroups or scopedAnchorGroups[group]
end

local function IsScopedAnchorGroupAllowed(group, isGlobal)
	local effectiveGroup = isGlobal and ToGlobalGroup(group) or group
	return IsScopedGroup(Cache.activeScopedAnchorGroups, effectiveGroup)
end
CDM.IsScopedAnchorGroupAllowed = IsScopedAnchorGroupAllowed

local function AddChildToScopedGroup(validChildren, group, child, isGlobal)
	if IsScopedAnchorGroupAllowed(group, isGlobal) then
		AddChildToGroup(validChildren, group, child, isGlobal)
	end
end
CDM.AddChildToScopedGroup = AddChildToScopedGroup

local function CollectScopedAnchorGroups(updateScope, config)
	if updateScope ~= UPDATE_SCOPE.ESSENTIAL_UTILITY then
		return Icons.CollectScopedAnchorGroups(updateScope, config, VIEWER_UPDATE_MAPPING)
	end

	local targetGroups = Icons.CollectScopedAnchorGroups(UPDATE_SCOPE.ESSENTIAL, config, VIEWER_UPDATE_MAPPING)

	for group in pairs(Icons.CollectScopedAnchorGroups(UPDATE_SCOPE.UTILITY, config, VIEWER_UPDATE_MAPPING)) do
		targetGroups[group] = true
	end

	return targetGroups
end

local function GetAnchorState(group)
	local state = Cache.cachedAnchorStates[group]
	if not state then
		state = { rows = {} }
		Cache.cachedAnchorStates[group] = state
	end

	return state
end

local function UpdateAnchorLinks(config)
	local anchorLinks = Cache.cachedAnchorLinks
	if not Cache.cachedAnchorLinksDirty then
		return anchorLinks
	end

	for _, linkedGroups in pairs(anchorLinks) do
		wipe(linkedGroups)
	end

	for _, state in pairs(Cache.cachedAnchorStates) do
		state.parentGroup = nil
	end

	local anchorConfigList = config and config.anchorConfig
	if anchorConfigList then
		for group = 1, #anchorConfigList do
			local anchorConfig = Utils.GetAnchorConfigForGroup(config, group)
			local parentGroup = Utils.ParseAnchorString(anchorConfig and anchorConfig.anchor and anchorConfig.anchor[2])
			local state = GetAnchorState(group)
			state.parentGroup = parentGroup
			if parentGroup then
				local linkedGroups = anchorLinks[parentGroup]
				if not linkedGroups then
					linkedGroups = {}
					anchorLinks[parentGroup] = linkedGroups
				end
				linkedGroups[group] = true
			end
		end
	end

	local globalAnchorConfig = SCM.globalAnchorConfig
	if globalAnchorConfig then
		for index = 1, #globalAnchorConfig do
			local anchorConfig = globalAnchorConfig[index]
			local group = ToGlobalGroup(index)
			local parentGroup = Utils.ParseAnchorString(anchorConfig and anchorConfig.anchor and anchorConfig.anchor[2])
			local state = GetAnchorState(group)
			state.parentGroup = parentGroup
			if parentGroup then
				local linkedGroups = anchorLinks[parentGroup]
				if not linkedGroups then
					linkedGroups = {}
					anchorLinks[parentGroup] = linkedGroups
				end
				linkedGroups[group] = true
			end
		end
	end

	local buffBarsAnchorConfig = config and config.buffBarsAnchorConfig
	if buffBarsAnchorConfig then
		for index = 1, #buffBarsAnchorConfig do
			local group = ToBuffBarGroup(index)
			local anchorConfig = Utils.GetAnchorConfigForGroup(config, index, nil, true)
			local parentGroup = Utils.ParseAnchorString(anchorConfig and anchorConfig.anchor and anchorConfig.anchor[2])
			local state = GetAnchorState(group)
			state.parentGroup = parentGroup
			if parentGroup then
				local linkedGroups = anchorLinks[parentGroup]
				if not linkedGroups then
					linkedGroups = {}
					anchorLinks[parentGroup] = linkedGroups
				end
				linkedGroups[group] = true
			end
		end
	end

	Cache.cachedAnchorLinksDirty = false
	return anchorLinks
end

local function LayoutAnchorGroup(group, visibleChildren, anchorConfig, options, changedGroups, resetSize, allowLayoutSkip)
	return CDM.LayoutAnchorGroup(group, visibleChildren, anchorConfig, options, changedGroups, resetSize, allowLayoutSkip)
end

local function LayoutEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups, changedGroups, options)
	if not IsScopedGroup(scopedAnchorGroups, group) or Cache.cachedCooldownFrameTbl[group] then
		return
	end

	local emptyChildren = Cache.cachedAnchorChildren[group]
	if not emptyChildren then
		emptyChildren = {}
		Cache.cachedAnchorChildren[group] = emptyChildren
	else
		wipe(emptyChildren)
	end

	LayoutAnchorGroup(group, emptyChildren, anchorConfig, options, changedGroups, true)
end

local function UpdateAnchorChain(changedGroups, config)
	if not InCombatLockdown() or not next(changedGroups) then
		return
	end

	local anchorLinks = UpdateAnchorLinks(config)
	local visitedGroups = SCM:AcquireScopedGroupCache()
	local queue = Cache.cachedAnchorQueue
	local queueIndex = 1

	wipe(queue)

	for group in pairs(changedGroups) do
		local linkedGroups = anchorLinks[group]
		if linkedGroups then
			for linkedGroup in pairs(linkedGroups) do
				queue[#queue + 1] = linkedGroup
			end
		end
	end

	while queueIndex <= #queue do
		local group = queue[queueIndex]
		queueIndex = queueIndex + 1

		if not visitedGroups[group] then
			visitedGroups[group] = true
			if SCM:UpdateAnchorOffset(group) then
				local linkedGroups = anchorLinks[group]
				if linkedGroups then
					for linkedGroup in pairs(linkedGroups) do
						queue[#queue + 1] = linkedGroup
					end
				end
			end
		end
	end

	wipe(queue)
	SCM:ReleaseScopedGroupCache(visitedGroups)
end

local layoutUpdateScheduled, pendingLayoutUpdate, pendingRefreshOptions, pendingRefreshGlowOptions

local function OrderCDManagerSpells(updateScope, scopedAnchorGroupsOverride, refreshOptions, refreshGlowOptions)
	if layoutUpdateScheduled then
		pendingLayoutUpdate = true
		pendingRefreshOptions = pendingRefreshOptions or refreshOptions
		pendingRefreshGlowOptions = pendingRefreshGlowOptions or refreshGlowOptions
		return
	end
	layoutUpdateScheduled = true
	C_Timer.After(0, function()
		layoutUpdateScheduled = nil
		if pendingLayoutUpdate then
			local options, glows = pendingRefreshOptions, pendingRefreshGlowOptions
			pendingLayoutUpdate, pendingRefreshOptions, pendingRefreshGlowOptions = nil, nil, nil
			OrderCDManagerSpells(UPDATE_SCOPE.ALL, nil, options, glows)
		end
	end)
	updateScope = updateScope or UPDATE_SCOPE.ALL
	CDM.isLayoutInProgress = true

	Cache.cachedViewerScale = 1

	wipe(Cache.cachedChildrenTbl)
	wipe(Cache.cachedCooldownFrameTbl)

	local config = SCM.currentConfig
	local isFullAllUpdate = updateScope == UPDATE_SCOPE.ALL and not scopedAnchorGroupsOverride
	local isFullBuffBarUpdate = updateScope == UPDATE_SCOPE.BUFF_BAR and not scopedAnchorGroupsOverride
	local scopedAnchorGroups = scopedAnchorGroupsOverride
	if not scopedAnchorGroups and not isFullBuffBarUpdate then
		scopedAnchorGroups = CollectScopedAnchorGroups(updateScope, config)
	end
	local options = SCM.db.profile.options
	local changedGroups = SCM:AcquireScopedGroupCache()
	Cache.activeScopedAnchorGroups = scopedAnchorGroups

	UpdateAnchorLinks(config)

	local viewerProcessOrder = (scopedAnchorGroups and updateScope ~= UPDATE_SCOPE.BUFF_BAR) and VIEWER_PROCESS_ORDER or VIEWER_PROCESS_ORDER_BY_SCOPE[updateScope] or VIEWER_PROCESS_ORDER
	if scopedAnchorGroups and updateScope ~= UPDATE_SCOPE.BUFF_BAR then
		for i = 1, #viewerProcessOrder do
			local viewerData = viewerProcessOrder[i]
			Icons.ExpandScopedAnchorGroups(_G[viewerData.frameName], viewerData, scopedAnchorGroups)
		end
	end

	for i = 1, #viewerProcessOrder do
		local viewerData = viewerProcessOrder[i]
		Icons.ProcessChildren(_G[viewerData.frameName], Cache.cachedChildrenTbl, viewerData, refreshOptions, refreshGlowOptions)
	end

	for group, children in pairs(Cache.cachedChildrenTbl) do
		if IsScopedGroup(scopedAnchorGroups, group) then
			local visibleChildren = GetOrCreateTableEntry(Cache.cachedVisibleChildren, group)
			wipe(visibleChildren)
			for _, child in ipairs(children) do
				if child.SCMShouldBeVisible then
					visibleChildren[#visibleChildren + 1] = child
				end
			end

			Cache.cachedCooldownFrameTbl[group] = visibleChildren
		end
	end

	if updateScope ~= UPDATE_SCOPE.BUFF_BAR then
		if scopedAnchorGroups then
			for group in pairs(scopedAnchorGroups) do
				CustomIcons.ProcessGroupIcons(group, Cache.cachedCooldownFrameTbl, refreshOptions, refreshGlowOptions)
			end
		else
			CustomIcons.ProcessGroupIcons(nil, Cache.cachedCooldownFrameTbl, refreshOptions, refreshGlowOptions)
		end
	end

	local allowLayoutSkip = scopedAnchorGroups and updateScope ~= UPDATE_SCOPE.BUFF_BAR
	wipe(Cache.cachedVisitedAnchorGroups)
	for group, visibleChildren in pairs(Cache.cachedCooldownFrameTbl) do
		LayoutAnchorGroup(group, visibleChildren, Utils.GetAnchorConfigForLayoutGroup(config, group), options, changedGroups, nil, allowLayoutSkip)
	end

	if not isFullBuffBarUpdate then
		for _, children in pairs(Cache.cachedChildrenTbl) do
			for _, child in ipairs(children) do
				local appliedVisibility = child.SCMShouldBeVisible and not child.SCMLayoutLimited
				local appliedLayoutLimited = child.SCMLayoutLimited and true or false
				if child.SCMAppliedVisibility ~= appliedVisibility or child.SCMAppliedLayoutLimited ~= appliedLayoutLimited then
					Icons.SetChildVisibilityState(child, child.SCMShouldBeVisible, true)
				end
			end
		end
	end

	if updateScope ~= UPDATE_SCOPE.BUFF_BAR then
		if config.anchorConfig then
			for group = 1, #config.anchorConfig do
				if not Cache.cachedVisitedAnchorGroups[group] then
					local anchorConfig = Utils.GetAnchorConfigForGroup(config, group)
					Cache.cachedVisitedAnchorGroups[group] = true
					LayoutEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups, changedGroups, options)
				end
			end
		end

		if SCM.globalAnchorConfig then
			for index = 1, #SCM.globalAnchorConfig do
				local anchorConfig = SCM.globalAnchorConfig[index]
				local group = ToGlobalGroup(index)
				if not Cache.cachedVisitedAnchorGroups[group] then
					Cache.cachedVisitedAnchorGroups[group] = true
					LayoutEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups, changedGroups, options)
				end
			end
		end
	end

	if updateScope == UPDATE_SCOPE.ALL or updateScope == UPDATE_SCOPE.BUFF_BAR then
		if config.buffBarsAnchorConfig then
			for index = 1, #config.buffBarsAnchorConfig do
				local anchorConfig = Utils.GetAnchorConfigForGroup(config, index, nil, true)
				local group = ToBuffBarGroup(index)
				if not Cache.cachedVisitedAnchorGroups[group] then
					Cache.cachedVisitedAnchorGroups[group] = true
					LayoutEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups, changedGroups, options)
				end
			end
		end
	end

	if isFullAllUpdate or isFullBuffBarUpdate then
		SCM:SkinBuffBars()
	end

	UpdateAnchorChain(changedGroups, config)

	SCM:ReleaseScopedGroupCache(changedGroups)
	Cache.activeScopedAnchorGroups = nil
	CDM.isLayoutInProgress = nil

	if SCM.SCMRefreshMatchedBuffBarWidths and not InCombatLockdown() then
		SCM.SCMRefreshMatchedBuffBarWidths = nil
		OrderCDManagerSpells(UPDATE_SCOPE.BUFF_BAR)
	end
end

CDM.OrderSpells = OrderCDManagerSpells
