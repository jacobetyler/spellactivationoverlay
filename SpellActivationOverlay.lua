local AddonName, SAO = ...

local sizeScale = 0.8;
local longSide = 256 * sizeScale;
local shortSide = 128 * sizeScale;
local combatOverlayFactor = 2;
local useTimer = true;

function SpellActivationOverlay_OnLoad(self)
	SAO.Frame = self;
	SAO.ShowAllOverlays = SpellActivationOverlay_ShowAllOverlays;
	SAO.HideOverlays = SpellActivationOverlay_HideOverlays;
	SAO.HideAllOverlays = SpellActivationOverlay_HideAllOverlays;
	SAO.SetOverlayTimer = SpellActivationOverlay_SetAllOverlayTimers;

	self.overlaysInUse = {};
	self.unusedOverlays = {};
	self.combatOnlyOverlays = {};

	self.offset = 0;
	self.scale = 1;
	SpellActivationOverlay_OnChangeGeometry(self);

	self.useTimer = true;
	SpellActivationOverlay_OnChangeTimerVisibility(self);

	local className, classFile, classId = UnitClass("player");
	local class = SAO.Class[classFile];
	if class then
		class.Intrinsics = { className, classFile, classId };
		SAO.CurrentClass = class;

		-- Keys of the class other than "Intrinsics", "Register" and "LoadOptions" are expected to be event names
		for key, _ in pairs(class) do
			if (key ~= "Intrinsics" and key ~= "Register" and key ~= "LoadOptions") then
				self:RegisterEvent(key);
			end
		end
	else
		print(WrapTextInColorCode("Class unknown or not converted yet: ", "FFFF0000")..select(1, UnitClass("player")));
	end

	-- These events do not exist in Classic Era, BC Classic, nor Wrath Classic
--	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW");
--	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE");
--	self:RegisterUnitEvent("UNIT_AURA", "player");
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
	self:RegisterEvent("SPELL_UPDATE_USABLE");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("SPELLS_CHANGED");
	self:RegisterEvent("LEARNED_SPELL_IN_TAB");
	self:RegisterEvent("LOADING_SCREEN_DISABLED");
end

function SpellActivationOverlay_OnChangeGeometry(self)
	-- Ignores self.scale because it should be used to scale alerts, not core
	local newSize = 256 * sizeScale + self.offset;
	-- Resize the parent instead of self because the parent is the one bearing the Size element
	self:GetParent():SetSize(newSize, newSize);

	-- Resize existing overlays and prepare variables for future overlays
	longSide = 256 * sizeScale * self.scale;
	shortSide = 128 * sizeScale * self.scale;
	for _, overlayList in pairs(self.overlaysInUse) do
		for i=1, #overlayList do
			local overlay = overlayList[i];
			overlay:SetGeometry(longSide, shortSide);
		end
	end

	-- Resize offsets for overlays that offset a mask when out of combat
	for _, overlay in ipairs(self.combatOnlyOverlays) do
		if overlay.combat.animOut:IsPlaying() then
			-- Calling the 'Play' custom function for animOut will setup its offset
			SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
		end
	end
end

function SpellActivationOverlay_OnChangeTimerVisibility(self)
	useTimer = self.useTimer;
	for _, overlayList in pairs(self.overlaysInUse) do
		for i=1, #overlayList do
			local overlay = overlayList[i];
			overlay.mask:SetShown(useTimer);
		end
	end
end

