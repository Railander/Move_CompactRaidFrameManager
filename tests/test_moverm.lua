--[[
    Unit tests for Move Raid Manager -- classic family core + config window
    (container is the manager's child at the default spot, like 1.15/2.5/5.5).
    Run with: lua5.1 tests/test_moverm.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local lib = dofile("tests/lib.lua").init(env);
local out = env.rawPrint;
local ok, same, P = lib.ok, lib.same, lib.P;
local Boot, Slash, Window, TypeIn, Click, DriveMenu, PickMenuEntry
    = lib.Boot, lib.Slash, lib.Window, lib.TypeIn, lib.Click, lib.DriveMenu, lib.PickMenuEntry;

local function ArtAlpha(art)
    local a = art[1]:GetAlpha();
    for _, region in ipairs(art) do
        if region:GetAlpha() ~= a then
            return "mixed";
        end
    end
    return a;
end

-- ----------------------------------------------------------------------------
-- boot and the window
-- ----------------------------------------------------------------------------
out("classic family:");

local manager, container, art, artByName = Boot(false);
local db = _G.Move_CompactRaidFrameManager;

ok(#env.printLog == 2 and env.printLog[1]:find("/moverm", 1, true) ~= nil,
    "fresh install prints the chat instructions", #env.printLog);
ok(db.y == -140 and db.fade == false and db.strata == 2,
    "fresh defaults: game's own Y, no fade, stock strata preselected (LOW)");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -140 }),
    "fresh install keeps the game's own anchor (collapsed after login)");
ok(manager:GetFrameStrata() == "LOW", "fresh install keeps the game's own strata");
ok(container:GetParent() == manager, "world mirrors the classic reparent");

local options = Window();
ok(options ~= nil and options:IsShown(), "/moverm opens the config window");
ok(options.yBox and options.hideBox and options.strataBtn,
    "window has the Y box, hide checkbox and strata picker");
ok(db.win.x == 0 and db.win.y == 0, "window starts centered");
Slash("");
ok(not options:IsShown(), "/moverm again closes it");
Slash("garbage");
ok(options:IsShown(), "unrecognized input opens the window");

-- ----------------------------------------------------------------------------
-- position: the Y box
-- ----------------------------------------------------------------------------
TypeIn(options.yBox, "-234.5");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -234.5 }),
    "Y box moves the manager, x preserved");
ok(db.y == -234.5 and options.yBox:GetText() == "-234.5",
    "Y box saved verbatim (fractional values kept)");

TypeIn(options.yBox, "-300");
ok(db.y == -300 and same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -300 }),
    "Y box moves the manager again");

-- the game's own expand/collapse keeps the moved Y without any hook
local toggleButton = manager.toggleButton;
toggleButton:GetScript("OnClick")(toggleButton); -- expand
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -7, -300 }),
    "expand re-anchor keeps the moved Y");
toggleButton:GetScript("OnClick")(toggleButton); -- collapse
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -300 }),
    "collapse re-anchor keeps the moved Y");

-- ----------------------------------------------------------------------------
-- autohide: fade targets the manager's own art only, never the raid frames
-- ----------------------------------------------------------------------------
Click(options.hideBox, true);
ok(ArtAlpha(art) == 0 and toggleButton:GetAlpha() == 0, "collapsed + hide hides the manager art");
ok(container:GetAlpha() == 1 and manager.displayFrame:GetAlpha() == 1,
    "raid frames and options panel are never faded");
manager._mouseOver = true;
manager:GetScript("OnEnter")(manager);
ok(ArtAlpha(art) == 1, "hovering the collapsed strip brings it back");
manager._mouseOver = false;
manager:GetScript("OnLeave")(manager);
ok(ArtAlpha(art) == 0, "leaving it hides it again");
toggleButton:GetScript("OnClick")(toggleButton); -- expand recomputes through the click hook
ok(ArtAlpha(art) == 1, "expanding ends the fade");
Click(options.hideBox, false);
toggleButton:GetScript("OnClick")(toggleButton); -- collapse
ok(ArtAlpha(art) == 1, "hide off keeps everything visible");

-- moving the raid frames away in edit mode breaks the classic parent link;
-- the fade must keep targeting only the manager's own art either way
Click(options.hideBox, true); -- collapsed right now, so the manager hides at once
container:SetParent(UIParent);
ok(ArtAlpha(art) == 0 and container:GetAlpha() == 1,
    "raid frames moved away: collapsed fade still hides only the manager");
manager._mouseOver = true;
manager:GetScript("OnEnter")(manager);
ok(ArtAlpha(art) == 1, "raid frames moved away: hover still reveals the manager");
manager._mouseOver = false;
manager:GetScript("OnLeave")(manager);
ok(ArtAlpha(art) == 0, "raid frames moved away: leaving hides it again");
Click(options.hideBox, false);

