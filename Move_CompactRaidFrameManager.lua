-- Move Raid Manager
-- Moves, autohides and re-stratas the game's default raid manager
-- (CompactRaidFrameManager) on every version of the game. One shared
-- implementation; the two client families are told apart by the manager's
-- toggle buttons, which nothing in the game can change at runtime:
--   * modern clients: one toggle strip back/forward pair, and the raid frame
--     container stays a sibling of the manager (both parented to UIParent) at
--     all times, so the manager frame is faded as a whole
--   * classic clients: a single toggle button, and the container is
--     reparented UNDER the manager while the raid frames sit in their default
--     spot next to it (moving the raid frames away in edit mode breaks that
--     link), so the fade targets the manager's own artwork and toggle button
--     instead -- correct either way, since that is all that is visible while
--     collapsed
-- The game re-anchors the manager on every expand/collapse, and only there;
-- post-hooks on the toggle buttons re-apply the saved vertical offset after
-- those re-anchors, so the offset survives with no override of the manager's
-- own methods and no polling. Appliers that find Blizzard's layout already
-- exactly in place return without writing a thing, so default settings leave
-- the game's frames pixel-identical. Everything is event driven: no polling
-- and no per-frame code. /moverm opens the config window, /moverm reset
-- restores the game's defaults. The strata stays at the game's own default
-- until one is chosen, and changing it never touches the raid frames' own
-- strata.
--
-- Midnight (12.x) gate discipline, retail flavor only: there is none. Tainted
-- calls on secret-clean objects serve under any restriction state
-- (live-verified 2026-09-12, all six types forced: drags, settings, strata
-- writes, installs, all clean), and nothing this addon touches can become
-- secret-marked (it ingests no unit/combat/aura data; Blizzard doesn't mark
-- chrome). So every op below just attempts -- no flag checks, no mark checks,
-- no pcall, no read-back verification, no queues. If the engine ever refuses,
-- it errors LOUDLY (Bugsack, not silence), which is exactly what we want: a
-- silent queue would hide the bug forever, an error gets reported and fixed.
-- The only guards left are crash-safety (nil results abort geometry) and
-- correctness (the already-there early-out keeps default settings from
-- touching Blizzard's anchors at all). Classic flavors run the same code.
-- Safe everywhere: SetAlpha, FontString:SetText, Show/Hide, db work. Chat
-- tutorial prints best-effort always (a swallowed line under Chat lockdown is
-- harmless -- it is never load-bearing).

local ADDON_NAME = "Move_CompactRaidFrameManager";

-- Blizzard's CompactRaidFrames addon loads before user addons, so the frames
-- normally exist at file scope; on an unknown layout stay inert (the slash
-- handler retries, so a late-loading manager still boots)
local manager = CompactRaidFrameManager;
local container = CompactRaidFrameContainer;
if not (manager and container) then
	return;
end

-- ingame instructions, in the same scheme as the other Move_* addons
local exitColor = "|r";
local colorOrange = "|cFFDF9F1F";
local function MoveRM_instructions()
	-- commands sit outside the color spans, so they render in the chat's
	-- default white while the surrounding text stays orange
	print(colorOrange .. "Use " .. exitColor .. "/moverm" .. colorOrange .. " to open the configuration window." .. exitColor);
	print(colorOrange .. "Use " .. exitColor .. "/moverm reset" .. colorOrange .. " to restore the game's defaults." .. exitColor);
end

local STRATAS = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" };
local MAX_STRATA = #STRATAS;
local MAX_COORD = 100000;

-- Rounds to 2 decimals (declared HERE, above every storer: stock capture,
-- reset and sanitize all persist coordinates, and the client's float32 layout
-- math hands GetPoint values like -140.00001525879 back -- without rounding
-- that 16-char string overflows the 9-char Y box, which then shows its
-- scrolled tail "0.0000" while GetText still reads fine).
local function MoveRM_Round2(v)
	return math.floor(v * 100 + 0.5) / 100;
end

local db; -- alias for the Move_CompactRaidFrameManager SavedVariables table, set on ADDON_LOADED
local options, refreshWindow; -- config window and its refresher, built below

-- Install state. Declared HERE, above every function that reads or writes
-- them: Lua upvalues bind at closure creation, so a later `local` would leave
-- earlier paths writing to a same-named global instead.
local MoveRM_stateLoaded = false; -- db backfilled (pure Lua, always runs)
local MoveRM_hooksInstalled = false; -- post-hooks attempted once (HookScript chains)
local MoveRM_captured = false; -- stock captured once (recapturing would adopt our moves)
local MoveRM_moveModeOn = false; -- move mode: the green box + drag input are shown
local MoveRM_moveDragging = false; -- a drag gesture is in flight (OnUpdate early-returns without it)
local MoveRM_moveBox; -- green 50% box under the manager, marking its rect
local MoveRM_moveInput; -- transparent drag input above the manager
local MoveRM_grabDY; -- cursor offset from the manager's anchor Y at grab time
-- Forward declarations: assigned further below, called from early paths and
-- mid-file appliers (bound here so they resolve correctly).
local MoveRM_EnsureInit;
local MoveRM_RegisterAddonEvents;
local MoveRM_DetachDrag;
local MoveRM_DragUpdate;
local MoveRM_SetMoveMode;
local MoveRM_BeginDrag;
local MoveRM_EndDrag;
local MoveRM_SyncMoveBox;
local MoveRM_EventFrame; -- listener frame, created at file load below

-- stock layout, captured once on init (recapturing later would adopt our
-- own moves as the game's)
local stockY = -140; -- the game's own vertical placement (both states sit at -140)
local stockStrata; -- the game's own strata
local stockStrataIndex = 2; -- db.strata value matching stockStrata (resolved at capture)
-- the strata setting belongs to the raid manager alone: the raid frames' own
-- strata is remembered so a change to the manager's can never drag them along
local containerStrata; -- the raid frames' own strata, re-asserted after every manager change
-- the container being the manager's child cannot tell the families apart:
-- classic only keeps it that way while the raid frames sit in their default
-- spot (see the header). The toggle buttons are the stable marker: one button
-- on classic, a back/forward pair on modern
local managerFadesAsWhole; -- modern family (no single toggle button): fade the manager frame
local fadeRegions; -- classic family: the manager's own artwork plus its toggle button

-- Capture the stock layout: the game's own placement and strata, the client
-- family, and the fade list. Runs once (stock must predate our own moves --
-- recapturing later would adopt our offset as the game's). The flag is managed
-- by EnsureInit, which only sets it once the strata read lands (nil stock
-- would poison reset, so a nil read simply retries next init).
local function MoveRM_CaptureStock()
	stockY = MoveRM_Round2(select(5, manager:GetPoint(1)) or -140);
	stockStrata = manager:GetFrameStrata();
	containerStrata = container:GetFrameStrata();
	-- resolve the stock strata to a picker index (LOW on classic, MEDIUM on
	-- retail): the picker lists real values only, preselected to the game's
	-- own, so db.strata is never nil once backfilled below
	stockStrataIndex = 2;
	for i, name in ipairs(STRATAS) do
		if name == stockStrata then
			stockStrataIndex = i;
			break;
		end
	end
	managerFadesAsWhole = manager.toggleButton == nil;
	if not managerFadesAsWhole then
		fadeRegions = {};
		for _, region in ipairs({ manager:GetRegions() }) do
			if region:IsObjectType("Texture") then
				fadeRegions[#fadeRegions + 1] = region;
			end
		end
		if manager.toggleButton then
			fadeRegions[#fadeRegions + 1] = manager.toggleButton;
		end
	end
end

-- core behavior: every op below just attempts. A call from any path --
-- hooks, slash, options, events -- runs the same straight-line code; there
-- is no lock state, no queue, nothing to flush
-- ----------------------------------------------------------------------------
local function MoveRM_SetAlpha(alpha)
	if managerFadesAsWhole then
		manager:SetAlpha(alpha);
		return;
	end
	for _, region in ipairs(fadeRegions) do
		region:SetAlpha(alpha);
	end
end

-- Hover covers the manager body AND its toggle strip: sliding from the body
-- onto the expand/collapse button fires the manager's OnLeave (the child
-- captures the mouse) while the cursor never leaves the manager's visible
-- area -- and Frame:IsMouseOver checks only its own rect (which is why
-- Blizzard code routinely tests parent and child separately). A bare manager
-- read would hide under the cursor, most visibly collapsed, where the strip
-- is the only visible sliver.
-- A nil read means the engine refused to answer: propagate nil (never
-- coerce here) so the caller can fail visible.
local function MoveRM_IsHovering()
	local m = manager:IsMouseOver();
	if m == nil then
		return nil;
	end
	if m then
		return true;
	end
	for _, key in ipairs({ "toggleButton", "toggleButtonBack", "toggleButtonForward" }) do
		local button = manager[key];
		if button then
			local b = button:IsMouseOver();
			if b == nil then
				return nil;
			end
			if b then
				return true;
			end
		end
	end
	return false;
end

-- autohide: the manager is only faded out while it sits collapsed and the
-- cursor is elsewhere (an alpha-0 frame still receives mouse events, so
-- hovering it brings it back). SetAlpha is the designated secret-display sink
-- (AllowedWhenTainted) and always lands, marked or not; only the hover reads
-- are mark-checked. The OnEnter events themselves are a hover signal, so
-- reveal needs no read at all.
local function MoveRM_ApplyFade(hovered)
	if not db then
		return;
	end
	if managerFadesAsWhole == nil then
		-- plain Lua field read, safe anytime (no gate): the modern/classic
		-- split is fixed for the session, so the fade can route without
		-- waiting for the stock capture
		managerFadesAsWhole = manager.toggleButton == nil;
	end
	if not managerFadesAsWhole and not MoveRM_captured then
		return; -- regions unknown until capture runs
	end
	if hovered then
		MoveRM_SetAlpha(1);
		return;
	end
	local over = MoveRM_IsHovering();
	if over == nil then
		over = true; -- unknown hover fails visible: a shown manager is usable
	end
	local hidden = db.fade and manager.collapsed and not over;
	MoveRM_SetAlpha(hidden and 0 or 1);
end

-- Re-apply the saved Y over the manager's current anchor. Blizzard only
-- re-anchors the manager on expand/collapse (traced across the whole 12.1
-- tree), and the toggle post-hooks below call this right after, so the
-- offset survives with no override of Blizzard's methods.
local function MoveRM_ApplyPosition()
	if not db then
		return;
	end
	local count = manager:GetNumPoints() or 0;
	local point, relativeTo, relativePoint, x, y = manager:GetPoint(count > 0 and count or 1);
	if not point then
		return;
	end
	if y == db.y then
		-- already exactly there: leave Blizzard's anchor completely alone
		return;
	end
	manager:ClearAllPoints();
	manager:SetPoint(point, relativeTo, relativePoint, x, db.y);
end

local function MoveRM_ApplyStrata()
	if not db then
		return;
	end
	local want = (db.strata and STRATAS[db.strata]) or stockStrata;
	if want == nil or containerStrata == nil then
		return; -- stock unknown: nothing sane to write yet
	end
	manager:SetFrameStrata(want);
	-- re-assert the raid frames' own strata: as the manager's child (classic)
	-- it would otherwise inherit the manager's change
	container:SetFrameStrata(containerStrata);
end

local function MoveRM_SetStrata(strata)
	if not db then
		return;
	end
	db.strata = strata;
	MoveRM_ApplyStrata();
end

-- restore every setting to the game's own behavior (db work is pure Lua and
-- always lands). Every
-- saved value goes back, including the config window's own position -- as if
-- the addon was never enabled.
local function MoveRM_Reset()
	if not db then
		return;
	end
	db.y, db.fade = MoveRM_Round2(stockY), false;
	db.win = { x = 0, y = 0 };
	if MoveRM_captured then
		MoveRM_SetStrata(stockStrataIndex);
	else
		-- stock index unknown yet: clear for the capture-time backfill
		db.strata = nil;
	end
	MoveRM_ApplyPosition(); -- restores the game's own placement
	MoveRM_ApplyFade();
	-- note: reset touches values only -- the window stays open and move mode
	-- stays on (the box follows the reset spot through refreshWindow below)
	if options then
		options:ClearAllPoints();
		options:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	end
	if refreshWindow then
		refreshWindow(); -- the window (and the move box) follows the reset
	end
	if options and options.yBox then
		-- force the Y box: it may hold keyboard focus or a format-equal
		-- string ("-140.0") that the conditional refresh skips, leaving
		-- stale visible text on the real client
		options.yBox:ClearFocus();
		options.yBox:SetText(tostring(db.y));
	end
end

local function MoveRM_Sanitize(dbt)
	-- v1 carryover: the old CLI-only addon saved exactly { y, fade, strata }
	-- under this same name, with strata defaulting to 2 (LOW, force-applied
	-- every login). All three keep working verbatim -- including a legacy 2,
	-- which stays an explicit LOW rather than becoming the game default --
	-- while the new win key backfills below.
	if dbt.y == nil then
		dbt.y = stockY;
	end
	dbt.y = tonumber(dbt.y) or stockY;
	if dbt.y < -MAX_COORD or dbt.y > MAX_COORD then
		dbt.y = stockY;
	end
	dbt.y = MoveRM_Round2(dbt.y); -- heal float32 layout drift from older saves
	dbt.fade = dbt.fade and true or false;
	if dbt.strata ~= nil then
		dbt.strata = math.floor(tonumber(dbt.strata) or 0);
		if dbt.strata < 1 or dbt.strata > MAX_STRATA then
			dbt.strata = nil;
		end
	end
	-- scrapped beta keys (side/mirror docks never shipped): drop them so
	-- tables from testing come back clean
	dbt.side = nil;
	dbt.mirror = nil;
	if type(dbt.win) ~= "table" then
		dbt.win = {};
	end
	dbt.win.x = MoveRM_Round2(tonumber(dbt.win.x) or 0);
	dbt.win.y = MoveRM_Round2(tonumber(dbt.win.y) or 0);
end

-- ----------------------------------------------------------------------------
-- move mode: drag the manager vertically, following MFC's drag proxy pattern
-- ----------------------------------------------------------------------------
-- Entering move mode shows a green 50% box exactly over the manager's rect at
-- a lower strata (BACKGROUND, so the manager overlays it) plus a transparent
-- drag input above the manager (TOOLTIP, so grabs land). The box is a
-- UIParent sibling copying the manager's anchor, so it also marks the spot
-- when the manager itself is hidden (not in group) -- where the manager would
-- fit if it was there. The math is cursor-driven, never read back from the
-- box: the box follows the manager, so reading it would feed our own movement
-- back into the next update and run away (see MFC). The OnUpdate script only
-- exists while a drag is active and is removed on release, so there is no
-- per-frame cost outside of it. Vertical only: the manager's X always belongs
-- to its collapsed/expanded stock anchor.

-- Best-effort OnUpdate detach on our own input frame: always safe.
MoveRM_DetachDrag = function()
	if MoveRM_moveInput then
		MoveRM_moveInput:SetScript("OnUpdate", nil);
	end
end;

local function MoveRM_BuildMoveUI()
	if MoveRM_moveBox then
		return;
	end
	MoveRM_moveBox = CreateFrame("Frame", "Move_CompactRaidFrameManagerMoveBox", UIParent);
	MoveRM_moveBox:SetFrameStrata("BACKGROUND");
	MoveRM_moveBox:SetFrameLevel(1);
	MoveRM_moveBox:EnableMouse(false);
	local tex = MoveRM_moveBox:CreateTexture(nil, "BACKGROUND");
	tex:SetColorTexture(0, 1, 0, 0.5);
	tex:SetAllPoints();
	MoveRM_moveBox:Hide();
	MoveRM_moveInput = CreateFrame("Frame", "Move_CompactRaidFrameManagerMoveInput", UIParent);
	MoveRM_moveInput:SetFrameStrata("TOOLTIP");
	MoveRM_moveInput:SetFrameLevel(100);
	MoveRM_moveInput:EnableMouse(true);
	MoveRM_moveInput:RegisterForDrag("LeftButton");
	-- No StartMoving/StopMovingOrSizing anywhere: the built-in mover would
	-- fight the manager's own anchors (each apply pulls the box, each box
	-- read would feed back into the manager). Instead the box is ONLY ever
	-- manager-driven and the manager is ONLY ever cursor-driven, so there is
	-- a single control loop with nothing to fight.
	MoveRM_moveInput:SetScript("OnDragStart", function(self)
		MoveRM_BeginDrag(self);
	end);
	MoveRM_moveInput:SetScript("OnDragStop", function(self)
		MoveRM_EndDrag(self);
	end);
	MoveRM_moveInput:Hide();
end

-- Shared drag endpoints: the move input AND the toggle-strip buttons both
-- drive them, so the strip is dual-purpose -- a plain press runs Blizzard's
-- own click natively (expand/collapse, always), while a press-and-move
-- becomes a manager drag. The OnUpdate always lives on the move input (shown
-- throughout move mode); the buttons only initiate.
MoveRM_BeginDrag = function(self)
	if not db or not MoveRM_moveModeOn then
		return; -- outside move mode the strip is click-only, as stock
	end
	-- capture where the cursor grabbed relative to the manager's anchor:
	-- db.y already IS the anchor's Y in UI units, so the grab is exact
	-- and the manager cannot jump by a single pixel, whatever the scale
	local _, ph = UIParent:GetSize();
	local _, cy = GetCursorPosition(); -- already in UI units on this client
	if cy == nil then
		return; -- cursor unreadable: refuse the grab without touching anything
	end
	MoveRM_grabDY = cy - (ph + db.y);
	MoveRM_moveDragging = true;
	if MoveRM_moveInput then
		MoveRM_moveInput:SetScript("OnUpdate", function() MoveRM_DragUpdate(); end);
	end
end

MoveRM_EndDrag = function(self)
	if MoveRM_moveDragging then
		MoveRM_DragUpdate(); -- exact final position (drag still active)
	end
	MoveRM_moveDragging = false;
	MoveRM_DetachDrag();
end

-- Re-anchor the box and the input over the manager's current rect. Only the
-- manager reads are mark-checked (everything written here is our own frames);
-- returns whether the box now mirrors the manager (move-mode entry refuses
-- otherwise -- showing a wrong box is worse than showing none).
MoveRM_SyncMoveBox = function()
	if not MoveRM_moveBox or not db then
		return false;
	end
	local count = manager:GetNumPoints() or 0;
	local point, relativeTo, relativePoint, x = manager:GetPoint(count > 0 and count or 1);
	if not point then
		return false;
	end
	local w, h = manager:GetSize();
	if w == nil or h == nil then
		return false;
	end
	MoveRM_moveBox:ClearAllPoints();
	MoveRM_moveBox:SetPoint(point, relativeTo, relativePoint, x, db.y);
	MoveRM_moveBox:SetSize(w, h);
	-- the drag input covers the manager EXCEPT the toggle-strip column, so
	-- expand/collapse stays clickable while move mode is on: the strip sits
	-- on the manager's right edge, so the input's right edge anchors to the
	-- toggle button's left edge (full height), leaving the rest draggable.
	-- Panel inner controls (expanded options rows) stay covered while moving
	-- -- move mode is a transient gesture, and the window close exits it.
	MoveRM_moveInput:ClearAllPoints();
	local strip = manager.toggleButton or manager.toggleButtonBack or manager.toggleButtonForward;
	if strip then
		MoveRM_moveInput:SetPoint("TOPLEFT", manager, "TOPLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("BOTTOMLEFT", manager, "BOTTOMLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("TOPRIGHT", strip, "TOPLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("BOTTOMRIGHT", strip, "BOTTOMLEFT", 0, 0);
	else
		MoveRM_moveInput:SetPoint(point, relativeTo, relativePoint, x, db.y);
		MoveRM_moveInput:SetSize(w, h);
	end
	return true;
end;

MoveRM_DragUpdate = function()
	if not MoveRM_moveDragging then
		return; -- idle frame: cheapest possible return, no queries at all
	end
	if not db then
		MoveRM_moveDragging = false;
		return;
	end
	local _, ph = UIParent:GetSize();
	local _, cy = GetCursorPosition(); -- already in UI units on this client
	if cy == nil then
		-- cursor unreadable mid-drag: end the gesture without persisting
		-- anything further (db keeps the last good spot)
		MoveRM_moveDragging = false;
		MoveRM_DetachDrag();
		return;
	end
	db.y = MoveRM_Round2(cy - MoveRM_grabDY - ph);
		MoveRM_ApplyPosition(); -- re-asserts over the stock re-anchor
	MoveRM_SyncMoveBox();
	if refreshWindow then
		refreshWindow(); -- the Y box updates live while dragging
	end
end

MoveRM_SetMoveMode = function(on)
	if on then
		MoveRM_BuildMoveUI();
		if not MoveRM_moveBox then
			return;
		end
		if not MoveRM_SyncMoveBox() then
			return; -- manager unreadable (marked): no box is better than a wrong one
		end
		MoveRM_moveBox:Show();
		MoveRM_moveInput:Show();
		MoveRM_moveModeOn = true;
	else
		-- exiting is always safe
		MoveRM_moveModeOn = false;
		MoveRM_moveDragging = false;
		MoveRM_DetachDrag();
		if MoveRM_moveBox then
			MoveRM_moveBox:Hide();
		end
		if MoveRM_moveInput then
			MoveRM_moveInput:Hide();
		end
	end
	if options and options.moveBtn then
		options.moveBtn:SetText(MoveRM_moveModeOn and "stop moving" or "move manager");
	end
end

-- ----------------------------------------------------------------------------
-- config window, built on init inside a pcall: even if a widget template
-- is missing in some client flavor, the manager keeps working
-- ----------------------------------------------------------------------------
local function MoveRM_MakeLabel(parent, text, fontObject, point, relativeTo, relPoint, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY");
	fs:SetFontObject(fontObject);
	fs:SetText(text);
	fs:SetPoint(point, relativeTo, relPoint, x, y);
	return fs;
end

local function MoveRM_MakeEditBox(parent, width, maxLetters, point, relativeTo, relPoint, x, y, onEnter)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate");
	box:SetSize(width, 28);
	box:SetPoint(point, relativeTo, relPoint, x, y);
	-- the compact font is load-bearing for the coordinate box: the Large font
	-- makes "-100.00" wider than the box's visible text area and the EditBox's
	-- scroll/caret handling then clips and misplaces the digits
	box:SetFontObject("GameFontHighlight");
	if box.SetTextInsets then
		-- the search-border left cap protrudes 5px outside the frame
		box:SetTextInsets(12, 8, 6, 6); -- equal vertical insets center the text
	end
	box:SetAutoFocus(false);
	box:SetMaxLetters(maxLetters);
	box:SetJustifyH("CENTER");
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus(); -- own frame: always servable
	end);
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus();
		if db then
			onEnter(self:GetText()); -- GetText reads are safe
		end
	end);
	return box;
end

local function MoveRM_BuildWindow()
	options = CreateFrame("Frame", "Move_CompactRaidFrameManagerOptions", UIParent, "BackdropTemplate");
	options:SetFrameStrata("HIGH");
	options:SetSize(272, 158);
	options:SetMovable(true);
	options:EnableMouse(true);
	options:RegisterForDrag("LeftButton");
	options:SetClampedToScreen(true);
	options:SetScript("OnDragStart", function(self)
		self:StartMoving(); -- own frame: always servable
	end);
	options:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing();
		if db then
			local pw, ph = UIParent:GetSize();
			local cx, cy = self:GetCenter();
			db.win = { x = MoveRM_Round2(cx - pw / 2), y = MoveRM_Round2(cy - ph / 2) };
			self:ClearAllPoints();
			self:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y);
		end
	end);
	options:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	});
	options:SetBackdropColor(0, 0, 0, 0.85);
	options:Hide();

	-- clicking anywhere outside an edit box (on the window or on the world)
	-- gives keyboard focus back so the game chat works again
	options:SetScript("OnMouseDown", function()
		if options.yBox then
			options.yBox:ClearFocus();
		end
	end);
	if WorldFrame then
		WorldFrame:HookScript("OnMouseUp", function()
			if options and options:IsShown() and options.yBox then
				options.yBox:ClearFocus();
			end
		end);
	end

	-- close
	local close = CreateFrame("Button", nil, options, "UIPanelCloseButton");
	close:SetPoint("TOPRIGHT", options, "TOPRIGHT", -4, -4);
	close:SetScript("OnClick", function()
		options:Hide();
	end);

	-- move mode: only while it is on is the manager drag-movable up and down;
	-- it sits centered at the top of the window
	options.moveBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate");
	options.moveBtn:SetSize(140, 22); -- wide enough for the Large-font label
	if options.moveBtn.SetNormalFontObject then
		options.moveBtn:SetNormalFontObject("GameFontNormalLarge");
		options.moveBtn:SetHighlightFontObject("GameFontHighlightLarge");
		options.moveBtn:SetDisabledFontObject("GameFontNormalLarge");
	end
	options.moveBtn:SetText("move manager");
	options.moveBtn:SetPoint("TOP", options, "TOP", 0, -6);
	options.moveBtn:SetScript("OnClick", function()
		if MoveRM_moveModeOn then
			MoveRM_SetMoveMode(false);
		else
			MoveRM_SetMoveMode(true); -- refuses itself when unmeasurable
		end
	end);

	-- position: one Y coordinate with a box for exact values (quick drags
	-- happen in move mode); the label is edge-anchored to the box so the row
	-- is vertically centered by point semantics
	options.yBox = MoveRM_MakeEditBox(options, 80, 9, "TOPLEFT", options, "TOPLEFT", 52, -44, function(v)
		v = tonumber(v);
		if v and v >= -MAX_COORD and v <= MAX_COORD then
			db.y = MoveRM_Round2(v);
			MoveRM_ApplyPosition(); -- db already correct, frame follows
			if refreshWindow then
				refreshWindow();
			end
		end
	end);
	MoveRM_MakeLabel(options, "Y", "GameFontNormalLarge", "RIGHT", options.yBox, "LEFT", -12, 0);

	-- autohide while collapsed
	options.hideBox = CreateFrame("CheckButton", "Move_CompactRaidFrameManagerHide", options, "UICheckButtonTemplate");
	options.hideBox:SetSize(22, 22);
	options.hideBox:SetPoint("TOPLEFT", options, "TOPLEFT", 52, -82);
	MoveRM_MakeLabel(options, "hide when collapsed", "GameFontNormalLarge", "LEFT", options.hideBox, "RIGHT", 8, 0);
	options.hideBox:SetScript("OnClick", function(self)
		if not db then
			return;
		end
		db.fade = self:GetChecked() and true or false;
		MoveRM_ApplyFade(); -- db already correct, frame follows
	end);

	function refreshWindow()
		if not db or not options.yBox then
			return;
		end
		-- own frames throughout: every write below serves, marked or not.
		if tonumber(options.yBox:GetText()) ~= db.y then
			options.yBox:SetText(tostring(db.y));
		end
		options.hideBox:SetChecked(db.fade);
		if options.strataBtn and db.strata then
			options.strataBtn:SetText(STRATAS[db.strata]);
		end
		if options.moveBtn then
			options.moveBtn:SetText(MoveRM_moveModeOn and "stop moving" or "move manager");
		end
		if MoveRM_moveModeOn then
			MoveRM_SyncMoveBox(); -- self-guarded: no-op when unmeasurable
		end
	end

	options:SetScript("OnShow", function()
		if refreshWindow then
			refreshWindow();
		end
	end);
	options:SetScript("OnHide", function()
		if MoveRM_moveModeOn then
			MoveRM_SetMoveMode(false); -- leaving the window also leaves move mode
		end
	end);