function SpellActivationOverlay_OnEvent(self, event, ...)
--[[ 
	Dead code because these events do not exist in Classic Era, BC Classic, nor Wrath Classic
	Also, the "displaySpellActivationOverlays" console variable does not exist
]]
--[[
	if ( event == "SPELL_ACTIVATION_OVERLAY_SHOW" ) then
		local spellID, texture, positions, scale, r, g, b = ...;
		if ( GetCVarBool("displaySpellActivationOverlays") ) then 
			SpellActivationOverlay_ShowAllOverlays(self, spellID, texture, positions, scale, r, g, b, true)
		end
	elseif ( event == "SPELL_ACTIVATION_OVERLAY_HIDE" ) then
		local spellID = ...;
		if spellID then
			SpellActivationOverlay_HideOverlays(self, spellID);
		else
			SpellActivationOverlay_HideAllOverlays(self);
		end
	end]]
	if ( not self.disableDimOutOfCombat ) then
		if ( event == "PLAYER_REGEN_DISABLED" ) then
			self.combatAnimOut:Stop();	--In case we're in the process of animating this out.
			self.combatAnimIn:Play();
			for _, overlay in ipairs(self.combatOnlyOverlays) do
				overlay.combat.animOut:Stop();
--				overlay.combat.animIn:Play();
			end
		elseif ( event == "PLAYER_REGEN_ENABLED" ) then
			self.combatAnimIn:Stop();	--In case we're in the process of animating this out.
			self.combatAnimOut:Play();
			for _, overlay in ipairs(self.combatOnlyOverlays) do
--				overlay.combat.animIn:Stop();
				SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
			end
		end
	end
	if ( event ) then
		SAO:OnEvent(event, ...);
	end
end

local complexLocationTable = {
	["RIGHT (FLIPPED)"] = {
		RIGHT = {	hFlip = true },
	},
	["BOTTOM (FLIPPED)"] = {
		BOTTOM = { vFlip = true },
	},
	["LEFT + RIGHT (FLIPPED)"] = {
		LEFT = {},
		RIGHT = { hFlip = true },
	},
	["TOP + BOTTOM (FLIPPED)"] = {
		TOP = {},
		BOTTOM = { vFlip = true },
	},
	["LEFT (CW)"] = {
		LEFT = { cw = 1 },
	},
	["LEFT (CCW)"] = {
		LEFT = { cw = -1 },
	},
	["RIGHT (CW)"] = {
		RIGHT = { cw = 1 },
	},
	["RIGHT (CCW)"] = {
		RIGHT = { cw = -1 },
	},
	["TOP (CW)"] = {
		TOP = { cw = 1 },
	},
	["TOP (CCW)"] = {
		TOP = { cw = -1 },
	},
	["BOTTOM (CW)"] = {
		BOTTOM = { cw = 1 },
	},
	["BOTTOM (CCW)"] = {
		BOTTOM = { cw = -1 },
	},
}

function SpellActivationOverlay_ShowAllOverlays(self, spellID, texturePath, positions, scale, r, g, b, autoPulse, forcePulsePlay, endTime, combatOnly)
	positions = strupper(positions);
	if ( complexLocationTable[positions] ) then
		for location, info in pairs(complexLocationTable[positions]) do
			SpellActivationOverlay_ShowOverlay(self, spellID, texturePath, location, scale, r, g, b, info.vFlip, info.hFlip, info.cw, autoPulse, forcePulsePlay, endTime, combatOnly);
		end
	else
		SpellActivationOverlay_ShowOverlay(self, spellID, texturePath, positions, scale, r, g, b, false, false, 0, autoPulse, forcePulsePlay, endTime, combatOnly);
	end
end

function SpellActivationOverlay_ShowOverlay(self, spellID, texturePath, position, scale, r, g, b, vFlip, hFlip, cw, autoPulse, forcePulsePlay, endTime, combatOnly)
	SAO:Debug("main - Starting Overlay at location "..position.." for spell ID "..spellID.." "..(GetSpellInfo(spellID) or "")..(endTime and (" for "..math.floor((type(endTime) == 'number' and endTime or endTime.endTime)-GetTime()+0.5).." secs") or ""));
	if (SpellActivationOverlayDB and SpellActivationOverlayDB.alert and not SpellActivationOverlayDB.alert.enabled) then
		-- Last chance to quit displaying the overlay, if the main overlay flag is disabled
		return;
	end

	local overlay = SpellActivationOverlay_GetOverlay(self, spellID, position);
	overlay.spellID = spellID;
	overlay.position = position;
	
	local texLeft, texRight, texTop, texBottom = 0, 1, 0, 1;
	if ( vFlip ) then
		texTop, texBottom = 1, 0;
	end
	if ( hFlip ) then
		texLeft, texRight = 1, 0;
	end
	if ( not cw or cw == 0 ) then
		overlay.texture:SetTexCoord(texLeft, texRight, texTop, texBottom);
