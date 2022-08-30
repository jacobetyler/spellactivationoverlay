local AddonName, SAO = ...

local function registerClass(self)
    local howlingBlast = GetSpellInfo(49184);
    self:RegisterAura("rime", 0, 59052, "rime", "Top", 1, 255, 255, 255, true, { howlingBlast });

    local runeStrike = 56815;
    self:RegisterAura("rune_strike", 0, runeStrike, nil, "", 0, 0, 0, 0, false, { runeStrike });
    self:RegisterCounter("rune_strike"); -- Must match name from above call
end

SAO.Class["DEATHKNIGHT"] = {
    ["Register"] = registerClass,
}