end

-- the strata picker needs the menu system; load it lazily (it ships
-- on every target flavor) so the dropdown builds where it exists, and fall
-- back to a cycling button where it does not
local function MoveRM_EnsureMenuUtil()
	if not MenuUtil and LoadAddOn then
		pcall(LoadAddOn, "Blizzard_Menu");
	end
end

local function MoveRM_StyleDropdown(button, label, rowTop)
	button:SetSize(160, 24);
	button:SetPoint("TOPLEFT", options, "TOPLEFT", 96, rowTop);
	if button.Text then
		-- the classic template right-aligns the text at a small size
		button.Text:SetFontObject("GameFontHighlightLarge");
		button.Text:SetJustifyH("LEFT");
	end
	MoveRM_MakeLabel(options, label, "GameFontNormalLarge", "RIGHT", button, "LEFT", -12, 0);
end

local function MoveRM_BuildStrataPicker()
	options.strataBtn = CreateFrame("DropdownButton", nil, options, "WowStyle1DropdownTemplate");
	MoveRM_StyleDropdown(options.strataBtn, "Strata", -116);
	options.strataBtn:SetupMenu(function(_, rootDescription)
		if not db then
			return;
		end
		-- the live game default is preselected (backfilled at capture), so
		-- the list holds real values only -- no placeholder entry
		for i, name in ipairs(STRATAS) do
			rootDescription:CreateRadio(name,
				function(data)
					return db.strata == data;
				end,
				function(data)
					MoveRM_SetStrata(data); -- db already correct, frame follows
					if refreshWindow then
						refreshWindow();
					end
				end, i);
		end
	end);