--		overlay.texture:SetTexCoord(texLeft,texTop, texLeft,texBottom, texRight,texTop, texRight,texBottom); -- Written for reference
	elseif ( cw > 0 ) then
		overlay.texture:SetTexCoord(texLeft,texBottom, texRight,texBottom, texLeft,texTop, texRight,texTop);
	else
		overlay.texture:SetTexCoord(texRight,texTop, texLeft,texTop, texRight,texBottom, texLeft,texBottom);
	end

	overlay.SetGeometry = function(self, longSide, shortSide)
		local parent = self:GetParent();

		self:ClearAllPoints();

		local width, height;
		if ( position == "CENTER" ) then
			width, height = longSide, longSide;
			self:SetPoint("CENTER", parent, "CENTER", 0, 0);
		elseif ( position == "LEFT" ) then
			width, height = shortSide, longSide;
			self:SetPoint("RIGHT", parent, "LEFT", 0, 0);
		elseif ( position == "RIGHT" ) then
			width, height = shortSide, longSide;
			self:SetPoint("LEFT", parent, "RIGHT", 0, 0);
		elseif ( position == "TOP" ) then
			width, height = longSide, shortSide;
			self:SetPoint("BOTTOM", parent, "TOP");
		elseif ( position == "BOTTOM" ) then
			width, height = longSide, shortSide;
			self:SetPoint("TOP", parent, "BOTTOM");
		elseif ( position == "TOPRIGHT" ) then
			width, height = shortSide, shortSide;
			self:SetPoint("BOTTOMLEFT", parent, "TOPRIGHT", 0, 0);
		elseif ( position == "TOPLEFT" ) then
			width, height = shortSide, shortSide;
			self:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", 0, 0);
		elseif ( position == "BOTTOMRIGHT" ) then
			width, height = shortSide, shortSide;
			self:SetPoint("TOPLEFT", parent, "BOTTOMRIGHT", 0, 0);
		elseif ( position == "BOTTOMLEFT" ) then
			width, height = shortSide, shortSide;
			self:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", 0, 0);
		else
			--GMError("Unknown SpellActivationOverlay position: "..tostring(position));
			return;
		end

		self:SetSize(width * scale, height * scale);
		self.mask:SetSize(longSide * scale, longSide * scale);
		self.combat:SetSize(longSide * scale * combatOverlayFactor, longSide * scale * combatOverlayFactor);
		-- Combat mask texture is bigger, to get an 'eye of the storm' effect at start
	end
	overlay:SetGeometry(longSide, shortSide);
	
	overlay.texture:SetTexture(texturePath);
	overlay.texture:SetVertexColor(r / 255, g / 255, b / 255);
	
	overlay.animOut:Stop();	--In case we're in the process of animating this out.
	PlaySound(SOUNDKIT.UI_POWER_AURA_GENERIC);
	overlay:Show();
	if ( forcePulsePlay ) then
		overlay.pulse:Play();
	end
	overlay.pulse.autoPlay = autoPulse;

	overlay.mask:SetShown(useTimer);

	SpellActivationOverlay_SetOverlayTimer(self, overlay, endTime);

	overlay.combatOnly = combatOnly;
	if ( combatOnly ) then
		tDeleteItem(self.combatOnlyOverlays, overlay); -- In case it was already in the list
		tinsert(self.combatOnlyOverlays, overlay);
		if ( InCombatLockdown() ) then
			overlay.combat.animOut:Stop();
