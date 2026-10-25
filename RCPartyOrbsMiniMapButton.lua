-- Minimap button for RC Party Orbs
RCPartyOrbsMiniMapButtonPosition = {
	locationAngle = 45, -- degrees
}

-- Get the actual minimap radius dynamically (handles old 152px and new Dragonflight 198px minimap)
local function GetMinimapRadius()
	local w = Minimap:GetWidth()
	if w and w > 0 then
		return (w / 2) + 4  -- slightly outside the edge so button sits on the ring
	end
	return 80  -- fallback
end

local function GetMinimapCenter()
	local w = Minimap:GetWidth()
	if w and w > 0 then
		return w / 2
	end
	return 70  -- fallback
end

-- Call this to move the minimap button to its saved position
function RCPartyOrbsMiniMapButton_Reposition()
	local radius = GetMinimapRadius()
	local center = GetMinimapCenter()
	local angle  = math.rad(RCPartyOrbsMiniMapButtonPosition.locationAngle)
	RCPartyOrbsMiniMapButtonPosition.x = center - (radius * math.cos(angle))
	RCPartyOrbsMiniMapButtonPosition.y = ((radius * math.sin(angle)) - center)
	RCPartyOrbsMiniMapButton:ClearAllPoints()
	RCPartyOrbsMiniMapButton:SetPoint("TOPLEFT", "Minimap", "TOPLEFT",
		RCPartyOrbsMiniMapButtonPosition.x,
		RCPartyOrbsMiniMapButtonPosition.y)
end

function RCPartyOrbsMiniMapButtonPosition_LoadFromDefaults()
	-- Load saved angle if available
	if RCPartyOrbsDB and RCPartyOrbsDB.minimapButtonAngle then
		RCPartyOrbsMiniMapButtonPosition.locationAngle = RCPartyOrbsDB.minimapButtonAngle
	end
	-- Ensure tooltip renders above ElvUI frames
	if RCPartyOrbsMinimapButtonTooltip then
		RCPartyOrbsMinimapButtonTooltip:SetFrameStrata("TOOLTIP")
	end
	RCPartyOrbsMiniMapButton_Reposition()
end

-- Only while the button is dragged this is called every frame
function RCPartyOrbs_Minimap_Update()
	local xpos, ypos = GetCursorPosition()
	local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
	local center = GetMinimapCenter()

	xpos = xmin - xpos / UIParent:GetScale() + center
	ypos = ypos / UIParent:GetScale() - ymin - center

	RCPartyOrbsMiniMapButtonPosition.locationAngle = math.deg(math.atan2(ypos, xpos))
	RCPartyOrbsMiniMapButton_Reposition()

	-- Save position
	if not RCPartyOrbsDB then RCPartyOrbsDB = {} end
	RCPartyOrbsDB.minimapButtonAngle = RCPartyOrbsMiniMapButtonPosition.locationAngle
end

-- Put your code that you want on a minimap button click here.
function RCPartyOrbsMiniMapButton_OnClick()
	if Handle_RCPartyOrbsGUI then
		Handle_RCPartyOrbsGUI()
	else
		-- Fallback: try to show the menu directly
		if RCPartyOrbsGUI then
			if RCPartyOrbsGUI:IsVisible() then
				RCPartyOrbsGUI:Hide()
				PlaySound(830)  -- SPELLBOOKCLOSE
			else
				RCPartyOrbsGUI:Show()
				PlaySound(829)  -- SPELLBOOKOPEN
				if RCPartyOrbs_UpdateMenu then
					RCPartyOrbs_UpdateMenu()
				end
			end
		end
	end
end