end

local function MoveRM_BuildStrataFallback()
	options.strataBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate");
	MoveRM_StyleDropdown(options.strataBtn, "Strata", -116);
	options.strataBtn:SetScript("OnClick", function()
		if not db then
			return;
		end
		-- cycle the real values only, wrapping around (never a placeholder)
		MoveRM_SetStrata((db.strata or 0) % MAX_STRATA + 1); -- db already correct
		if refreshWindow then
			refreshWindow();
		end
	end);
end

-- ----------------------------------------------------------------------------
-- Load (pure Lua, always) + init (attempt everything at file scope, on load,
-- and on slash)
-- ----------------------------------------------------------------------------

-- Backfill the db from SavedVariables. Pure Lua table work only. Returns
-- false on a missing manager (inert before touching SavedVariables).
-- Idempotent. The first-run tutorial prints best-effort, chat lockdown or
-- not -- it is never load-bearing.
local function MoveRM_LoadState()
	if MoveRM_stateLoaded then
		return true;
	end
	if not (manager and container) then
		return false;
	end

	local freshDB = _G[ADDON_NAME] == nil;
	db = _G[ADDON_NAME];
	if not db then
		db = {}; -- start from the game's own placement
		_G[ADDON_NAME] = db; -- first session: publish it so it gets saved
	end
	MoveRM_Sanitize(db);
	if freshDB then
		MoveRM_instructions();
	end
	MoveRM_stateLoaded = true;
	return true;