--			overlay.combat.animIn:Play();
		else
--			overlay.combat.animIn:Stop();
			SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
		end
	else
		tDeleteItem(self.combatOnlyOverlays, overlay);
	end

	if ( not self.disableDimOutOfCombat and not InCombatLockdown() ) then
		-- Simulate a short, fake in-combat mode, to make the spell alert more visible
		self.combatAnimOut:Stop();
		self.combatAnimIn:Play();
		if ( combatOnly ) then
			overlay.combat.animOut:Stop();
--			overlay.combat.animIn:Play();
		end
	end
end

function SpellActivationOverlay_GetOverlay(self, spellID, position)
	local overlayList = self.overlaysInUse[spellID];
	local overlay;
	if ( overlayList ) then
		for i=1, #overlayList do
			if ( overlayList[i].position == position ) then
				overlay = overlayList[i];
			end
		end
	end
	
	if ( not overlay ) then
		overlay = SpellActivationOverlay_GetUnusedOverlay(self);
		if ( overlayList ) then
			tinsert(overlayList, overlay);
		else
			self.overlaysInUse[spellID] = { overlay };
		end
	end
	
	return overlay;
end

function SpellActivationOverlay_HideOverlays(self, spellID)
	local overlayList = self.overlaysInUse[spellID];
	if ( overlayList ) then
		for i=1, #overlayList do
			local overlay = overlayList[i];
			SAO:Debug("main - Hiding Overlay at location "..overlay.position.." for spell ID "..overlay.spellID.." "..(GetSpellInfo(overlay.spellID) or ""));
			overlay.pulse:Pause();
			overlay.animOut:Play();
		end
	end
end

function SpellActivationOverlay_HideAllOverlays(self)
	for spellID, overlayList in pairs(self.overlaysInUse) do
		SpellActivationOverlay_HideOverlays(self, spellID);
	end
end

function SpellActivationOverlay_SetAllOverlayTimers(self, spellID, endTime)
	if ( not endTime ) then
		return
	end

	local overlayList = self.overlaysInUse[spellID];
	if ( overlayList ) then
		for i=1, #overlayList do
			local overlay = overlayList[i];
			SpellActivationOverlay_SetOverlayTimer(self, overlay, endTime);
		end
	end
end

