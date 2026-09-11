--[[
    Unit tests for Move Raid Manager -- move mode (drag the manager up/down).
    Run with: lua5.1 tests/test_moverm_move.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local lib = dofile("tests/lib.lua").init(env);
local out = env.rawPrint;
local ok, same, P = lib.ok, lib.same, lib.P;
local Boot, Slash, Window, TypeIn, Click
    = lib.Boot, lib.Slash, lib.Window, lib.TypeIn, lib.Click;

_G.UIParent:SetSize(1024, 768);

-- ----------------------------------------------------------------------------
-- static hygiene: the addon must not leak globals (a bare `moveBox`-style
-- typo silently shares state across /reloads: the second boot reuses the
-- first boot's orphaned frames). luac lists every global store; the only
-- legal one is the client's slash registration. It also lists every global
-- READ: any MoveRM_-prefixed read is a missed forward declaration (a later
-- `local` the earlier code cannot see -- silently nil, like the heal crash).
-- Runs first so either failure lands precisely here instead of downstream.
-- ----------------------------------------------------------------------------
out("global hygiene:");

do
	local pipe = io.popen("luac -l -p Move_CompactRaidFrameManager.lua 2>&1");
	ok(pipe ~= nil, "luac listing runs");
	if pipe then
		local listing = pipe:read("*a");
		pipe:close();
		local leaks = {};
		for name in listing:gmatch("SETGLOBAL%s+%d+%s+%-?%d+%s+;%s+([A-Za-z_][A-Za-z0-9_]*)") do
			if name ~= "SLASH_MOVERM1" then
				leaks[#leaks + 1] = name;
			end
		end
		ok(#leaks == 0, "no leaked globals (only SLASH_MOVERM1)", table.concat(leaks, ","));
		local early = {};
		for name in listing:gmatch("GETGLOBAL%s+%d+%s+%-?%d+%s+;%s+(MoveRM_[A-Za-z0-9_]*)") do
			early[#early + 1] = name;
		end
		ok(#early == 0, "no early globals (all MoveRM_ refs are locals)", table.concat(early, ","));
	end
end

local function BoxOf()
    return env:FindFrame("Move_CompactRaidFrameManagerMoveBox");
end

local function InputOf()
    return env:FindFrame("Move_CompactRaidFrameManagerMoveInput");
end

-- ----------------------------------------------------------------------------
-- move mode on the classic family
-- ----------------------------------------------------------------------------
out("move mode:");

local manager, container = Boot(false);
local db = _G.Move_CompactRaidFrameManager;
local options = Window();
local toggleButton = manager.toggleButton;

ok(options.moveBtn ~= nil and options.moveBtn:GetText() == "move manager",
    "window has the move button, labelled for entry");
ok(BoxOf() == nil, "box and input are built lazily, not at login");

Click(options.moveBtn);
local box, input = BoxOf(), InputOf();
ok(box ~= nil and input ~= nil and box:IsShown() and input:IsShown(),
    "move button shows the box and the input");
ok(options.moveBtn:GetText() == "stop moving", "button relabels while moving");
ok(same(P(box), P(manager)), "box copies the manager's anchor");
ok(box:GetWidth() == manager:GetWidth() and box:GetHeight() == manager:GetHeight(),
    "box copies the manager's size");
ok(box:GetFrameStrata() == "BACKGROUND", "box sits below (BACKGROUND)");
ok(manager:GetFrameStrata() == "LOW", "manager overlays the box");
ok(input:GetFrameStrata() == "TOOLTIP", "input sits above for grabs");
local boxTex = ({ box:GetRegions() })[1];
ok(boxTex ~= nil and boxTex.r == 0 and boxTex.g == 1 and boxTex.b == 0 and boxTex.a == 0.5,
    "box is the 50% green marker");

-- drag: grab the anchor exactly, move the cursor, the Y follows
env.cursorX, env.cursorY = 512, 768 + db.y; -- cursor right on the anchor
input:GetScript("OnDragStart")(input);
ok(input:GetScript("OnUpdate") ~= nil, "grab attaches the drag script");
env.cursorX, env.cursorY = 512, 528;
input:GetScript("OnUpdate")(input);
ok(db.y == -240, "drag writes the Y (cursor-driven, vertical only)", db.y);
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -240 }),
    "manager follows, X preserved");
ok(same(P(box), P(manager)), "box follows the manager");
ok(options.yBox:GetText() == "-240", "Y box updates live while dragging");
input:GetScript("OnDragStop")(input);
ok(input:GetScript("OnUpdate") == nil, "release detaches the drag script");

-- typing while move mode is on moves the box too
TypeIn(options.yBox, "-300");
ok(same(P(box), { "TOPLEFT", "UIParent", "TOPLEFT", -182, -300 }),
    "box follows typed changes");

-- the toggle strip stays clickable: the input covers everything EXCEPT the
-- strip column (anchored to the toggle button's far edge, full height)
ok(input:GetNumPoints() == 4, "input uses four anchors, not the manager rect");
do
	local p1, rt1, rp1 = input:GetPoint(1);
	local p3, rt3, rp3 = input:GetPoint(3);
	ok(p1 == "TOPLEFT" and rt1 == manager and rp1 == "TOPLEFT",
	    "input starts at the manager's far edge");
	ok(p3 == "TOPRIGHT" and rt3 == toggleButton and rp3 == "TOPLEFT",
	    "input stops at the toggle strip");
end

-- toggling expand keeps the drag spot (X belongs to the stock anchor)
toggleButton:GetScript("OnClick")(toggleButton); -- expand
ok(same(P(manager), { "TOPLEFT", "UIParent", "TOPLEFT", -7, -300 }),
    "expand keeps the dragged Y");

-- ----------------------------------------------------------------------------
-- the box follows expand/collapse (regression: it used to freeze on the old
-- rect until the next drag -- and collapsed, the stale box misled grabs
-- while only the toggle strip stayed draggable)
-- ----------------------------------------------------------------------------
out("box follows toggle:");

ok(BoxOf():IsShown(), "precondition: move mode on");
toggleButton:GetScript("OnClick")(toggleButton); -- collapse
ok(manager.collapsed == true, "collapsed");
ok(same(P(box), P(manager)), "box follows the collapse at once");
ok(box:GetWidth() == manager:GetWidth() and box:GetHeight() == manager:GetHeight(),
    "box copies the collapsed size at once");
-- collapsed dragging works from the small input and from the strip alike
env.cursorX, env.cursorY = 512, 768 + db.y;
input:GetScript("OnDragStart")(input);
env.cursorX, env.cursorY = 512, 608;
input:GetScript("OnUpdate")(input);
ok(db.y == -160, "collapsed input drag writes the Y", db.y);
ok(same(P(box), P(manager)), "box follows the collapsed drag");
input:GetScript("OnDragStop")(input);
toggleButton:GetScript("OnClick")(toggleButton); -- expand
ok(manager.collapsed == false, "expanded again");
ok(same(P(box), P(manager)), "box follows the expand at once");

-- leaving the window leaves move mode
options:Hide();
options:GetScript("OnHide")(options);
ok(not box:IsShown() and not input:IsShown(), "closing the window hides the box and input");
ok(options.moveBtn:GetText() == "move manager", "button relabels on exit");
Slash(""); -- reopen for the reset check
ok(options.moveBtn:GetText() == "move manager", "reopen shows the entry label");

-- reset refreshes the window (and would re-sync an open box)
TypeIn(options.yBox, "-500");
Click(options.hideBox, true);
Slash("reset");
ok(options.yBox:GetText() == "-140", "reset refreshes the Y box");
ok(options.hideBox:GetChecked() == false, "reset refreshes the hide checkbox");
ok(options.strataBtn:GetText() == "LOW", "reset refreshes the strata picker");

-- ----------------------------------------------------------------------------
-- reset returns every value (window position and move mode included)
-- ----------------------------------------------------------------------------
out("reset all:");

db.win = { x = 50, y = 60 }; -- a previously moved window
Click(options.moveBtn); -- move mode on
ok(BoxOf():IsShown(), "precondition: move mode on");
Slash("reset");
ok(db.y == -140 and db.fade == false and db.strata == 2,
    "reset clears the manager values (strata back to stock LOW)");
ok(db.win.x == 0 and db.win.y == 0, "reset clears the window position");
ok(same(P(options), { "CENTER", "UIParent", "CENTER", 0, 0 }), "window re-anchored center");
ok(BoxOf():IsShown(), "reset keeps move mode on (values only)");
ok(same(P(BoxOf()), P(manager)), "box follows the reset spot");
ok(options.moveBtn:GetText() == "stop moving", "button stays on the moving label");
ok(options.yBox:GetText() == "-140", "window rows follow the reset");

-- ----------------------------------------------------------------------------
-- strip drag: the toggle buttons are dual-purpose -- a plain press runs the
-- stock click natively, a press-and-move drags the manager (move mode only)
-- ----------------------------------------------------------------------------
out("strip drag:");

ok(BoxOf():IsShown(), "precondition: move mode on");
ok(manager.collapsed == false, "precondition: expanded");
toggleButton:GetScript("OnClick")(toggleButton); -- collapse, move mode on
ok(manager.collapsed == true and db.y == -140, "native click collapses with move mode on");
-- grab on the toggle button itself; motion runs on the shared input script
env.cursorX, env.cursorY = 512, 768 + db.y;
toggleButton:GetScript("OnDragStart")(toggleButton);
ok(InputOf():GetScript("OnUpdate") ~= nil, "strip grab attaches the shared drag script");
env.cursorX, env.cursorY = 512, 468;
InputOf():GetScript("OnUpdate")(InputOf());
ok(db.y == -300, "strip drag writes the Y", db.y);
ok(same(P(BoxOf()), P(manager)), "box follows the strip drag");
toggleButton:GetScript("OnDragStop")(toggleButton);
ok(InputOf():GetScript("OnUpdate") == nil, "strip release detaches the script");
-- outside move mode the strip is click-only, as stock
Click(options.moveBtn); -- move mode off
ok(not BoxOf():IsShown(), "move mode off");
env.cursorX, env.cursorY = 512, 768 + db.y;
toggleButton:GetScript("OnDragStart")(toggleButton);
ok(InputOf():GetScript("OnUpdate") == nil, "strip grab ignored outside move mode");
ok(db.y == -300, "no Y change outside move mode");
toggleButton:GetScript("OnClick")(toggleButton); -- expand, click-only
ok(manager.collapsed == false, "click-only strip expands natively");
toggleButton:GetScript("OnClick")(toggleButton); -- collapse, tidy for fallback
ok(manager.collapsed == true, "click-only strip collapses natively");

-- ----------------------------------------------------------------------------
-- collapsed body drag: the input leaves the strip column out, so when only
-- the strip shows, the visible sliver is manager body with no input above
-- it -- the manager frame itself initiates those drags (regression: only
-- the button dragged while collapsed)
-- ----------------------------------------------------------------------------
out("collapsed body drag:");

Click(options.moveBtn); -- move mode on again
ok(BoxOf():IsShown(), "precondition: move mode on");
ok(manager.collapsed == true, "precondition: collapsed");
env.cursorX, env.cursorY = 512, 768 + db.y;
manager:GetScript("OnDragStart")(manager);
ok(InputOf():GetScript("OnUpdate") ~= nil, "body grab attaches the shared drag script");
env.cursorX, env.cursorY = 512, 668;
InputOf():GetScript("OnUpdate")(InputOf());
ok(db.y == -100, "body drag writes the Y", db.y);
ok(same(P(BoxOf()), P(manager)), "box follows the body drag");
manager:GetScript("OnDragStop")(manager);
ok(InputOf():GetScript("OnUpdate") == nil, "body release detaches the script");
-- outside move mode the body is stock (no click action, no drag)
Click(options.moveBtn); -- move mode off
env.cursorX, env.cursorY = 512, 768 + db.y;
manager:GetScript("OnDragStart")(manager);
ok(InputOf():GetScript("OnUpdate") == nil, "body grab ignored outside move mode");
ok(db.y == -100, "no Y change outside move mode");

-- ----------------------------------------------------------------------------
-- fallback pickers (clients without the dropdown template)
-- ----------------------------------------------------------------------------
out("fallback pickers:");

env:Reset();
env.failTemplates = { "WowStyle1DropdownTemplate" };
manager, container = Boot(false);
db = _G.Move_CompactRaidFrameManager;
options = Window();
ok(options.strataBtn ~= nil and options.strataBtn.SetupMenu == nil,
    "without the template the strata fallback builds");
Click(options.strataBtn);
ok(db.strata == 3 and manager:GetFrameStrata() == "MEDIUM", "fallback cycles forward from stock");
ok(options.strataBtn:GetText() == "MEDIUM", "fallback label follows");
db.strata = 8; -- park at the top, cycle wraps to the bottom (never a placeholder)
Click(options.strataBtn);
ok(db.strata == 1 and manager:GetFrameStrata() == "BACKGROUND", "fallback wraps around");
Click(options.moveBtn);
ok(BoxOf():IsShown(), "move mode works with the fallback picker");

lib.done();
