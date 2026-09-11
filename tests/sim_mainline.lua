--[[
    Integration Sim for Move Raid Manager -- modern client session
    (Blizzard_CompactRaidFrames Mainline family per source 12.1.0).
    Run with: lua5.1 tests/sim_mainline.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local lib = dofile("tests/lib.lua").init(env);
local out = env.rawPrint;
local ok, same, P = lib.ok, lib.same, lib.P;
local Boot, Slash, Window, TypeIn, Click, DriveMenu, PickMenuEntry
    = lib.Boot, lib.Slash, lib.Window, lib.TypeIn, lib.Click, lib.DriveMenu, lib.PickMenuEntry;

out("modern session:");

-- first login: stock placement, stock strata, silent except the tutorial
local manager, container = Boot(true);
local db = _G.Move_CompactRaidFrameManager;
local back, forward = manager.toggleButtonBack, manager.toggleButtonForward;
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -140 }),
    "out of the box the manager sits exactly where the game put it");
ok(manager:GetFrameStrata() == "MEDIUM", "out of the box the strata is the game's own");
ok(manager:GetAlpha() == 1 and container:GetAlpha() == 1, "nothing faded");
ok(#env.printLog == 2 and env.printLog[1]:find("/moverm", 1, true) ~= nil,
    "fresh install prints the chat instructions");

-- the player opens the window, lowers the manager and enables autohide; the
-- manager is collapsed after login, so it hides at once
local options = Window();
TypeIn(options.yBox, "-300");
Click(options.hideBox, true);
ok(manager:GetAlpha() == 0, "autohide on: collapsed manager fades as a whole");
ok(container:GetAlpha() == 1, "raid frames unaffected");

-- expanding shows it at the custom spot
back:GetScript("OnClick")(back); -- expand
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", 0, -300 }),
    "expanding keeps the moved Y and the modern x");
ok(manager:GetAlpha() == 1, "expanded manager fully visible");

-- the reported strata bug: raising the manager above the raid frames must
-- not drag the raid frames along, with the default layout anchoring the raid
-- frames to the manager
PickMenuEntry(DriveMenu(options.strataBtn), 7);
ok(manager:GetFrameStrata() == "FULLSCREEN_DIALOG" and container:GetFrameStrata() == "HIGH",
    "manager raised to FULLSCREEN_DIALOG, raid frames stay at HIGH");

-- collapsing fades it again even at the raised strata
forward:GetScript("OnClick")(forward); -- collapse
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -300 }),
    "collapsing keeps the moved Y and the modern x");
ok(manager:GetAlpha() == 0, "fade still applies at the new strata");

-- toggling hide off restores full visibility
Click(options.hideBox, false);
ok(manager:GetAlpha() == 1, "hide off shows the manager again");
Slash(""); -- close the window when done

-- UI reload keeps everything exactly as left
env:Reset();
manager, container = Boot(true, true);
db = _G.Move_CompactRaidFrameManager;
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -300 }),
    "reload restores the spot over the collapsed re-anchor");
ok(manager:GetFrameStrata() == "FULLSCREEN_DIALOG" and container:GetFrameStrata() == "HIGH",
    "reload restores the strata split");
ok(manager:GetAlpha() == 1, "reload restores the fade state");

-- /moverm reset hands everything back to the game
Slash("reset");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -200, -140 })
    and manager:GetFrameStrata() == "MEDIUM" and container:GetFrameStrata() == "HIGH",
    "reset restores the game's defaults");

lib.done();