function SpellActivationOverlay_SetOverlayTimer(self, overlay, endTime)
	local startTime = type(endTime) == 'table' and endTime.startTime or nil;
	endTime = type(endTime) == 'table' and endTime.endTime or endTime;
	if ( not endTime or endTime <= GetTime() ) then
		return; -- endTime not set or "too soon"
	end

	local maxLag = 0.25; -- Estimated maximum lag, used to compare existing endTime with new endTime
	if ( type(overlay.endTime) == 'number' and SAO:IsTimeAlmostEqual(endTime, overlay.endTime, maxLag) ) then
		return; -- Overlay already has similar endTime: assume this is the same timer
	end
	overlay.endTime = endTime;

	SAO:Debug("main - Setting Overlay Timer at location "..overlay.position.." for spell ID "..overlay.spellID.." "..(GetSpellInfo(overlay.spellID) or "")..(endTime and (" for "..math.floor(endTime-GetTime()+0.5).." secs") or " without time"));

	local offset = startTime and (GetTime() - startTime) or 0;
	local duration = endTime - GetTime() + offset - 0.1; -- Subtract 0.1 to account for final shrink
	local position = overlay.position;
	local isHorizontal = position:sub(1, 3) == "TOP" or position:sub(1, 6) == "BOTTOM";
	local isVertical = position:sub(#position-3) == "LEFT" or position:sub(#position-4) == "RIGHT";
	if ( isHorizontal and isVertical ) then
		-- Corner
		overlay.mask.timeoutXY.scaleXY:SetDuration(duration);
		overlay.mask.timeoutXY:Stop();
		overlay.mask.timeoutXY:Play(false, offset);
	elseif ( isHorizontal ) then
		-- Top/Bottom
		overlay.mask.timeoutX.scaleX:SetDuration(duration);
		overlay.mask.timeoutX:Stop();
		overlay.mask.timeoutX:Play(false, offset);
	elseif ( isVertical ) then
		-- Left/Right
		overlay.mask.timeoutY.scaleY:SetDuration(duration);
		overlay.mask.timeoutY:Stop();
		overlay.mask.timeoutY:Play(false, offset);
	end
end

function SpellActivationOverlay_GetUnusedOverlay(self)
	local overlay = tremove(self.unusedOverlays, #self.unusedOverlays);
	if ( not overlay ) then
		overlay = SpellActivationOverlay_CreateOverlay(self);
	end
	return overlay;
end

function SpellActivationOverlay_CreateOverlay(self)
	return CreateFrame("Frame", nil, self, "SpellActivationOverlayTemplate");
end

function SpellActivationOverlayTexture_OnShow(self)
	self.animIn:Play();
end

function SpellActivationOverlayTexture_TerminateOverlay(overlay)
	SAO:Debug("main - Terminating Overlay at location "..overlay.position.." for spell ID "..overlay.spellID.." "..(GetSpellInfo(overlay.spellID) or ""));
	local overlayParent = overlay:GetParent();

	-- No longer need to pulse
	overlay.pulse:Stop();

	-- Stop animations that may re-trigger terminate when they finish
	overlay.animOut:Stop();
	overlay.mask.timeoutXY:Stop();
	overlay.mask.timeoutX:Stop();
	overlay.mask.timeoutY:Stop();
--	overlay.combat.animIn:Stop();
	overlay.combat.animOut:Stop();

	-- Hide the overlay and make it available again in the pool for future use
	overlay.mask:SetScale(1); -- Reset scale, in case a previous animation shrank it to 0.01
	overlay.endTime = nil; -- Reset endTime, to avoid excessive optimizations when re-using this overlay
	overlay:Hide();
	tDeleteItem(overlayParent.overlaysInUse[overlay.spellID], overlay);
	tinsert(overlayParent.unusedOverlays, overlay);
end

function SpellActivationOverlayFrame_OnTimeoutFinished(anim)
	local mask = anim:GetParent();
	local overlay = mask:GetParent();
	mask:SetScale(0.01); -- Shrink mask scale to 0.01 to avoid glitches with final animation below
	-- Start the fade-out animation, which will eventually terminate the overlay
	overlay.animOut:Play();
end

function SpellActivationOverlayFrame_PlayCombatAnimOut(animOut)
	local combat = animOut:GetParent();
	local overlay = combat:GetParent();
	local frame = overlay:GetParent();
	local position = overlay.position;

	local baseLongSide = 256;
	local baseShortSide = 128;
	local farAway = ((baseLongSide-baseShortSide) / 2 + baseShortSide) * sizeScale * frame.scale * combatOverlayFactor;

	local offsetX, offsetY;
	if ( position == "CENTER" ) then
		offsetX, offsetY = 0, 0;
	elseif ( position == "LEFT" ) then
		offsetX, offsetY = farAway, 0;
	elseif ( position == "RIGHT" ) then
		offsetX, offsetY = -farAway, 0;
	elseif ( position == "TOP" ) then
		offsetX, offsetY = 0, -farAway;
	elseif ( position == "BOTTOM" ) then
		offsetX, offsetY = 0, farAway;
	elseif ( position == "TOPRIGHT" ) then
		offsetX, offsetY = -farAway, -farAway;
	elseif ( position == "TOPLEFT" ) then
		offsetX, offsetY = farAway, -farAway;
	elseif ( position == "BOTTOMRIGHT" ) then
		offsetX, offsetY = -farAway, farAway;
	elseif ( position == "BOTTOMLEFT" ) then
		offsetX, offsetY = farAway, farAway;
	else
		--GMError("Unknown SpellActivationOverlay position: "..tostring(position));
		return;
	end

	animOut.path1.final:SetOffset(offsetX, offsetY);
	animOut.path2.final:SetOffset(offsetX, offsetY);

	animOut:Play();
end

function SpellActivationOverlayTexture_OnFadeInPlay(animGroup)
	animGroup:GetParent():SetAlpha(0);
end

function SpellActivationOverlayTexture_OnFadeInFinished(animGroup)
	local overlay = animGroup:GetParent();
	overlay:SetAlpha(1);
	if ( overlay.pulse.autoPlay ) then
		overlay.pulse:Play();
	end
end

function SpellActivationOverlayTexture_OnFadeOutFinished(anim)
	local overlay = anim:GetRegionParent();
	SpellActivationOverlayTexture_TerminateOverlay(overlay);
end

function SpellActivationOverlayFrame_OnFadeInFinished(anim)
	if ( not InCombatLockdown() ) then
		-- Fade-out immediately if not in combat
		-- Although it may look counter-intuitive to be out-of-combat during an in-combat animation,
		-- This may actually happen if the in-combat mode was forced to showcase out-of-combat procs e.g., healing-based procs
		local frame = anim:GetParent();
		if ( not frame.disableDimOutOfCombat ) then
			frame.combatAnimOut:Play();
			for _, overlay in ipairs(frame.combatOnlyOverlays) do
				SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
			end
		end
	end
end

function SpellActivationOverlayFrame_SetForceAlpha1(enabled)
	local self = SpellActivationOverlayFrame;
	if (enabled) then
		if (not self.disableDimOutOfCombat) then
			self.disableDimOutOfCombat = 1;
			self.combatAnimOut:Stop();	--In case we're in the process of animating this out.
			self:SetAlpha(1);
			for _, overlay in ipairs(self.combatOnlyOverlays) do
				overlay.combat.animOut:Stop();
				overlay.texture:SetAlpha(1);
			end
		else
			-- Set last digit
			self.disableDimOutOfCombat = self.disableDimOutOfCombat-self.disableDimOutOfCombat%10+1;
		end
	else
		if (self.disableDimOutOfCombat) then
			-- Reset last digit
			self.disableDimOutOfCombat = self.disableDimOutOfCombat-self.disableDimOutOfCombat%10;

			if (self.disableDimOutOfCombat == 0) then
				self.disableDimOutOfCombat = nil;
				if (not InCombatLockdown()) then
					self.combatAnimOut:Play();
					for _, overlay in ipairs(self.combatOnlyOverlays) do
						SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
					end
				end
			end
		end
	end
end

function SpellActivationOverlayFrame_SetForceAlpha2(enabled)
	local self = SpellActivationOverlayFrame;
	if (enabled) then
		if (not self.disableDimOutOfCombat) then
			self.disableDimOutOfCombat = 10;
			self.combatAnimOut:Stop();	--In case we're in the process of animating this out.
			self:SetAlpha(1);
			for _, overlay in ipairs(self.combatOnlyOverlays) do
				overlay.combat.animOut:Stop();
				overlay.texture:SetAlpha(1);
			end
		else
			-- Set second-to-last digit
			self.disableDimOutOfCombat = self.disableDimOutOfCombat%10+10;
		end
	else
		if (self.disableDimOutOfCombat) then
			-- Reset second-to-last digit
			self.disableDimOutOfCombat = self.disableDimOutOfCombat%10;

			if (self.disableDimOutOfCombat == 0) then
				self.disableDimOutOfCombat = nil;
				if (not InCombatLockdown()) then
					self.combatAnimOut:Play();
					for _, overlay in ipairs(self.combatOnlyOverlays) do
						SpellActivationOverlayFrame_PlayCombatAnimOut(overlay.combat.animOut);
					end
				end
			end
		end
	end
end