end


-- Install the fade/toggle post-hooks. Attempted unconditionally; the hooks
-- run after Blizzard's own handlers: the stock OnClick first flips collapsed
-- and re-anchors, then ours re-applies the saved Y.
local function MoveRM_InstallHooks()
	if MoveRM_hooksInstalled then
		return;
	end
	-- the fade inputs change when the manager is shown, hovered or toggled.
	-- Enter carries its own hover signal (no read needed); the rest recompute
	-- against body-or-strip. The strip gets its own Enter/Leave pair: it is
	-- a child, so hovering it fires the manager's Leave while the cursor is
	-- still on the visible area.
	manager:HookScript("OnShow", function() MoveRM_ApplyFade(); end);
	manager:HookScript("OnEnter", function() MoveRM_ApplyFade(true); end);
	manager:HookScript("OnLeave", function() MoveRM_ApplyFade(); end);
	-- the manager body itself initiates drags too: the move input above it
	-- leaves the toggle-strip column out, so when collapsed (only the strip
	-- shows) the visible sliver would otherwise not drag. A plain press still
	-- does nothing here (the body has no click action), and children keep
	-- precedence -- buttons, dropdowns and the resize handle behave stock.
	manager:RegisterForDrag("LeftButton");
	manager:SetScript("OnDragStart", function(self)
		MoveRM_BeginDrag(self);
	end);
	manager:SetScript("OnDragStop", function(self)
		MoveRM_EndDrag(self);
	end);
	for _, key in ipairs({ "toggleButton", "toggleButtonBack", "toggleButtonForward" }) do
		local button = manager[key];
		if button then
		button:HookScript("OnClick", function()
			MoveRM_ApplyPosition();
			MoveRM_ApplyFade();
			if MoveRM_moveModeOn then
				MoveRM_SyncMoveBox(); -- the box follows expand/collapse
			end
		end);
		-- fade follows the strip too: the buttons are children, so sliding
		-- from the body onto them fires the manager's OnLeave while the
		-- cursor is still on the manager's visible area (collapsed, the
		-- strip is ALL that shows). Enter carries its own hover signal;
		-- Leave recomputes against body-or-strip.
		button:HookScript("OnEnter", function()
			MoveRM_ApplyFade(true);
		end);
		button:HookScript("OnLeave", function()
			MoveRM_ApplyFade();
		end);
			-- dual-purpose strip: a plain press runs the stock click above
			-- natively, while a press-and-move drags the manager (move mode
			-- only). RegisterForDrag never blocks clicks -- the client still
			-- fires OnClick for a press without movement.
			button:RegisterForDrag("LeftButton");
			button:SetScript("OnDragStart", function(self)
				MoveRM_BeginDrag(self);
			end);
			button:SetScript("OnDragStop", function(self)
				MoveRM_EndDrag(self);
			end);
		end
	end
	-- installs are attempted once (HookScript chains, so repeats would stack
	-- duplicate wrappers): if the engine ever refuses, it errors loudly and
	-- we hear about it.
	MoveRM_hooksInstalled = true;
