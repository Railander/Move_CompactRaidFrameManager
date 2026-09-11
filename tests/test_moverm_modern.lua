--[[
    Unit tests for Move Raid Manager -- modern family specifics
    (container is a UIParent sibling, per source 12.1.0 Mainline).
    Run with: lua5.1 tests/test_moverm_modern.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local lib = dofile("tests/lib.lua").init(env);
local out = env.rawPrint;
local ok, same, P = lib.ok, lib.same, lib.P;
local Boot, Slash, Window, TypeIn, Click, DriveMenu, PickMenuEntry
    = lib.Boot, lib.Slash, lib.Window, lib.TypeIn, lib.Click, lib.DriveMenu, lib.PickMenuEntry;

out("modern family:");

local manager, container = Boot(true);
local db = _G.Move_CompactRaidFrameManager;

ok(container:GetParent() == UIParent and container:GetParent() ~= manager,
    "world mirrors the modern sibling container");
ok(db.y == -140 and db.strata == 3, "fresh defaults: stock Y and strata preselected (MEDIUM)");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -140 }),
    "fresh install keeps the game's own anchor (collapsed after login)");

-- whole-frame fade: the manager is faded as one, raid frames untouched
local options = Window();
Click(options.hideBox, true);
ok(manager:GetAlpha() == 0, "collapsed + hide hides the whole manager frame");
ok(container:GetAlpha() == 1, "raid frames are never faded");
manager._mouseOver = true;
manager:GetScript("OnEnter")(manager);
ok(manager:GetAlpha() == 1, "hover brings the manager back");
manager._mouseOver = false;

-- both modern toggle buttons drive expand/collapse and keep the moved Y
TypeIn(options.yBox, "-234.5");
local forward, back = manager.toggleButtonForward, manager.toggleButtonBack;
back:GetScript("OnClick")(back); -- expand
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", 0, -234.5 }),
    "expand keeps the moved Y and the modern x");
ok(manager:GetAlpha() == 1, "expanding ends the fade");
forward:GetScript("OnClick")(forward); -- collapse
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -234.5 }),
    "collapse keeps the moved Y and the modern x");
ok(manager:GetAlpha() == 0, "collapsing fades again");

-- strata: manager only; the sibling container is re-pinned regardless
PickMenuEntry(DriveMenu(options.strataBtn), 8);
ok(manager:GetFrameStrata() == "TOOLTIP", "strata applies to the manager");
ok(container:GetFrameStrata() == "HIGH", "raid frames keep their own strata (the strata bug)");

-- reset restores the modern stock strata and placement
Slash("reset");
ok(db.y == -140 and db.fade == false and db.strata == 3,
    "reset clears every saved setting (strata back to stock MEDIUM)");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -140 }),
    "reset restores the game's own placement");
ok(manager:GetFrameStrata() == "MEDIUM" and container:GetFrameStrata() == "HIGH",
    "reset restores the game's own strata split");
ok(manager:GetAlpha() == 1, "reset ends the fade");

lib.done();
