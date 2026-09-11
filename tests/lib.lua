--[[
    Shared suite library for Move Raid Manager (test_moverm, test_moverm_modern,
    test_moverm_right, sim_classic, sim_mainline). Suites run from the addon
    root:

        local env = dofile("../shared/wow_test_env.lua"); -- the canonical mock
        local lib = dofile("tests/lib.lua").init(env);

    Passing env in (instead of dofile-ing the mock a second time) matters: a
    second dofile re-executes the mock and installs a FRESH frame registry,
    which would silently detach the addon from the suite's env.

    Provides the assert helpers, the config-window drivers, and the two
    client worlds, mirroring source's Blizzard_CompactRaidFrames per
    family:
      * classic (1.15/2.5/5.5 Classic folder): the manager OnLoad reparents
        the container under itself; the manager carries its own artwork
        textures plus a single toggle button (RIGHT anchor, two-half arrow
        sprite); expand/collapse re-anchor to UIParent TOPLEFT x=-7 / x=-182
        at y=-140 and swap the arrow sprite half (strata LOW).
      * modern (12.1 Mainline folder): the container stays a UIParent
        sibling; the manager has a Background atlas and a
        toggleButtonBack/toggleButtonForward pair (RIGHT anchors, directional
        atlases: back = left-pointing, forward = right-pointing);
        expand/collapse re-anchor to x=0 / x=-200 at y=-140 (strata MEDIUM).
    Both worlds ship Blizzard's Collapse() called from OnLoad, exactly like
    the real client, so the addon boots with collapsed=true and the stock
    strip state (classic: collapsed half; modern: forward shown).
--]]

