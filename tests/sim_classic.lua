--[[
    Integration Sim for Move Raid Manager -- classic client session
    (Blizzard_CompactRaidFrames Classic family per source 1.15.9/5.5.4).
    Run with: lua5.1 tests/sim_classic.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local lib = dofile("tests/lib.lua").init(env);
local out = env.rawPrint;
local ok, same, P = lib.ok, lib.same, lib.P;
local Boot, Slash, Window, TypeIn, Click, DriveMenu, PickMenuEntry
    = lib.Boot, lib.Slash, lib.Window, lib.TypeIn, lib.Click, lib.DriveMenu, lib.PickMenuEntry;

out("classic session:");

-- first login: the addon stays out of the game's way
local manager, container, art = Boot(false);
local db = _G.Move_CompactRaidFrameManager;
local toggleButton = manager.toggleButton;
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -140 }),
    "out of the box the manager sits exactly where the game put it");
ok(art[1]:GetAlpha() == 1, "out of the box nothing is faded");
ok(container:GetFrameStrata() == "HIGH" and manager:GetFrameStrata() == "LOW",
    "out of the box both stratas are the game's own");
ok(#env.printLog == 2 and env.printLog[1]:find("/moverm", 1, true) ~= nil,
    "fresh install prints the chat instructions");

-- the player opens the window, moves the manager up and turns on autohide;
-- the manager is collapsed after login, so it hides at once
local options = Window();
TypeIn(options.yBox, "-120.5");
Click(options.hideBox, true);
ok(art[1]:GetAlpha() == 0 and container:GetAlpha() == 1,
    "autohide on: collapsed manager hides, raid frames stay up");

-- opening it for roster checks keeps the custom spot
toggleButton:GetScript("OnClick")(toggleButton); -- expand
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -7, -120.5 }),
    "expanding keeps the moved Y");
ok(art[1]:GetAlpha() == 1, "expanded manager fully visible");

-- collapsing hides it again
toggleButton:GetScript("OnClick")(toggleButton); -- collapse
ok(art[1]:GetAlpha() == 0, "collapsed manager hides itself");

-- hovering the hidden strip brings it back, moving on hides it
manager._mouseOver = true;
manager:GetScript("OnEnter")(manager);
ok(art[1]:GetAlpha() == 1, "hover reveals the manager");
manager._mouseOver = false;
manager:GetScript("OnLeave")(manager);
ok(art[1]:GetAlpha() == 0, "moving on hides it again");

-- the leader raises the manager above other UI without touching the raid frames
PickMenuEntry(DriveMenu(options.strataBtn), 5);
ok(manager:GetFrameStrata() == "DIALOG" and container:GetFrameStrata() == "HIGH",
    "manager strata raised, raid frames untouched");
toggleButton:GetScript("OnClick")(toggleButton); -- expand to use it
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -7, -120.5 }),
    "expanding at the new strata keeps the custom spot");
ok(art[1]:GetAlpha() == 1, "expanded manager fully visible at the new strata");
Slash(""); -- close the window when done

-- UI reload keeps everything exactly as left (the fresh world boots collapsed)
env:Reset();
manager, container, art = Boot(false, true);
db = _G.Move_CompactRaidFrameManager;
toggleButton = manager.toggleButton;
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -120.5 }),
    "reload restores the spot over the collapsed re-anchor");
ok(art[1]:GetAlpha() == 0, "reload restores the autohide state");
ok(manager:GetFrameStrata() == "DIALOG" and container:GetFrameStrata() == "HIGH",
    "reload restores the strata split");
ok(#env.printLog == 0, "reload stays silent");

-- /moverm reset hands everything back to the game
Slash("reset");
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -140 })
    and art[1]:GetAlpha() == 1
    and manager:GetFrameStrata() == "LOW" and container:GetFrameStrata() == "HIGH",
    "reset restores the game's defaults");

lib.done();
