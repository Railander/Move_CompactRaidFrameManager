--[[
    Restriction-discipline suite for Move Raid Manager on the SHARED harness.

    Straps the addon to shared/wow_test_env.lua (mock client) +
    shared/wow_restriction_sim.lua (12.x enforcement layer: SecretArguments
    gates, dispatch-false query semantics, hooksecurefunc taint).

    Run from the addon root: lua5.1 tests/sim_restrictions.lua
    Prints PASS:/FAIL: lines, ends with "Test Results: N passed, M failed",
    os.exit(1) on any failure. Output via env.rawPrint (print is captured).

    Harness adaptations (documented, not worked around):
    - tests/lib.lua is NOT reused here: its worlds are built for the bare
      mock (no gates, no seeds). The minimal worlds below are built on the
      sim's seeded Blizzard-owned CompactRaidFrameManager/Container so every
      gated call is observed.
    - Gated reads (GetScript) are captured while clear and driven while
      locked, exactly like Move_FPS_Counter's sim_restrictions.lua.
    - The stock toggle OnClick is Blizzard-equivalent Lua here, so driving a
      toggle while locked logs the TEST's own gated SetPoint (in game that
      runs as untainted Blizzard execution). Those are cleared as
      test-induced, like Move_FPS_Counter R8; the addon must log nothing.
    - The sim does not gate layout getters (GetPoint) or hover reads
      (IsMouseOver); the addon still avoids them while locked by design
      (lock-checked appliers), so sim-clean matches the game-safe discipline.
]]

local env = dofile("../shared/wow_test_env.lua");
local rs = dofile("../shared/wow_restriction_sim.lua");

local PASS, FAIL = 0, 0;
local function ok(cond, name, extra)
    if cond then PASS = PASS + 1; env.rawPrint("  PASS: " .. name);
    else FAIL = FAIL + 1; env.rawPrint("  FAIL: " .. name .. (extra and (" -- " .. tostring(extra)) or "")); end
end

local SCREEN_W, SCREEN_H = 1024, 768;

local function newViolations(base)
    local out = {};
    for i = base + 1, #env.restrictionViolations do
        out[#out + 1] = env.restrictionViolations[i].api;
    end
    return out;
end

local function onlyFrom(list, allowed)
    for _, api in ipairs(list) do
        if not allowed[api] then return false, api; end
    end
    return true;
end

local function noSetShown(base, label)
    for i = base + 1, #env.restrictionViolations do
        if env.restrictionViolations[i].api == "Frame:SetShown" then
            ok(false, label, "SetShown used; Show/Hide required");
            return;
        end
    end
    ok(true, label);
end

local function pointOf(region)
    local a, b, c, d, e = region:GetPoint(1);
    if type(b) == "table" then b = b:GetName() or "?"; end
    return table.concat({ tostring(a), tostring(b), tostring(c), tostring(d), tostring(e) }, "|");
end

-- Modern world on the sim's seeds: single Background texture + back/forward
-- toggle pair + display frame, stock Collapse at boot (mirrors tests/lib.lua).
local function buildModern()
    local manager = _G.CompactRaidFrameManager;
    local container = _G.CompactRaidFrameContainer;
    manager:SetSize(222, 140);
    manager:SetFrameStrata("MEDIUM");
    manager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, -140);
    container:SetFrameStrata("HIGH");
    container:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, -5);

    local bg = manager:CreateTexture("CompactRaidFrameManagerBackground", "ARTWORK");
    bg:SetAllPoints();

    local function makeToggle(name, key)
        local b = CreateFrame("Button", name, manager);
        manager[key] = b;
        b:SetSize(16, 35);
        b:SetPoint("RIGHT", manager, "RIGHT", -7, 0);
        local tex = b:CreateTexture(name .. "NormalTexture", "OVERLAY");
        function b:GetNormalTexture() return tex; end
        return b;
    end
    local forward = makeToggle("CompactRaidFrameManagerToggleButtonForward", "toggleButtonForward");
    local back = makeToggle("CompactRaidFrameManagerToggleButtonBack", "toggleButtonBack");
    local displayFrame = CreateFrame("Frame", "CompactRaidFrameManagerDisplayFrame", manager);
    manager.displayFrame = displayFrame;

    local function expand(self)
        self.collapsed = false;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -140);
        self.displayFrame:Show();
        back:Show();
        forward:Hide();
    end
    local function collapse(self)
        self.collapsed = true;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, -140);
        self.displayFrame:Hide();
        back:Hide();
        forward:Show();
    end
    local function onToggle() if manager.collapsed then expand(manager); else collapse(manager); end end
    back:SetScript("OnClick", onToggle);
    forward:SetScript("OnClick", onToggle);
    collapse(manager);
    return manager, container, back, forward;