end

-- Setup, run at file scope (pre-SV: registers, captures, hooks, builds)
-- and again on ADDON_LOADED and slash (cheap idempotent re-entry:
-- registration no-ops, capture/hooks run once, applies re-assert).
-- The first apply waits for state (db guard below).
MoveRM_EnsureInit = function()
	MoveRM_RegisterAddonEvents();

	if not MoveRM_captured then
		MoveRM_CaptureStock();
		if stockStrata ~= nil then
			MoveRM_captured = true;
		end
	end
	MoveRM_InstallHooks();
	if MoveRM_captured and db and db.strata == nil then
		db.strata = stockStrataIndex; -- preselect the game's own strata
	end
	if not options then
		pcall(function()
			MoveRM_EnsureMenuUtil();
			MoveRM_BuildWindow();
		end);
	end
	if options and not options.strataBtn then
		pcall(MoveRM_BuildStrataPicker);
		if not options.strataBtn then
			pcall(MoveRM_BuildStrataFallback);
		end
	end
	if MoveRM_stateLoaded then
		MoveRM_ApplyPosition(); -- positions over the login re-anchor
		MoveRM_ApplyStrata(); -- db.strata is backfilled above, always explicit
		MoveRM_ApplyFade();
		if options then
			options:ClearAllPoints();
			options:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y);
			if refreshWindow then
				refreshWindow();
			end
		end
	end