-- ----------------------------------------------------------------------------
-- strata: dropdown drives the manager only, the raid frames are pinned
-- ----------------------------------------------------------------------------
local root = DriveMenu(options.strataBtn);
ok(#root == 8, "strata menu lists the 8 real values (game default preselected, no placeholder)");
for _, entry in ipairs(root) do
	if entry.data == 2 then
		ok(entry.isSelected(entry.data), "stock LOW preselected on classic");
	end
end
PickMenuEntry(root, 6);
ok(manager:GetFrameStrata() == "FULLSCREEN", "picking FULLSCREEN applies to the manager");
ok(container:GetFrameStrata() == "HIGH", "raid frames keep their own strata (the strata bug)");
PickMenuEntry(root, 8);
ok(manager:GetFrameStrata() == "TOOLTIP" and container:GetFrameStrata() == "HIGH",
    "higher strata still leaves the raid frames alone");
PickMenuEntry(root, 2);
ok(manager:GetFrameStrata() == "LOW" and container:GetFrameStrata() == "HIGH",
    "back to LOW restores the stock strata");
PickMenuEntry(root, 1);
ok(manager:GetFrameStrata() == "BACKGROUND", "a strata can be picked again");

-- ----------------------------------------------------------------------------
-- reset and reload
-- ----------------------------------------------------------------------------
TypeIn(options.yBox, "-500");
Click(options.hideBox, true);
Slash("reset");
ok(db.y == -140 and db.fade == false and db.strata == 2,
    "reset clears every saved setting (strata back to stock LOW)");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -140 }),
    "reset restores the game's own placement");
ok(manager:GetFrameStrata() == "LOW" and container:GetFrameStrata() == "HIGH",
    "reset restores the game's own strata split");
ok(ArtAlpha(art) == 1, "reset ends the fade");

-- reset forces the Y box even past the conditional refresh: a format-equal
-- string ("-140.0") or a focused box would otherwise keep showing stale text
-- live (the slash self-heal runs first, so the trap is laid after it: stock
-- db.y with a differently-formatted, focused box)
TypeIn(options.yBox, "-140");
options.yBox:SetText("-140.0"); -- tonumber-equal to db.y, string-different
options.yBox:SetFocus();
Slash("reset");
ok(db.y == -140, "reset restores the default Y");
ok(options.yBox:GetText() == "-140", "reset rewrites a format-equal box");
ok(options.yBox:HasFocus() == false, "reset releases box focus");

-- reload round-trip: settings persist and re-apply on the fresh world
Slash(""); -- close the window so reopen state is testable
options = Window();
TypeIn(options.yBox, "-234.5");
Click(options.hideBox, true);
PickMenuEntry(DriveMenu(options.strataBtn), 1);
Slash(""); -- close
env:Reset();
manager, container, art, artByName = Boot(false, true);
db = _G.Move_CompactRaidFrameManager;
ok(#env.printLog == 0, "reload does not reprint the instructions");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -234.5 }),
    "reload reapplies the moved Y over the collapse re-anchor");
ok(ArtAlpha(art) == 0, "reload reapplies the fade");
ok(manager:GetFrameStrata() == "BACKGROUND" and container:GetFrameStrata() == "HIGH",
    "reload reapplies the strata and the raid frame pin");
options = Window();
ok(options.strataBtn:GetText() == "BACKGROUND", "window shows the saved strata");

-- a corrupt saved table falls back to sane values
env:Reset();
_G.Move_CompactRaidFrameManager = { y = "not-a-number", fade = 1, strata = 99, win = "junk", side = "right", mirror = true };
manager, container, art = Boot(false, true);
db = _G.Move_CompactRaidFrameManager;
ok(db.y == -140 and db.fade == true and db.strata == 2
    and type(db.win) == "table" and db.win.x == 0,
    "corrupt values fall back (y stock, fade coerced, strata back to stock, win rebuilt)");
ok(db.side == nil and db.mirror == nil, "scrapped beta keys are dropped");
ok(manager:GetFrameStrata() == "LOW", "dropped strata keeps the game's own");

-- a v1 table (old CLI-only addon: exactly { y, fade, strata }) carries over:
-- position, fade and strata keep working, the new keys backfill, no re-greet
env:Reset();
_G.Move_CompactRaidFrameManager = { y = -234.5, fade = true, strata = 6 };
manager, container, art = Boot(false, true);
db = _G.Move_CompactRaidFrameManager;
ok(#env.printLog == 0, "v1 carryover does not reprint the instructions");
ok(db.y == -234.5 and db.fade == true and db.strata == 6
    and type(db.win) == "table" and db.win.x == 0 and db.win.y == 0,
    "v1 values preserved, new keys backfilled");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -234.5 }),
    "v1 Y applied over the collapse re-anchor");
ok(ArtAlpha(art) == 0, "v1 fade applied");
ok(manager:GetFrameStrata() == "FULLSCREEN" and container:GetFrameStrata() == "HIGH",
    "v1 strata applied, raid frames re-pinned");

lib.done();