end

-- Classic world on the sim's seeds: artwork + single toggle button, container
-- reparented under the manager (mirrors tests/lib.lua).
local function buildClassic()
    local manager = _G.CompactRaidFrameManager;
    local container = _G.CompactRaidFrameContainer;
    manager:SetSize(200, 140);
    manager:SetFrameStrata("LOW");
    manager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -182, -140);
    container:SetFrameStrata("HIGH");
    container:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, -5);

    local art = {};
    for _, name in ipairs({
        "CompactRaidFrameManagerBg",
        "CompactRaidFrameManagerBorderTopLeft", "CompactRaidFrameManagerBorderTopRight",
        "CompactRaidFrameManagerBorderBottomLeft", "CompactRaidFrameManagerBorderBottomRight",
        "CompactRaidFrameManagerBorderTop", "CompactRaidFrameManagerBorderBottom",
        "CompactRaidFrameManagerBorderRight",
    }) do
        art[#art + 1] = manager:CreateTexture(name, "ARTWORK");
    end
    local byName = {};
    for _, t in ipairs(art) do byName[t:GetName()] = t; end
    byName.CompactRaidFrameManagerBorderTopLeft:SetPoint("TOPLEFT", manager, "TOPLEFT", 0, 0);
    byName.CompactRaidFrameManagerBorderTopRight:SetPoint("TOPRIGHT", manager, "TOPRIGHT", 0, 0);
    byName.CompactRaidFrameManagerBorderBottomLeft:SetPoint("BOTTOMLEFT", manager, "BOTTOMLEFT", 0, 0);
    byName.CompactRaidFrameManagerBorderBottomRight:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", 0, 0);
    byName.CompactRaidFrameManagerBorderTop:SetPoint("TOPLEFT", byName.CompactRaidFrameManagerBorderTopLeft, "TOPRIGHT", 0, 1);
    byName.CompactRaidFrameManagerBorderTop:SetPoint("TOPRIGHT", byName.CompactRaidFrameManagerBorderTopRight, "TOPLEFT", 0, 1);
    byName.CompactRaidFrameManagerBorderBottom:SetPoint("BOTTOMLEFT", byName.CompactRaidFrameManagerBorderBottomLeft, "BOTTOMRIGHT", 0, -4);
    byName.CompactRaidFrameManagerBorderBottom:SetPoint("BOTTOMRIGHT", byName.CompactRaidFrameManagerBorderBottomRight, "BOTTOMLEFT", 0, -4);
    byName.CompactRaidFrameManagerBorderRight:SetPoint("TOPRIGHT", byName.CompactRaidFrameManagerBorderTopRight, "BOTTOMRIGHT", 2, 0);
    byName.CompactRaidFrameManagerBorderBottomRight:SetPoint("BOTTOMRIGHT", byName.CompactRaidFrameManagerBorderBottomRight, "TOPRIGHT", 2, 0);
    byName.CompactRaidFrameManagerBg:SetPoint("TOPLEFT", byName.CompactRaidFrameManagerBorderTopLeft, "TOPLEFT", 7, -6);
    byName.CompactRaidFrameManagerBg:SetPoint("BOTTOMRIGHT", byName.CompactRaidFrameManagerBorderBottomRight, "BOTTOMRIGHT", -7, 7);

    local b = CreateFrame("Button", "CompactRaidFrameManagerToggleButton", manager);
    manager.toggleButton = b;
    b:SetSize(16, 64);
    b:SetPoint("RIGHT", manager, "RIGHT", -9, 0);
    local tex = b:CreateTexture("CompactRaidFrameManagerToggleButtonNormalTexture", "OVERLAY");
    function b:GetNormalTexture() return tex; end
    local displayFrame = CreateFrame("Frame", "CompactRaidFrameManagerDisplayFrame", manager);
    manager.displayFrame = displayFrame;

    local function expand(self)
        self.collapsed = false;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -7, -140);
        self.displayFrame:Show();
        tex:SetTexCoord(0.5, 1, 0, 1);
    end
    local function collapse(self)
        self.collapsed = true;
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -182, -140);
        self.displayFrame:Hide();
        tex:SetTexCoord(0, 0.5, 0, 1);
    end
    b:SetScript("OnClick", function(self) if self.collapsed ~= false and manager.collapsed then expand(manager); else collapse(manager); end end);
    container:SetParent(manager);
    collapse(manager);
    return manager, container, b;