end;

-- ----------------------------------------------------------------------------
-- login and persist through sessions functionality
-- ----------------------------------------------------------------------------
local function MoveRM_OnEvent(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			if MoveRM_LoadState() then
				MoveRM_EnsureInit();
			end
			-- unregister LAST: EnsureInit re-registers everything above,
			-- so unsubscribing first would resurrect in the same tick.
			-- The handler is idempotent anyway, so a lingering
			-- registration would be harmless regardless.
			self:UnregisterEvent("ADDON_LOADED");
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED"
		or event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE"
		or event == "PARTY_LEADER_CHANGED" then
		-- Blizzard rebuilds the panel on crossings and roster changes
		-- (options flow, heights): keep the move box on the manager's rect.
		-- Box sync is a no-op unless move mode is on; unmeasurable rects
		-- simply skip.
		if MoveRM_moveModeOn then
			MoveRM_SyncMoveBox();
		end
	end
end

-- All event installs funnel through here. Re-registering is a no-op and the
-- script is simply replaced, so repeated EnsureInit calls stay cheap.
local function MoveRM_RegisterAddonEventsInner()
	if not MoveRM_EventFrame then return end
	MoveRM_EventFrame:RegisterEvent("ADDON_LOADED");
	MoveRM_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	MoveRM_EventFrame:RegisterEvent("ZONE_CHANGED");
	MoveRM_EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
	-- panel rebuilds can move/resize the manager under an open move box
	MoveRM_EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
	MoveRM_EventFrame:RegisterEvent("PARTY_LEADER_CHANGED");
	MoveRM_EventFrame:SetScript("OnEvent", MoveRM_OnEvent);
end
MoveRM_RegisterAddonEvents = MoveRM_RegisterAddonEventsInner;

MoveRM_EventFrame = CreateFrame("Frame", "Move_CompactRaidFrameManagerEventFrame");

-- File scope runs before SavedVariables land: register (so our own
-- ADDON_LOADED is heard), capture stock, install hooks, build the window.
-- The first apply waits for state in the ADDON_LOADED handler below.
MoveRM_EnsureInit();

-- ----------------------------------------------------------------------------
-- slash command functionality: bare /moverm (or anything unrecognized)
-- toggles the config window, /moverm reset restores the game's defaults
-- ----------------------------------------------------------------------------
SLASH_MOVERM1 = "/moverm";
SlashCmdList.MOVERM = function(msg)
	if not MoveRM_stateLoaded then
		if not MoveRM_LoadState() then
			return; -- unknown layout: inert, SavedVariables untouched
		end
	end
	-- re-entry is cheap and idempotent: a missed ADDON_LOADED (refused
	-- registration) resumes here.
	MoveRM_EnsureInit();
	if not db then
		return; -- settings are not loaded yet
	end
	msg = string.lower(string.match(msg or "", "^%s*(.-)%s*$") or "");
	if msg == "reset" then
		MoveRM_Reset();
	elseif options and options:IsShown() then
		options:Hide();
	elseif options then
		options:Show();
	end
end
