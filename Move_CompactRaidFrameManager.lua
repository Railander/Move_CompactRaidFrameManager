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
-- own methods and no polling. The position applier returns without writing
-- when the anchor already matches, so default settings leave the game's
-- placement pixel-identical (strata and fade only ever rewrite the same live
-- values back). Everything is event driven: no polling
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
-- no read-back verification, no queues. Widget builds run inside pcall
-- containment (a missing template must not break the manager), which is
-- crash-safety, not gating. If the engine ever refuses,
-- it errors LOUDLY (Bugsack, not silence), which is exactly what we want: a
-- silent queue would hide the bug forever, an error gets reported and fixed.
-- The only guards left are crash-safety (nil results abort geometry) and
-- correctness (the position early-out keeps the default Y from touching
-- Blizzard's anchors at all). Classic flavors run the same code.
-- Safe everywhere: SetAlpha, FontString:SetText, Show/Hide, db work. Chat
-- tutorial prints best-effort always (a swallowed line under Chat lockdown is
-- harmless -- it is never load-bearing).

local ADDON_NAME = "Move_CompactRaidFrameManager";

-- Blizzard's CompactRaidFrames addon loads before user addons, so the frames
-- normally exist at file scope; on an unknown layout stay inert until
-- /reload (the guard below exits before the slash handler registers, so no
-- retry is possible that session)
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
-- the strata picker shows digits, not names: FULLSCREEN_DIALOG still clipped
-- against the arrow column at 208, and a digit needs no width. Display-only:
-- db.strata keeps the 1-8 STRATAS index, shown as 2-9.
local function MoveRM_StrataLabel(i)
	return tostring(i + 1);
end
local MoveRM_STRATA_LABELS = {};
for i in ipairs(STRATAS) do
	MoveRM_STRATA_LABELS[#MoveRM_STRATA_LABELS + 1] = MoveRM_StrataLabel(i);
end
-- hide modes: 1 keeps the manager fully visible, 2 fades it out while it
-- sits collapsed and the cursor is elsewhere (hovering brings it back),
-- 3 hides it at all times, even on hover
local HIDES = { "never", "when cursor away", "always" };
local MAX_HIDE = #HIDES;
local MAX_COORD = 100000;

-- config window geometry: the initial control column (the layout pass below
-- refines it); the label gap; the Y-box nudge (the InputBoxTemplate's
-- search-border cap visibly protrudes ~5px past the frame edge, so a shared
-- anchor would paint the Y box left of the dropdowns)
local MoveRM_CONTROL_X = 88;
local MoveRM_LABEL_GAP = 12;
local MoveRM_YBOX_NUDGE = 5;
-- template chrome: the dropdown's text region ends at the arrow, so measured
-- text needs the arrow column + insets on top (calibrated once from live
-- observation; it only changes if Blizzard redesigns the template)
local MoveRM_DROPDOWN_PAD = 40;

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
local MoveRM_moveGhost; -- yellow 50% box below the green one: the tall
-- (leader/assist) version's extra height, from fixed per-family preview
-- heights (see below), with its own drag input
local MoveRM_moveGhostInput; -- transparent drag input above the ghost
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

-- Single anchor reader: capture, apply and sync must all look at the same
-- anchor (the last one), or a multi-anchor manager would compare one Y and
-- write another, re-anchoring every toggle.
local function MoveRM_ManagerAnchor()
	local count = manager:GetNumPoints() or 0;
	return manager:GetPoint(count > 0 and count or 1);
end

-- Capture the stock layout: the game's own placement and strata, the client
-- family, and the fade list. Runs once (stock must predate our own moves --
-- recapturing later would adopt our offset as the game's). The flag is managed
-- by EnsureInit, which only sets it once the strata read lands (nil stock
-- would poison reset, so a nil read simply retries next init).
local function MoveRM_CaptureStock()
	stockY = MoveRM_Round2(select(5, MoveRM_ManagerAnchor()) or -140);
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

-- hide: "never" keeps the manager fully visible; "when cursor away" fades
-- it out while it sits collapsed and the cursor is elsewhere (an alpha-0
-- frame still receives mouse events, so hovering it brings it back);
-- "always" hides it at all times, even on hover. SetAlpha is the
-- designated secret-display sink (AllowedWhenTainted) and always lands;
-- hover reads may return nil (the caller fails visible instead). The OnEnter
-- events themselves are
-- a hover signal, so reveal needs no read at all.
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
	if db.hide == 3 then
		MoveRM_SetAlpha(0); -- hidden at all times, even on hover
		return;
	end
	if db.hide ~= 2 then
		MoveRM_SetAlpha(1); -- "never" (and any unbackfilled state)
		return;
	end
	if hovered then
		MoveRM_SetAlpha(1);
		return;
	end
	local over = MoveRM_IsHovering();
	if over == nil then
		over = true; -- unknown hover fails visible: a shown manager is usable
	end
	local hidden = manager.collapsed and not over;
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
	local point, relativeTo, relativePoint, x, y = MoveRM_ManagerAnchor();
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

local function MoveRM_SetHide(hide)
	if not db then
		return;
	end
	db.hide = hide;
	MoveRM_ApplyFade();
end

-- restore every setting to the game's own behavior (db work is pure Lua and
-- always lands). Every
-- saved value goes back, including the config window's own position -- as if
-- the addon was never enabled.
local function MoveRM_Reset()
	if not db then
		return;
	end
	db.y, db.hide = MoveRM_Round2(stockY), 1;
	db.tallExtra = nil; -- scrapped learn-era key: the ghost is deterministic now (see the preview heights)
	db.fade = nil; -- checkbox-era key, dropped by the hide migration
	db.side, db.mirror = nil, nil; -- scrapped beta keys, never shipped (see Sanitize)
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
	-- hide carryover: the checkbox era saved fade as true/false (v1 included).
	-- A faded table becomes "when cursor away", an unfaded one "never"; the
	-- old key is dropped once migrated.
	if dbt.hide == nil and dbt.fade ~= nil then
		dbt.hide = (dbt.fade and true or false) and 2 or 1;
	end
	dbt.fade = nil;
	if dbt.hide ~= nil then
		dbt.hide = math.floor(tonumber(dbt.hide) or 0);
		if dbt.hide < 1 or dbt.hide > MAX_HIDE then
			dbt.hide = nil;
		end
	end
	if dbt.hide == nil then
		dbt.hide = 1;
	end
	if dbt.strata ~= nil then
		dbt.strata = math.floor(tonumber(dbt.strata) or 0);
		if dbt.strata < 1 or dbt.strata > MAX_STRATA then
			dbt.strata = nil;
		end
	end
	-- scrapped learn-era key (tallExtra heights from testing): drop it so
	-- old tables come back clean -- the ghost is deterministic now
	dbt.tallExtra = nil;
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
	-- the tall-version ghost (see SyncMoveBox): yellow, mouse-transparent
	-- like the green box, with its own drag input above it
	MoveRM_moveGhost = CreateFrame("Frame", "Move_CompactRaidFrameManagerMoveGhost", UIParent);
	MoveRM_moveGhost:SetFrameStrata("BACKGROUND");
	MoveRM_moveGhost:SetFrameLevel(1);
	MoveRM_moveGhost:EnableMouse(false);
	local ghostTex = MoveRM_moveGhost:CreateTexture(nil, "BACKGROUND");
	ghostTex:SetColorTexture(1, 1, 0, 0.5);
	ghostTex:SetAllPoints();
	MoveRM_moveGhost:Hide();
	MoveRM_moveGhostInput = CreateFrame("Frame", "Move_CompactRaidFrameManagerMoveGhostInput", UIParent);
	MoveRM_moveGhostInput:SetFrameStrata("TOOLTIP");
	MoveRM_moveGhostInput:SetFrameLevel(100);
	MoveRM_moveGhostInput:EnableMouse(true);
	MoveRM_moveGhostInput:RegisterForDrag("LeftButton");
	MoveRM_moveGhostInput:SetScript("OnDragStart", function(self)
		MoveRM_BeginDrag(self);
	end);
	MoveRM_moveGhostInput:SetScript("OnDragStop", function(self)
		MoveRM_EndDrag(self);
	end);
	MoveRM_moveGhostInput:Hide();
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
	-- GetCursorPosition returns screen pixels: scale into UI units (at
	-- scale 1 this divides by 1, so the math is unchanged there)
	local scale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1;
	local _, cyRaw = GetCursorPosition();
	if cyRaw == nil then
		return; -- cursor unreadable: refuse the grab without touching anything
	end
	local cy = cyRaw / scale;
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

-- Tall-version preview heights, one per client family (the toggle buttons
-- tell them apart at runtime: a lone toggleButton is classic, the
-- Tall-version preview heights, one per client family (the toggle buttons
-- tell them apart at runtime: a lone toggleButton is classic, the
-- back/forward pair is modern). Blizzard resizes the manager itself to fit
-- the options flow, so the party-leader frame height is derivable from the
-- dumped UI code with zero live state -- no learning, no persistence, the
-- ghost shows on a fresh install, solo, first session. Target is the PARTY
-- leader (the 5-man panel), not the raid leader: the constants must match
-- the layout the owner actually parks against -- a raid-lead MAX (prior
-- 480) previews 2-3x the party overflow solo and leaves ~110px of yellow
-- below an expanded party-lead box. Derivation (12.1.0 dump, flow function
-- byte-identical on GitHub master and in 1.60.1/1.15.9/2.5.6/5.5.4; no
-- custom flow spacing anywhere, so every line break adds exactly the row
-- height; independently verified by a third-party sim executing the real
-- Blizzard code against retail: party-regular usedY=255 -> H=275 and
-- party-lead usedY=327 -> H=347 with stub-zero divider/label -- both EXACT):
-- MODERN (Mainline UpdateOptionsFlowContainer, party leader: no
-- filterOptions; five 40x40 buttons -- difficulty, editMode, readyCheck,
-- rolePoll, countdown -- stride 4 gives rows of 4+1 plus ONE horizontal
-- divider): usedY = 48 top offset + 40 + DIV + 40 + 10 + 99 raidMarkers
-- (XML 222x99) + 5 + LBL RestrictPingsLabel (158x0 FontString: one
-- GameFontNormalLeft line -- FRIZQT 12px, no spacing, taken at a tight 12)
-- + 2 + 25 RestrictPingsDropdown (WowStyle1DropdownTemplate 120x25) + 5 +
-- 53 BottomButtons (XML 160x53); height = usedY + 20 = 360, pixel by pixel:
-- 48+40+0+40+10+99+5+13+2+25+5+53+20 = 360. Every term pinned: the 327
-- subtotal (everything but DIV/LBL/padding) reproduces a third-party probe
-- EXACTLY (sim executing the real Blizzard code: party-lead usedY=327 ->
-- H=347 with its stub-zero divider/label), which simultaneously proves the
-- divider atlas resolves to ~0 despite the object sitting in-flow (its
-- terms would otherwise overshoot the probe) and bounds old-era art
-- (party-leads BG 222x344: no room for DIV>3 in either era). So DIV=0,
-- padding 20, and LBL=13: the font-metrics 12 read 1px under live (owner
-- measured, 2026-09-20), so the label carries the live-calibrated 13.
-- Rounded DOWN by policy: a 1-2px under-preview parks invisibly low,
-- yellow that remains is a visible lie -- and the owner measured ~5px over
-- at 364, matching DIV~3+LBL~14 (17) vs true ~12 word for word.
-- Cross-checks: raid-lead math from the same rows gives ~472, matching the
-- old 222x474 leads art -- the row model is sound.
-- CLASSIC (Classic/... UpdateOptionsFlowContainer, container =
-- displayFrame.optionsFlowContainer, 200 wide; party leader: no offset
-- reset outside the raid branch, so 0 fresh (post-raid without /reload the
-- stale 4 lingers -- RemoveAllObjects never clears offsets -- giving 199:
-- the clamp still shows none expanded, solo under-previews by 4, both
-- invisible in practice): usedY = 50 raidMarkers + 65
-- leaderOptions (200 wide, own lines) + 20 convertToRaid line (169x20
-- after a 20px indent) + 20 editMode/hiddenModeToggle line (85+85 side
-- by side) = 155; height = usedY + 40 = 195 exactly -- every term
-- XML-exact, no estimates. Same structure in all four classic dumps.
-- The ghost below shows tall MINUS the current box height (see SyncMoveBox),
-- so an expanded party-lead box (already tall) shows no ghost while a solo
-- box previews the exact lead reach. CAVEATS: a RAID leader/assist/member
-- layout is taller (raid-lead ~472) and clamps to no ghost -- parking a
-- raid panel needs manual margin, the preview covers party play exactly.
-- DRIFT RISK: a Blizzard row add/remove/resize or divider-art change
-- stale-dates the constants -- re-derive from UpdateOptionsFlowContainer
-- when the leader panel visibly changes.
local MoveRM_TALL_MODERN = 360;
local MoveRM_TALL_CLASSIC = 195;

-- Re-anchor the box, the ghost and the inputs over the manager's current
-- rect. Only the manager reads can fail here (everything written is our own
-- frames); returns whether the box now mirrors the manager (move-mode entry
-- refuses otherwise -- showing a wrong box is worse than showing none).
-- The drag surface is our OWN geometry throughout: the input copies the box
-- rect (plus the ghost when shown) and cuts the toggle-strip column only
-- while the strip is actually shown. Solo the manager hides with its strip
-- (UpdateShown hides the whole frame outside groups) -- a strip-anchored
-- input then derives its rect from hidden frames and drags die there, with
-- the clicks falling through to the world; a box-anchored one cannot.
MoveRM_SyncMoveBox = function()
	if not MoveRM_moveBox or not db then
		return false;
	end
	local point, relativeTo, relativePoint, x = MoveRM_ManagerAnchor();
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
	-- the ghost hangs below the box: the family's tall preview height MINUS
	-- the box's own height, if any -- a grouped leader's box already IS
	-- tall, so no ghost (box + ghost always exactly cover the tall rect);
	-- a solo box always previews the full lead reach. Rounded at the
	-- boundary: live heights are float32, and raw dust (359.99999 vs the
	-- 360 preview) must not raise a sliver of ghost. The family read is
	-- plain Lua (same split as the fade router): no capture, no state.
	local tall = (manager.toggleButton == nil) and MoveRM_TALL_MODERN or MoveRM_TALL_CLASSIC;
	local extra = MoveRM_Round2(math.max(0, tall - h));
	if MoveRM_moveGhost then
		if extra > 0 then
			MoveRM_moveGhost:ClearAllPoints();
			MoveRM_moveGhost:SetPoint("TOPLEFT", MoveRM_moveBox, "BOTTOMLEFT", 0, 0);
			MoveRM_moveGhost:SetSize(w, extra);
			MoveRM_moveGhost:Show();
		else
			MoveRM_moveGhost:Hide();
		end
	end
	if MoveRM_moveGhostInput then
		if extra > 0 then
			MoveRM_moveGhostInput:ClearAllPoints();
			MoveRM_moveGhostInput:SetPoint("TOPLEFT", MoveRM_moveGhost, "TOPLEFT", 0, 0);
			MoveRM_moveGhostInput:SetPoint("BOTTOMRIGHT", MoveRM_moveGhost, "BOTTOMRIGHT", 0, 0);
			MoveRM_moveGhostInput:Show();
		else
			MoveRM_moveGhostInput:Hide();
		end
	end
	-- the drag input covers the manager EXCEPT the toggle-strip column, so
	-- expand/collapse stays clickable while move mode is on -- but only
	-- while the manager (and hence its strip) is shown. Hidden, the strip
	-- takes no clicks, so the input takes the full box rect instead (see
	-- the function header). Panel inner controls (expanded options rows)
	-- stay covered while moving -- move mode is a transient gesture, and
	-- the window close exits it.
	MoveRM_moveInput:ClearAllPoints();
	local strip = manager.toggleButton or manager.toggleButtonBack or manager.toggleButtonForward;
	-- the manager-shown check is the whole gate: Blizzard always shows
	-- exactly one strip with the manager (Collapse/Expand swap them), so a
	-- separate strip check buys nothing and the mock never Shows its strips
	if strip and manager:IsShown() then
		MoveRM_moveInput:SetPoint("TOPLEFT", manager, "TOPLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("BOTTOMLEFT", manager, "BOTTOMLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("TOPRIGHT", strip, "TOPLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("BOTTOMRIGHT", strip, "BOTTOMLEFT", 0, 0);
	else
		-- solo (or stripped of toggles): no clickable strip to protect,
		-- so the input is simply the box rect, anchored to our own box
		MoveRM_moveInput:SetPoint("TOPLEFT", MoveRM_moveBox, "TOPLEFT", 0, 0);
		MoveRM_moveInput:SetPoint("BOTTOMRIGHT", MoveRM_moveBox, "BOTTOMRIGHT", 0, 0);
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
	-- screen pixels into UI units (see BeginDrag); scale 1 divides by 1
	local scale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1;
	local _, cyRaw = GetCursorPosition();
	if cyRaw == nil then
		-- cursor unreadable mid-drag: end the gesture without persisting
		-- anything further (db keeps the last good spot)
		MoveRM_moveDragging = false;
		MoveRM_DetachDrag();
		return;
	end
	local cy = cyRaw / scale;
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
			-- manager unreadable: no box is better than a wrong one; say so
			-- best-effort (a swallowed line under Chat lockdown is harmless)
			print(colorOrange .. "Move Raid Manager: cannot enter move mode -- the manager is unreadable." .. exitColor);
			return;
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
		if MoveRM_moveGhost then
			MoveRM_moveGhost:Hide();
		end
		if MoveRM_moveGhostInput then
			MoveRM_moveGhostInput:Hide();
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

-- Info icons: the spellbook's hi-res "i" (Interface\Common\Help-I), stretched
-- full-canvas to 16px -- the GuildRewards-tutorial-button pattern. Proven
-- across every dumped flavor (referenced in the 1.15.9/2.5.6/5.5.4 Classic
-- and 12.1.0/1.60.1 Mainline UI dumps); residual: 3.4.3/4.4.0 undumped.
-- Three shapes failed live first and stay documented in-code so nobody
-- retries them: UIPanelInfoButton shows its texture UNSIZED (native pixels
-- overflowing its 16px button = blurry crop); FriendsFrame's InformationIcon
-- full-stretched is equally soft (vanilla-era source art, crisp only at
-- MoneyFrame's 13px -- while Help-I is modern art authored for 46px, so it
-- downscales sharp); the spellbook's TrackingBorder ring art sits off-center
-- in its own canvas (HelpPlate compensates +12/-13 at 64px -- unknowable
-- blind at 16px, read as a small top-left circle).
-- Deliberately a mouse-enabled Frame, not a Button: buttons press/highlight
-- on hover while this one does nothing on click. One icon sits between each
-- label and its control (labels are FontStrings, which never receive mouse
-- events, so the tip cannot live on the label itself). Rows stay tidy
-- because icons share one size and one right edge: the Y icon absorbs the
-- box nudge in its own offset, so every label keeps the uniform gap.
local MoveRM_ICON_SIZE = 16;
local MoveRM_ICON_GAP = 6;
local function MoveRM_BuildInfoIcons()
	if not (options and options.yBox and options.yLabel
		and options.hideBtn and options.hideBtn.MoveRM_label
		and options.strataBtn and options.strataBtn.MoveRM_label) then
		return;
	end
	if options.yLabel.MoveRM_icon then
		return; -- built once
	end
	local rows = {
		{ control = options.yBox, label = options.yLabel,
			dx = -(MoveRM_ICON_GAP + MoveRM_YBOX_NUDGE),
			tip = "Choose the Y coordinate of the manager window.\nType an exact Y coordinate, or drag it in move mode." },
		{ control = options.hideBtn, label = options.hideBtn.MoveRM_label,
			dx = -MoveRM_ICON_GAP,
			tip = "'never' always shows it.\n'when cursor away' fades it while collapsed and the cursor is away.\n'always' disables it entirely." },
		{ control = options.strataBtn, label = options.strataBtn.MoveRM_label,
			dx = -MoveRM_ICON_GAP,
			tip = "Selects the overlay preference (strata) of the raid manager window.\n2 = lowest\n9 = highest" },
	};
	for _, row in ipairs(rows) do
		local icon = CreateFrame("Frame", nil, options);
		icon:SetSize(MoveRM_ICON_SIZE, MoveRM_ICON_SIZE);
		icon:SetPoint("RIGHT", row.control, "LEFT", row.dx, 0);
		icon:EnableMouse(true);
		local art = icon:CreateTexture(nil, "ARTWORK");
		art:SetAllPoints();
		art:SetTexture("Interface\\Common\\Help-I");
		row.label:ClearAllPoints();
		row.label:SetPoint("RIGHT", icon, "LEFT", -MoveRM_ICON_GAP, 0);
		icon:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(row.tip);
			GameTooltip:Show();
		end);
		icon:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
		row.label.MoveRM_icon = icon;
	end
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
	options:SetSize(308, 158);
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
	options.yBox = MoveRM_MakeEditBox(options, 80, 9, "TOPLEFT", options, "TOPLEFT", MoveRM_CONTROL_X, -44, function(v)
		v = tonumber(v);
		if v and v >= -MAX_COORD and v <= MAX_COORD then
			db.y = MoveRM_Round2(v);
			MoveRM_ApplyPosition(); -- db already correct, frame follows
		end
		if refreshWindow then
			refreshWindow(); -- rejected input reverts visibly instead of lingering
		end
	end);
	-- the Y label carries the extra nudge gap, so its right edge lands with
	-- the dropdown labels' once the box itself is nudged (see the layout)
	options.yLabel = MoveRM_MakeLabel(options, "Y", "GameFontNormalLarge", "RIGHT", options.yBox, "LEFT", -(MoveRM_LABEL_GAP + MoveRM_YBOX_NUDGE), 0);

	function refreshWindow()
		if not db or not options.yBox then
			return;
		end
		-- own frames throughout: every write below serves, marked or not.
		if tonumber(options.yBox:GetText()) ~= db.y then
			options.yBox:SetText(tostring(db.y));
		end
		if options.hideBtn and db.hide then
			options.hideBtn:SetText(HIDES[db.hide]);
		end
		if options.strataBtn and db.strata then
			options.strataBtn:SetText(MoveRM_StrataLabel(db.strata));
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

-- Size a dropdown from its entries, measured live: a scratch FontString in
-- the dropdown font carries each entry, so the width follows the client's
-- real metrics (font, scale) and any edit to the option texts -- no manual
-- resizing per change. Only the template chrome stays constant (see above).
local function MoveRM_MeasureDropdown(entries)
	local scratch = options.MoveRM_scratch;
	if not scratch then
		scratch = options:CreateFontString(nil, "OVERLAY");
		scratch:SetFontObject("GameFontHighlightLarge");
		options.MoveRM_scratch = scratch;
	end
	local widest = 0;
	for _, text in ipairs(entries) do
		scratch:SetText(text);
		local w = scratch:GetStringWidth();
		if w and w > widest then
			widest = w;
		end
	end
	return math.ceil(widest) + MoveRM_DROPDOWN_PAD;
end

local function MoveRM_StyleDropdown(button, label, rowTop, entries)
	button:SetSize(MoveRM_MeasureDropdown(entries), 24);
	button:SetPoint("TOPLEFT", options, "TOPLEFT", MoveRM_CONTROL_X, rowTop);
	if button.Text then
		-- the classic template right-aligns the text at a small size
		button.Text:SetFontObject("GameFontHighlightLarge");
		button.Text:SetJustifyH("LEFT");
	end
	button.MoveRM_label = MoveRM_MakeLabel(options, label, "GameFontNormalLarge", "RIGHT", button, "LEFT", -MoveRM_LABEL_GAP, 0);
end

local function MoveRM_BuildStrataPicker()
	-- build into a local: SetupMenu is the fallible step (missing menu
	-- system), and publishing only on success lets EnsureInit fall back to
	-- the cycling button instead of leaving a dead dropdown behind
	local btn = CreateFrame("DropdownButton", nil, options, "WowStyle1DropdownTemplate");
	MoveRM_StyleDropdown(btn, "Strata", -120, MoveRM_STRATA_LABELS);
	btn:SetupMenu(function(_, rootDescription)
		if not db then
			return;
		end
		-- the live game default is preselected (backfilled at capture), so
		-- the list holds real values only -- no placeholder entry
		for i in ipairs(STRATAS) do
			rootDescription:CreateRadio(MoveRM_StrataLabel(i),
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
	options.strataBtn = btn;
end

local function MoveRM_BuildStrataFallback()
	local btn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate");
	MoveRM_StyleDropdown(btn, "Strata", -120, MoveRM_STRATA_LABELS);
	btn:SetScript("OnClick", function()
		if not db then
			return;
		end
		-- cycle the real values only, wrapping around (never a placeholder)
		MoveRM_SetStrata((db.strata or 0) % MAX_STRATA + 1); -- db already correct
		if refreshWindow then
			refreshWindow();
		end
	end);
	options.strataBtn = btn;
end

-- the hide picker needs the menu system too, so it follows the same
-- picker/fallback split as strata: a dropdown where the menu exists, a
-- cycling button where it does not
local function MoveRM_BuildHidePicker()
	-- same local-build discipline as the strata picker: a missing SetupMenu
	-- must leave nothing behind so the fallback below still runs
	local btn = CreateFrame("DropdownButton", nil, options, "WowStyle1DropdownTemplate");
	MoveRM_StyleDropdown(btn, "Hide", -84, HIDES);
	btn:SetupMenu(function(_, rootDescription)
		if not db then
			return;
		end
		for i, name in ipairs(HIDES) do
			rootDescription:CreateRadio(name,
				function(data)
					return db.hide == data;
				end,
				function(data)
					MoveRM_SetHide(data); -- db already correct, frame follows
					if refreshWindow then
						refreshWindow();
					end
				end, i);
		end
	end);
	options.hideBtn = btn;
end

local function MoveRM_BuildHideFallback()
	local btn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate");
	MoveRM_StyleDropdown(btn, "Hide", -84, HIDES);
	btn:SetScript("OnClick", function()
		if not db then
			return;
		end
		-- cycle never -> when cursor away -> always, wrapping around
		MoveRM_SetHide((db.hide or 0) % MAX_HIDE + 1); -- db already correct
		if refreshWindow then
			refreshWindow();
		end
	end);
	options.hideBtn = btn;
end

-- Center the widest label+icon+control row in the window, then left-align
-- every other control to that row's control edge. Labels right-anchor to
-- their icon and icons to their control, so equal control edges line the
-- icons AND the labels up too (the Y label carries the extra nudge gap,
-- keeping its edge with the others). Pure client-side text measurement on
-- our own frames; runs once every control exists, so widths are final
-- whatever the picker variants built.
local function MoveRM_LayoutControls()
	if not (options and options.yBox and options.yLabel
		and options.hideBtn and options.hideBtn.MoveRM_label
		and options.strataBtn and options.strataBtn.MoveRM_label) then
		return;
	end
	local function rowWidth(lab, cw)
		return lab:GetStringWidth() + MoveRM_ICON_GAP + MoveRM_ICON_SIZE + MoveRM_ICON_GAP + cw;
	end
	local yW = rowWidth(options.yLabel, options.yBox:GetWidth());
	local hW = rowWidth(options.hideBtn.MoveRM_label, options.hideBtn:GetWidth());
	local sW = rowWidth(options.strataBtn.MoveRM_label, options.strataBtn:GetWidth());
	local widest, wideLab = yW, options.yLabel;
	if hW > widest then
		widest, wideLab = hW, options.hideBtn.MoveRM_label;
	end
	if sW > widest then
		widest, wideLab = sW, options.strataBtn.MoveRM_label;
	end
	local controlX = (options:GetWidth() - widest) / 2
		+ wideLab:GetStringWidth() + MoveRM_ICON_GAP + MoveRM_ICON_SIZE + MoveRM_ICON_GAP;
	local function shift(control, x)
		local point, relTo, relPoint, _, y = control:GetPoint(1);
		if not point then
			return;
		end
		control:ClearAllPoints();
		control:SetPoint(point, relTo, relPoint, x, y);
	end
	shift(options.yBox, controlX + MoveRM_YBOX_NUDGE);
	shift(options.hideBtn, controlX);
	shift(options.strataBtn, controlX);
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
	if type(db) ~= "table" then
		-- corrupt/hand-edited value: start clean (mirrors the win-table
		-- guard in Sanitize) so the backfill below always has a table
		db = {}; -- start from the game's own placement
		_G[ADDON_NAME] = db; -- publish it so it gets saved
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
	-- SetScript stays (not HookScript): the conservative sealed variant since
	-- the move-mode launch -- stock sets no drag scripts here, so HookScript
	-- buys nothing. (A HookScript round-trip on 2026-09-20 proved nothing
	-- either way: the reported failure tracked group state across both
	-- variants, and the mock drives both identically.)
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
		-- fires OnClick for a press without movement. SetScript (not
		-- HookScript) per the manager body above: the sealed variant.
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
		local builtOk = pcall(function()
			MoveRM_EnsureMenuUtil();
			MoveRM_BuildWindow();
		end);
		if not builtOk and options then
			-- half-built window: drop it so a later init retries from
			-- scratch instead of trusting a zombie frame
			pcall(function() options:Hide(); end);
			options = nil;
			refreshWindow = nil;
		end
	end
	if options and not options.strataBtn then
		pcall(MoveRM_BuildStrataPicker);
		if not options.strataBtn then
			pcall(MoveRM_BuildStrataFallback);
		end
	end
	if options and not options.hideBtn then
		pcall(MoveRM_BuildHidePicker);
		if not options.hideBtn then
			pcall(MoveRM_BuildHideFallback);
		end
	end
	MoveRM_BuildInfoIcons(); -- icons ride the controls, labels re-anchor to them
	MoveRM_LayoutControls(); -- center the widest row, align every box to it
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
			-- a pre-SV slash may have published a fresh table that the
			-- client's load then replaced: re-point to the live
			-- SavedVariables table when the identity differs, so settings
			-- keep persisting
			if MoveRM_stateLoaded and type(_G[ADDON_NAME]) == "table" and _G[ADDON_NAME] ~= db then
				db = _G[ADDON_NAME];
				MoveRM_Sanitize(db);
			end
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
		-- simply skip (the ghost re-derives from the fixed preview heights
		-- inside the sync, so no learning rides along here).
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
