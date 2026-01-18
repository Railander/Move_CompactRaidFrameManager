-- ingame instructions
local exitColor = "|r"
local colorOrange = "|cFFDF9F1F"
local colorRed = "|cFFFF3F1F"
local function MoveCRFM_instructions()
	print(colorOrange .. "Use /moverm followed by: the desired Y coordinate; whether to fade it out on mouseover; to change strata 1-8 (ascending priority); to print saved config." .. exitColor)
	print(colorOrange .. "Example:" .. exitColor .. " /moverm -234.5")
	print(colorOrange .. "Example:" .. exitColor .. " /moverm yes")
	print(colorOrange .. "Example:" .. exitColor .. " /moverm strata 6")
	print(colorOrange .. "Example:" .. exitColor .. " /moverm print")
end

-- strata array
local MoveCRFM_stratas = {
	[1] = "BACKGROUND",
	[2] = "LOW",
	[3] = "MEDIUM",
	[4] = "HIGH",
	[5] = "DIALOG",
	[6] = "FULLSCREEN",
	[7] = "FULLSCREEN_DIALOG",
	[8] = "TOOLTIP",
}

-- frames array (obtained with /fstack then pressing CTRL on mouseover)
local MoveCRFM_frames = {
	CompactRaidFrameManager,
}

local function MoveCRFM_framesAlpha(frames,alpha)
	for _,f in ipairs(frames) do
		f:SetAlpha(alpha)
	end
end

-- main functionality
local function MoveCRFM_move()
	local anchorMyselfAt, anchorTo, anchorToAt, coordX, coordY = CompactRaidFrameManager:GetPoint()
	CompactRaidFrameManager:SetPoint(anchorMyselfAt, anchorTo, anchorToAt, coordX, Move_CompactRaidFrameManager.y)
end
local function MoveCRFM_fade()
	if not Move_CompactRaidFrameManager or not Move_CompactRaidFrameManager.fade then
		MoveCRFM_framesAlpha(MoveCRFM_frames,1)
	elseif CompactRaidFrameManager:IsMouseOver() or not CompactRaidFrameManager.collapsed then
		MoveCRFM_framesAlpha(MoveCRFM_frames,1)
	else
		MoveCRFM_framesAlpha(MoveCRFM_frames,0)
	end
end
local function MoveCRFM_strata()
	CompactRaidFrameManager:SetFrameStrata(MoveCRFM_stratas[Move_CompactRaidFrameManager.strata])
end
local function MoveCRFM_set()
	MoveCRFM_move()
	MoveCRFM_fade()
	MoveCRFM_strata()
end

-- persist through sessions functionality
local function MoveCRFM_loaded(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Move_CompactRaidFrameManager" then
		if not Move_CompactRaidFrameManager then
			MoveCRFM_instructions()
			Move_CompactRaidFrameManager = {
				y = select(5,CompactRaidFrameManager:GetPoint()),
				fade = false,
				strata = 2,
			}
		end
		MoveCRFM_set()
		-- append ourselves into blizzard's frames
		hooksecurefunc("CompactRaidFrameManager_Toggle", function()
			MoveCRFM_move()
			MoveCRFM_fade()
		end)
	end
end

-- event triggers
local MoveCRFM = CreateFrame("Frame")
MoveCRFM:RegisterEvent("ADDON_LOADED")
MoveCRFM:SetScript("OnEvent", MoveCRFM_loaded)
CompactRaidFrameManager:HookScript("OnShow", MoveCRFM_fade)
CompactRaidFrameManager:HookScript("OnEnter", MoveCRFM_fade)
CompactRaidFrameManager:HookScript("OnLeave", MoveCRFM_fade)

-- slash command functionality
SLASH_MOVERM1 = "/moverm"
function SlashCmdList.MOVERM(msg, editbox)
	local msgY = tonumber(string.match(msg, "^(-?%d+\.?%d?)$"))
	local msgFade = string.match(string.upper(msg), "^YES$") or string.match(string.upper(msg), "^NO$")
	local msgStrata = tonumber(string.match(string.lower(msg), "^strata ([1-8])$"))
	local msgPrint = string.match(string.lower(msg), "^print$")
	if msgY then
		Move_CompactRaidFrameManager.y = msgY
		MoveCRFM_move()
	elseif msgFade then
		if msgFade == "YES" then
			Move_CompactRaidFrameManager.fade = true
		else
			Move_CompactRaidFrameManager.fade = false
		end
		MoveCRFM_fade()
	elseif msgStrata then
		Move_CompactRaidFrameManager.strata = msgStrata
		MoveCRFM_strata()
	elseif msgPrint then
		print(colorOrange .. "Fade: " .. exitColor .. tostring(Move_CompactRaidFrameManager.fade))
		print(colorOrange .. "Strata: " .. exitColor .. tostring(Move_CompactRaidFrameManager.strata))
		print(colorOrange .. "Coord: " .. exitColor .. "y=" .. tostring(Move_CompactRaidFrameManager.y))
	else
		print(colorRed .. "Incorrect use of" .. exitColor .. " /moverm")
		MoveCRFM_instructions()
	end
end