end

local function findOptions()
    return env:FindFrame("Move_CompactRaidFrameManagerOptions");
end

local function findEventFrame()
    return env:FindFrame("Move_CompactRaidFrameManagerEventFrame");
end

-- Drive a DropdownButton's SetupMenu generator with a fake root description.
local function pickMenuEntry(dd, data)
    local root = {};
    function root:CreateRadio(text, isSelected, setSelected, d)
        self[#self + 1] = { setSelected = setSelected, data = d };
    end
    dd:GetMenuGenerator()(dd, root);
    for _, entry in ipairs(root) do
        if entry.data == data then entry.setSelected(data); return true; end
    end
    return false;
end

-- Boot under MAX restrictions: the /reload-in-combat trap (mainline). The
-- world itself is built clear first (Blizzard frames anchor before combat;
-- only the ADDON load lands mid-protection), then the lock slams on.
rs.Enable(env, { scenario = "none", flavor = "mainline" });
_G.UIParent:SetSize(SCREEN_W, SCREEN_H);
buildModern();
env:ActivateAllRestrictions();
env:ClearViolations();
_G.Move_CompactRaidFrameManager = nil;
assert(loadfile("Move_CompactRaidFrameManager.lua"))();
env:FireEvent("ADDON_LOADED", "Move_CompactRaidFrameManager");

env.rawPrint("== R1: max boot defers everything with zero gates ==");
do
    ok(#env.restrictionViolations == 0, "locked boot logs nothing (lock checked before any install)");
    ok(_G.Move_CompactRaidFrameManager == nil, "saved state untouched: ADDON_LOADED unheard while deaf");
    ok(findOptions() == nil, "options window NOT half-built while protected");
    local ef = findEventFrame();
    ok(ef ~= nil, "listener frame exists (CreateFrame is ungated)");
    ok(ef ~= nil and not ef:IsEventRegistered("ADDON_LOADED"), "no event registered while protected");
    ok(#env.taintedHooks == 0, "no Blizzard-Lua hooks installed while protected");
end

env.rawPrint("== R2: slash self-heal while locked is fully silent ==");
do
    local base = #env.restrictionViolations;
    SlashCmdList.MOVERM(""); -- lazy state load (pure Lua) + deferred gated init
    ok(#newViolations(base) == 0, "locked slash logs nothing");
    local db = _G.Move_CompactRaidFrameManager;
    ok(db ~= nil and db.y == -140, "state loaded (game placement) while gates wait");
    ok(#env.printLog == 0, "first-run greet queued, not printed into lockdown (best-effort)");
    ok(findOptions() == nil, "options still unbuilt while locked");
    base = #env.restrictionViolations;
    SlashCmdList.MOVERM("reset"); -- db-only work lands, applies queue
    ok(#newViolations(base) == 0, "locked reset logs nothing");
    ok(_G.Move_CompactRaidFrameManager.y == -140, "reset db correct while applies wait");
    noSetShown(base, "no SetShown anywhere on the locked paths");
end

env.rawPrint("== R3: lift resumes everything with zero gates ==");
do
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    SlashCmdList.MOVERM(""); -- self-heal: full gated init runs once clear
    ok(#env.restrictionViolations == 0, "lift init is clean");
    local db = _G.Move_CompactRaidFrameManager;
    local manager = _G.CompactRaidFrameManager;
    local container = _G.CompactRaidFrameContainer;
    ok(db.y == -140, "game placement kept after lift");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-140", "collapsed anchor applied", pointOf(manager));
    local setPointTouches = 0;
    for _, touch in ipairs(env.blizzardTouches) do
        if touch.api == "Frame:SetPoint" then setPointTouches = setPointTouches + 1; end
    end
    ok(setPointTouches == 0, "default lift writes no anchors (Blizzard layout untouched)");
    ok(manager:GetFrameStrata() == "MEDIUM" and container:GetFrameStrata() == "HIGH",
        "stock strata split kept after lift");
    ok(manager:GetAlpha() == 1, "nothing faded after lift");
    local options = findOptions();
    ok(options ~= nil and options.strataBtn ~= nil,
        "options + strata picker built on lift");
    ok(#env.printLog == 2 and env.printLog[1]:find("/moverm", 1, true) ~= nil,
        "queued first-run greet printed once clear");
    local ef = findEventFrame();
    ok(ef ~= nil and ef:IsEventRegistered("ADDON_RESTRICTION_STATE_CHANGED")
        and ef:IsEventRegistered("PLAYER_REGEN_ENABLED")
        and ef:IsEventRegistered("PLAYER_ENTERING_WORLD"),
        "restriction/regen/zone events registered on lift");
    ok(manager:GetScript("OnShow") ~= nil and manager:GetScript("OnEnter") ~= nil
        and manager:GetScript("OnLeave") ~= nil,
        "fade post-hooks installed on lift");
    -- capture gated-readable handlers while clear: GetScript itself is gated
    -- while locked, so every locked driver below uses these references.
    local H = {};
    H.enterY = options.yBox:GetScript("OnEnterPressed");
    H.hideClick = options.hideBox:GetScript("OnClick");
    H.onShow = manager:GetScript("OnShow");
    H.onEnter = manager:GetScript("OnEnter");
    H.onLeave = manager:GetScript("OnLeave");
    H.backClick = manager.toggleButtonBack:GetScript("OnClick");
    H.forwardClick = manager.toggleButtonForward:GetScript("OnClick");
    H.typeY = function(v) options.yBox:SetText(v); H.enterY(options.yBox); end
    H.clickHide = function(checked) options.hideBox:SetChecked(checked); H.hideClick(options.hideBox); end
    _G.MoveRM_testHooks = H;
end

env.rawPrint("== R4: zero hooksecurefunc taint anywhere ==");
do
    ok(#env.taintedHooks == 0, "addon never hooksecurefunc'd a Blizzard Lua method");
end

env.rawPrint("== R5: expand/collapse keeps Y while clear, queues while locked ==");
do
    local H = _G.MoveRM_testHooks;
    local manager = _G.CompactRaidFrameManager;
    local db = _G.Move_CompactRaidFrameManager;
    H.typeY("-300");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300", "Y box moves the manager");
    H.backClick(manager.toggleButtonBack); -- expand while clear
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|0|-300", "expand keeps the moved Y with no override");
    H.forwardClick(manager.toggleButtonForward); -- collapse while clear
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300", "collapse keeps the moved Y with no override");
    ok(#env.restrictionViolations == 0, "clear toggles touch no gates");
    env:ActivateAllRestrictions();
    env:ClearViolations();
    -- Locked toggle: the stock re-anchor is driven here as tainted test code,
    -- so the sim blocks it (in game it runs as untainted Blizzard execution
    -- and lands). Either way the addon's post-hook must only queue behind it.
    H.backClick(manager.toggleButtonBack); -- expand while locked
    env:ClearViolations(); -- drop the TEST's own gated SetPoint (untainted Blizzard execution in game)
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300",
        "locked toggle moves nothing from the addon side", pointOf(manager));
    ok(db.y == -300, "saved Y untouched while locked");
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    env:FireEvent("PLAYER_REGEN_ENABLED"); -- backstop refresh flushes the queue
    ok(#env.restrictionViolations == 0, "lift flush is clean");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300",
        "flush re-asserts the saved Y over the standing anchor", pointOf(manager));
    H.forwardClick(manager.toggleButtonForward); -- collapse while clear for the fade tests
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300", "collapsed again");
    noSetShown(0, "toggle path never used SetShown");
end

env.rawPrint("== R6: inputs while locked queue silently, flush on lift ==");
do
    local H = _G.MoveRM_testHooks;
    local db = _G.Move_CompactRaidFrameManager;
    local manager = _G.CompactRaidFrameManager;
    local container = _G.CompactRaidFrameContainer;
    local options = findOptions();
    env:ActivateAllRestrictions();
    env:ClearViolations();
    local base = #env.restrictionViolations;
    H.typeY("-120.5");
    ok(db.y == -120.5, "locked Y input lands in db (pure Lua)");
    H.typeY("-400");
    ok(db.y == -400, "locked Y input lands in db again");
    H.clickHide(true);
    ok(db.fade == true, "locked fade input lands in db");
    ok(pickMenuEntry(options.strataBtn, 5), "locked strata pick runs");
    ok(db.strata == 5, "locked strata lands in db");
    ok(#newViolations(base) == 0, "locked inputs log nothing");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-300",
        "locked inputs apply nothing yet", pointOf(manager));
    ok(manager:GetFrameStrata() == "MEDIUM", "locked strata applies nothing yet");
    ok(manager:GetAlpha() == 1, "locked fade applies nothing yet (last state stands)");
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    env:FireEvent("PLAYER_REGEN_ENABLED");
    ok(#env.restrictionViolations == 0, "lift flush is clean");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-400",
        "queued Y applied on lift", pointOf(manager));
    ok(manager:GetFrameStrata() == "DIALOG" and container:GetFrameStrata() == "HIGH",
        "queued strata applied on lift, raid frames re-pinned");
    ok(manager:GetAlpha() == 0, "queued fade applied on lift (collapsed, unhovered)");
end

env.rawPrint("== R7: restriction-event payload protocol lifts via out-of-dispatch confirm ==");
do
    local H = _G.MoveRM_testHooks;
    local db = _G.Move_CompactRaidFrameManager;
    local manager = _G.CompactRaidFrameManager;
    env:SetRestriction("Encounter", rs.ACTIVE);
    env:ClearViolations();
    env:FireRestrictionChange("Encounter", 2); -- Activating edge locks (query lies false, payload rules)
    ok(H ~= nil and db.y == -400, "suite state intact");
    H.typeY("-500");
    ok(db.y == -500, "write queued under Encounter lock");
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-400",
        "queued write applies nothing yet", pointOf(manager));
    env:FireRestrictionChange("Encounter", 0); -- Inactive applies first, then dispatches
    env:Pump(0.1); -- the C_Timer.After(0) confirm runs outside dispatch
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-200|-500",
        "queued write flushed on confirm", pointOf(manager));
    ok(#env.restrictionViolations == 0, "confirm path touches no gates");
    env:DeactivateAllRestrictions();
end

env.rawPrint("== R8: fade inputs while locked are skipped, not misread ==");
do
    local H = _G.MoveRM_testHooks;
    local manager = _G.CompactRaidFrameManager;
    ok(manager:GetAlpha() == 0, "precondition: collapsed manager faded");
    env:ActivateAllRestrictions();
    env:ClearViolations();
    local base = #env.restrictionViolations;
    manager._mouseOver = true;
    H.onEnter(manager); -- hover while locked: IsMouseOver unreadable, last state stands
    ok(manager:GetAlpha() == 0, "locked hover changes nothing");
    manager._mouseOver = false;
    H.onLeave(manager);
    ok(manager:GetAlpha() == 0, "locked leave changes nothing");
    H.onShow(manager);
    ok(manager:GetAlpha() == 0, "locked show changes nothing");
    ok(#newViolations(base) == 0, "locked fade path touches no gates");
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    manager._mouseOver = true;
    H.onEnter(manager);
    ok(manager:GetAlpha() == 1, "hover reveals once clear");
    manager._mouseOver = false;
    H.onLeave(manager);
    ok(manager:GetAlpha() == 0, "leave hides once clear");
    ok(#env.restrictionViolations == 0, "clear fade path touches no gates");
end

env.rawPrint("== R9: classic flavor enforces nothing (states Active, gates off) ==");
do
    -- A real classic client never reports any restriction type Active (no
    -- secret system), so the addon runs straight through there. The sim keeps
    -- state tracking alive on classic and only disables gate enforcement, so
    -- a classic-max boot still (correctly per the shared query) defers its
    -- gated init -- while every direct frame call succeeds unenforced.
    env:Reset(); -- fresh frames; restriction states preserved, logs cleared
    rs.Enable(env, { scenario = "max", flavor = "classic" });
    _G.UIParent:SetSize(SCREEN_W, SCREEN_H);
    local manager, container = buildClassic();
    env:ClearViolations();
    _G.Move_CompactRaidFrameManager = nil;
    assert(loadfile("Move_CompactRaidFrameManager.lua"))();
    env:FireEvent("ADDON_LOADED", "Move_CompactRaidFrameManager");
    ok(#env.restrictionViolations == 0, "classic max boot is clean (no gate system)");
    ok(_G.Move_CompactRaidFrameManager == nil,
        "classic deaf boot loads nothing (ADDON_LOADED unheard, same as mainline R1)");
    ok(findOptions() == nil, "classic gated init deferred while sim states read Active (sim-only; real classic never reports Active)");
    env:ClearViolations();
    local toggle = manager.toggleButton;
    toggle:GetScript("OnClick")(toggle); -- expand at max: unenforced on classic
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-7|-140", "classic stock re-anchor works at max");
    manager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -7, -200);
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-7|-200", "classic SetPoint ungated at max");
    container:SetFrameStrata("FULLSCREEN");
    ok(container:GetFrameStrata() == "FULLSCREEN", "classic SetFrameStrata ungated at max");
    ok(#env.restrictionViolations == 0, "classic frame calls ungated at max");
    ok(#env.taintedHooks == 0, "classic install never hooked a Blizzard Lua method");
    -- lifting the sim states resumes the deferred init, like any lift
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    SlashCmdList.MOVERM("");
    ok(#env.restrictionViolations == 0, "classic lift init is clean");
    local options = findOptions();
    ok(options ~= nil and options:IsShown(), "classic window opens after lift");
    ok(#env.restrictionViolations == 0, "classic options clean");
end

env.rawPrint("== R10: move mode drags while clear, refuses while locked ==");
do
    -- Post-R9 world: classic manager, expanded, clear.
    local manager = _G.CompactRaidFrameManager;
    local db = _G.Move_CompactRaidFrameManager;
    local options = findOptions();
    -- capture gated-readable scripts while clear (GetScript is gated while locked)
    local moveBtnClick = options.moveBtn:GetScript("OnClick");
    local onHide = options:GetScript("OnHide");
    local function clickMove() moveBtnClick(options.moveBtn); end
    clickMove(); -- enter move mode while clear
    local box = env:FindFrame("Move_CompactRaidFrameManagerMoveBox");
    local input = env:FindFrame("Move_CompactRaidFrameManagerMoveInput");
    ok(box ~= nil and box:IsShown() and input:IsShown(), "move mode enters while clear");
    ok(pointOf(box) == pointOf(manager), "box copies the manager rect");
    ok(box:GetFrameStrata() == "BACKGROUND", "box below the manager");
    local onDragStart = input:GetScript("OnDragStart");
    local onDragStop = input:GetScript("OnDragStop");
    -- drag while clear: grab the anchor, move the cursor, the Y follows
    env.cursorX, env.cursorY = 512, 768 + db.y;
    onDragStart(input);
    local onDragUpdate = input:GetScript("OnUpdate");
    ok(onDragUpdate ~= nil, "grab attaches the drag script");
    env.cursorX, env.cursorY = 512, 500;
    env:ClearViolations();
    onDragUpdate(input);
    ok(db.y == -268, "clear drag writes the Y", db.y);
    ok(pointOf(manager) == "TOPLEFT|UIParent|TOPLEFT|-7|-268", "manager follows", pointOf(manager));
    ok(pointOf(box) == pointOf(manager), "box follows the drag");
    ok(options.yBox:GetText() == "-268", "Y box updates live");
    ok(#env.restrictionViolations == 0, "clear drag touches no gates");
    onDragStop(input);
    ok(input:GetScript("OnUpdate") == nil, "release detaches the script");
    -- lock lands mid-drag: the gesture ends, nothing further persists
    onDragStart(input);
    env:ActivateAllRestrictions();
    env:ClearViolations();
    local frozen = db.y;
    onDragUpdate(input);
    ok(db.y == frozen, "locked frames persist nothing", db.y);
    onDragUpdate(input);
    ok(db.y == frozen, "repeat frames still persist nothing");
    ok(#env.restrictionViolations == 0, "mid-drag lock touches no gates");
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    env:FireEvent("PLAYER_REGEN_ENABLED");
    ok(#env.restrictionViolations == 0, "lift flush is clean");
    ok(pointOf(box) == pointOf(manager), "box re-synced on lift");
    -- entering move mode while locked is silently refused
    clickMove(); -- exit while clear
    ok(not box:IsShown(), "move mode exits while clear");
    env:ActivateAllRestrictions();
    env:ClearViolations();
    local base = #env.restrictionViolations;
    clickMove(); -- enter attempt while locked
    ok(not box:IsShown(), "locked enter refused (box stays hidden)");
    ok(options.moveBtn:GetText() == "move manager", "locked enter relabels nothing");
    ok(#newViolations(base) == 0, "locked enter logs nothing");
    env:DeactivateAllRestrictions();
    clickMove(); -- enter once clear again
    ok(box:IsShown(), "move mode enters after lift");
    -- the strip is dual-purpose: a press-and-move on the toggle button drags
    -- through the same shared endpoints (classic single button here)
    local toggle = manager.toggleButton;
    local stripDragStart = toggle:GetScript("OnDragStart");
    local stripDragStop = toggle:GetScript("OnDragStop");
    ok(stripDragStart ~= nil, "toggle carries a drag start (RegisterForDrag installed clear)");
    env.cursorX, env.cursorY = 512, 768 + db.y;
    env:ClearViolations();
    stripDragStart(toggle);
    env.cursorX, env.cursorY = 512, 400;
    input:GetScript("OnUpdate")(input);
    ok(db.y == -368, "strip drag writes the Y", db.y);
    ok(#env.restrictionViolations == 0, "strip drag touches no gates");
    stripDragStop(toggle);
    ok(input:GetScript("OnUpdate") == nil, "strip release detaches the shared script");
    -- the manager body itself initiates drags (covers the collapsed sliver
    -- the strip-excluding input leaves out); plain presses stay native
    local bodyDragStart = manager:GetScript("OnDragStart");
    local bodyDragStop = manager:GetScript("OnDragStop");
    ok(bodyDragStart ~= nil, "manager body carries a drag start (installed clear)");
    env.cursorX, env.cursorY = 512, 768 + db.y;
    env:ClearViolations();
    bodyDragStart(manager);
    env.cursorX, env.cursorY = 512, 450;
    input:GetScript("OnUpdate")(input);
    ok(db.y == -318, "body drag writes the Y", db.y);
    ok(#env.restrictionViolations == 0, "body drag touches no gates");
    bodyDragStop(manager);
    ok(input:GetScript("OnUpdate") == nil, "body release detaches the shared script");
    -- strip drag while locked refuses silently, and the native click (driven
    -- here as the stock handler, untainted in game) still toggles: the addon
    -- never intercepts it
    env:ActivateAllRestrictions();
    env:ClearViolations();
    local sbase = #env.restrictionViolations;
    local frozenY = db.y;
    stripDragStart(toggle);
    ok(db.y == frozenY, "locked strip drag persists nothing");
    ok(#newViolations(sbase) == 0, "locked strip grab logs nothing");
    env:DeactivateAllRestrictions();
    env:ClearViolations();
    -- GetScript itself is gated while locked, so the attach check runs here:
    -- a refused grab must have left no script behind
    ok(input:GetScript("OnUpdate") == nil, "refused grab attached nothing");
    -- toggle while move mode is on re-syncs the box at once (regression: it
    -- used to freeze on the old rect until the next drag)
    local toggleClick = toggle:GetScript("OnClick");
    toggleClick(toggle); -- collapse
    ok(pointOf(box) == pointOf(manager), "box follows the collapse at once");
    toggleClick(toggle); -- expand
    ok(pointOf(box) == pointOf(manager), "box follows the expand at once");
    -- roster rebuilds with move mode on re-sync the box without violations
    env:ClearViolations();
    local rbase = #env.restrictionViolations;
    env:FireEvent("GROUP_ROSTER_UPDATE");
    env:FireEvent("PARTY_LEADER_CHANGED");
    ok(pointOf(box) == pointOf(manager), "box still on the manager after roster");
    ok(#newViolations(rbase) == 0, "roster box-sync is clean");
    -- leaving the window leaves move mode
    onHide(options);
    ok(not box:IsShown() and not input:IsShown(), "window close exits move mode");
    env:ClearViolations();
end

env.rawPrint(("\nTest Results: %d passed, %d failed"):format(PASS, FAIL));
if FAIL > 0 then os.exit(1); end