local function BuildManagerWorld(modern)
    local manager = CreateFrame("Frame", "CompactRaidFrameManager", UIParent);
    manager:SetSize(222, 140);
    manager:EnableMouse(true);
    manager:SetFrameStrata(modern and "MEDIUM" or "LOW");
    manager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", modern and 0 or -7, -140);

    local container = CreateFrame("Frame", "CompactRaidFrameContainer", UIParent);
    container:SetFrameStrata("HIGH");
    container:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, -5);
    manager.container = container;

    -- the manager's own artwork, named and anchored like the 1.15 Classic XML
    local art = {};
    if not modern then
        local names = {
            "CompactRaidFrameManagerBg",
            "CompactRaidFrameManagerBorderTopLeft", "CompactRaidFrameManagerBorderTopRight",
            "CompactRaidFrameManagerBorderBottomLeft", "CompactRaidFrameManagerBorderBottomRight",
            "CompactRaidFrameManagerBorderTop", "CompactRaidFrameManagerBorderBottom",
            "CompactRaidFrameManagerBorderRight",
        };
        for _, name in ipairs(names) do
            art[#art + 1] = manager:CreateTexture(name, "ARTWORK");
        end
        local artByName = {};
        for _, texture in ipairs(art) do
            artByName[texture:GetName()] = texture;
        end
        -- corner and edge anchors, mirroring the XML structure
        artByName.CompactRaidFrameManagerBorderTopLeft:SetPoint("TOPLEFT", manager, "TOPLEFT", 0, 0);
        artByName.CompactRaidFrameManagerBorderTopRight:SetPoint("TOPRIGHT", manager, "TOPRIGHT", 0, 0);
        artByName.CompactRaidFrameManagerBorderBottomLeft:SetPoint("BOTTOMLEFT", manager, "BOTTOMLEFT", 0, 0);
        artByName.CompactRaidFrameManagerBorderBottomRight:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", 0, 0);
        artByName.CompactRaidFrameManagerBorderTop:SetPoint("TOPLEFT", artByName.CompactRaidFrameManagerBorderTopLeft, "TOPRIGHT", 0, 1);
        artByName.CompactRaidFrameManagerBorderTop:SetPoint("TOPRIGHT", artByName.CompactRaidFrameManagerBorderTopRight, "TOPLEFT", 0, 1);
        artByName.CompactRaidFrameManagerBorderBottom:SetPoint("BOTTOMLEFT", artByName.CompactRaidFrameManagerBorderBottomLeft, "BOTTOMRIGHT", 0, -4);
        artByName.CompactRaidFrameManagerBorderBottom:SetPoint("BOTTOMRIGHT", artByName.CompactRaidFrameManagerBorderBottomRight, "BOTTOMLEFT", 0, -4);
        artByName.CompactRaidFrameManagerBorderRight:SetPoint("TOPRIGHT", artByName.CompactRaidFrameManagerBorderTopRight, "BOTTOMRIGHT", 2, 0);
        artByName.CompactRaidFrameManagerBorderRight:SetPoint("BOTTOMRIGHT", artByName.CompactRaidFrameManagerBorderBottomRight, "TOPRIGHT", 2, 0);
        artByName.CompactRaidFrameManagerBg:SetPoint("TOPLEFT", artByName.CompactRaidFrameManagerBorderTopLeft, "TOPLEFT", 7, -6);
        artByName.CompactRaidFrameManagerBg:SetPoint("BOTTOMRIGHT", artByName.CompactRaidFrameManagerBorderBottomRight, "BOTTOMRIGHT", -7, 7);
    else
        art[#art + 1] = manager:CreateTexture("CompactRaidFrameManagerBackground", "ARTWORK");
        art[1]:SetAllPoints();
    end
    local artByName = {};
    for _, texture in ipairs(art) do
        artByName[texture:GetName()] = texture;
    end

    -- the toggle button(s): stock anchors and OnClick, like the XML
    local function MakeToggleButton(name, parentKey, width, height, xOffset)
        local b = CreateFrame("Button", name, manager);
        manager[parentKey] = b;
        b:SetSize(width, height);
        b:SetPoint("RIGHT", manager, "RIGHT", xOffset, 0);
        local tex = b:CreateTexture(name .. "NormalTexture", "OVERLAY");
        function b:GetNormalTexture() return tex; end
        b:SetScript("OnClick", function()
            CompactRaidFrameManager_Toggle(manager);
        end);
        return b, tex;
    end

    local toggleButton, toggleTex, forward, back;
    if modern then
        forward = MakeToggleButton("CompactRaidFrameManagerToggleButtonForward", "toggleButtonForward", 16, 35, -7);
        back = MakeToggleButton("CompactRaidFrameManagerToggleButtonBack", "toggleButtonBack", 16, 35, -7);
    else
        toggleButton, toggleTex = MakeToggleButton("CompactRaidFrameManagerToggleButton", "toggleButton", 16, 64, -9);
    end

    -- the options panel: hidden while collapsed, like Blizzard's Collapse()
    local displayFrame = CreateFrame("Frame", "CompactRaidFrameManagerDisplayFrame", manager);
    manager.displayFrame = displayFrame;

    -- Blizzard's Expand/Collapse/Toggle, verbatim behavior per family
    -- (including the stock strip visuals the real code sets)
    function CompactRaidFrameManager_Expand(self)
        self.collapsed = false;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", modern and 0 or -7, -140);
        self.displayFrame:Show();
        if modern then
            back:Show();
            forward:Hide();
        else
            toggleTex:SetTexCoord(0.5, 1, 0, 1);
        end
    end
    function CompactRaidFrameManager_Collapse(self)
        self.collapsed = true;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", modern and -200 or -182, -140);
        self.displayFrame:Hide();
        if modern then
            back:Hide();
            forward:Show();
        else
            toggleTex:SetTexCoord(0, 0.5, 0, 1);
        end
    end
    function CompactRaidFrameManager_Toggle(self)
        if self.collapsed then
            CompactRaidFrameManager_Expand(self);
        else
            CompactRaidFrameManager_Collapse(self);
        end
    end

    -- classic OnLoad reparents the container under the manager
    if not modern then
        container:SetParent(manager);
    end

    CompactRaidFrameManager_Collapse(manager); -- OnLoad state, both families
    return manager, container, art, artByName;
end

return {
    init = function(env)
        local out = env.rawPrint;
        local lib = {};

        local PASS, FAIL = 0, 0;
        function lib.ok(cond, name, extra)
            if cond then PASS = PASS + 1; out("  PASS: " .. name);
            else FAIL = FAIL + 1; out("  FAIL: " .. name .. (extra ~= nil and (" -- " .. tostring(extra)) or "")); end
        end
        function lib.done()
            out(("Test/Sim Results: %d passed, %d failed"):format(PASS, FAIL));
            if FAIL > 0 then
                os.exit(1);
            end
        end

        function lib.same(actual, expected)
            if #actual ~= #expected then return false; end
            for i = 1, #actual do
                if actual[i] ~= expected[i] then return false; end
            end
            return true;
        end

        -- points as comparable tables: relativeTo reduced to its name
        function lib.P(frame, index)
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(index or 1);
            return { point, relativeTo and (relativeTo.GetName and relativeTo:GetName()) or tostring(relativeTo), relativePoint, x, y };
        end

        -- wipe globals from a previous boot, build a fresh world, load the
        -- addon and fire ADDON_LOADED; returns manager, container, art,
        -- artByName. keepDB re-boots over the existing SavedVariables table
        -- (reload)
        function lib.Boot(modern, keepDB)
            if not keepDB then
                _G.Move_CompactRaidFrameManager = nil;
            end
            _G.CompactRaidFrameManager = nil;
            _G.CompactRaidFrameContainer = nil;
            local manager, container, art, artByName = BuildManagerWorld(modern);
            _G.CompactRaidFrameManager = manager;
            _G.CompactRaidFrameContainer = container;
            assert(loadfile("Move_CompactRaidFrameManager.lua"))();
            env:FireEvent("ADDON_LOADED", "Move_CompactRaidFrameManager");
            return manager, container, art, artByName;
        end

        function lib.Slash(msg)
            SlashCmdList.MOVERM(msg);
        end

        function lib.Window()
            SlashCmdList.MOVERM("");
            return env:FindFrame("Move_CompactRaidFrameManagerOptions");
        end

        -- type into an edit box and press enter
        function lib.TypeIn(box, value)
            box:SetText(value);
            local s = box:GetScript("OnEnterPressed");
            if s then s(box); end
        end

        -- click a widget; pass checked to set a checkbox state first
        function lib.Click(widget, checked)
            if checked ~= nil then
                widget:SetChecked(checked);
            end
            local s = widget:GetScript("OnClick");
            if s then s(widget); end
        end

        -- drive a DropdownButton's MenuUtil generator with a fake root description
        function lib.DriveMenu(dd)
            local root = {};
            function root:CreateRadio(text, isSelected, setSelected, data)
                self[#self + 1] = { text = text, isSelected = isSelected, setSelected = setSelected, data = data };
            end
            dd:GetMenuGenerator()(dd, root);
            return root;
        end

        function lib.PickMenuEntry(root, data)
            for _, entry in ipairs(root) do
                if entry.data == data then
                    entry.setSelected(data);
                    return;
                end
            end
        end

        return lib;
    end,
};
