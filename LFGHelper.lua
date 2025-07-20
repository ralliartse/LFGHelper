-- Keywords to detect LFG/LFM
local keywords = {
  "lfg", "lfm", "lf", "lf1m", "lf2m", "lf3m", "lf4m"
}

local function extractDungeonName(text)
  text = string.lower(text)  -- Ensure case-insensitive
  for _, data in ipairs(LFGHelperInstancesDB) do
    if type(data.acronym) == "table" then
      -- Multiple acronyms
      for _, alias in ipairs(data.acronym) do
        local acronym = string.lower(alias)
        -- Use pattern matching with boundaries
        local pattern1 = "[^%a]" .. acronym .. "[^%a]"
        local pattern2 = "^" .. acronym .. "[^%a]"
        local pattern3 = "[^%a]" .. acronym .. "$"
        local pattern4 = "^" .. acronym .. "$"

        if string.find(text, pattern1) or string.find(text, pattern2)
            or string.find(text, pattern3) or string.find(text, pattern4) then
          return data.instanceName
        end
      end
    end
  end
  return nil
end

local function CleanupOldEntries()
    local threshold = (LFGHelperSettings.cleanupMinutes or 15) * 60  -- fallback to 15 minutes if empty
    local count = table.getn(LFGHelperPostingDB)
    for i = count, 1, -1 do  -- backwards loop to safely remove
        local data = LFGHelperPostingDB[i]
        if time() - data.timestamp > threshold then
            table.remove(LFGHelperPostingDB, i)
        end
    end
    UpdateMainFrame() -- update the main frame when cleanup is done
end

function UpdateMainFrame()
    local contentFrame = LFGHelperScrollContent
    if contentFrame.rows then
        for _, row in ipairs(contentFrame.rows) do
            row:Hide()
        end
    else
        contentFrame.rows = {}
    end
    local yOffset = -10
    local rowHeight = 20
    local currentY = -10
    local rowCount = 0
    contentFrame:SetWidth(640)  -- ensure width is consistent with your rows
    for instanceName, isVisible in pairs(LFGHelperVisibleInstances) do
        if isVisible then
            for _, postingData in ipairs(LFGHelperPostingDB) do
                if instanceName == postingData.instance then
                    local rowFrame = CreateFrame("Frame", nil, contentFrame)
                    rowFrame:SetWidth(590)
                    rowFrame:SetHeight(rowHeight)
                    rowFrame:SetPoint("TOPLEFT", 0, currentY)
                    currentY = currentY - rowHeight - 5
                    rowCount = rowCount + 1
                    local senderWidth = 60
                    local instanceWidth = 100
                    local textWidth = 340
                    local timeWidth = 60
                    -- Button
                    local button = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
                    button:SetWidth(60)
                    button:SetHeight(rowHeight)
                    button:SetPoint("LEFT", 0, 0)
                    local senderName = postingData.sender
                    local lowerText = string.lower(postingData.text or "")
                    if string.find(lowerText, "lfg") then
                        button:SetText("INVITE")
                        button:SetScript("OnClick", function(self, button)
                          if senderName then
                              print("Sending invite to: " .. senderName)
                              InviteByName(senderName)
                          else
                              print("Error: unable to retrieve the name")
                          end
                      end)
                    else
                        button:SetText("WHISPER")
                        button:SetScript("OnClick", function(self, button)
                          if senderName then
                              print("Opening whisper to: " .. senderName)
                              ChatFrame_OpenChat("/w " .. senderName .. " ")
                          else
                              print("Error: unable to retrieve the name")
                          end
                      end)
                    end

                    -- Sender Column
                    local senderFont = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    senderFont:SetText(postingData.sender)
                    senderFont:SetWidth(senderWidth)
                    senderFont:SetJustifyH("LEFT")
                    senderFont:SetPoint("LEFT", button, "RIGHT", 10, 0)

                    -- Instance Column
                    local instanceFont = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    instanceFont:SetText(postingData.instance)
                    instanceFont:SetWidth(instanceWidth)
                    instanceFont:SetJustifyH("LEFT")
                    instanceFont:SetPoint("LEFT", senderFont, "RIGHT", 10, 0)

                    -- Message Column
                    local messageFont = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    messageFont:SetText(postingData.text)
                    messageFont:SetWidth(textWidth)
                    messageFont:SetJustifyH("LEFT")
                    messageFont:SetPoint("LEFT", instanceFont, "RIGHT", 10, 0)

                    -- Timelapse Column
                    local timeFont = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    local timelapse = math.floor((time() - postingData.timestamp) / 60)
                    timeFont:SetText(timelapse .. " mins ago")
                    timeFont:SetWidth(timeWidth)
                    timeFont:SetJustifyH("LEFT")
                    timeFont:SetPoint("LEFT", messageFont, "RIGHT", 10, 0)

                    table.insert(contentFrame.rows, rowFrame)
                end
            end
        end
    end
    if rowCount == 0 then
        contentFrame:SetHeight(100)
    else
        contentFrame:SetHeight(math.abs(currentY) + 20)
    end
    LFGHelperScroll:UpdateScrollChildRect()
end

function senderAlreadyPosted(sender)
    for index, posting in ipairs(LFGHelperPostingDB) do
        if posting.sender == sender then
            return index  -- This is a numeric index
        end
    end
    return nil
end

function CreateOrUpdatePosting(sender, instance, msg, channelNumber, keyword)
    local index = senderAlreadyPosted(sender)
    CleanupOldEntries()
    if index then -- if an entry has been found, update this entry
        -- Update existing entry
        LFGHelperPostingDB[index].instance = instance
        LFGHelperPostingDB[index].text = msg
        LFGHelperPostingDB[index].timestamp = time()
    else
        -- Insert new entry
        table.insert(LFGHelperPostingDB, {
            sender = sender,
            instance = instance,
            text = msg,
            lookingfor = keyword,
            timestamp = time()
        })
    end
end

function InitializeVisibleInstance()
  for _, data in ipairs(LFGHelperInstancesDB) do
    if data.show then
      local sanitizedName = string.gsub(data.instanceName, "%s+", "_")  -- Replace spaces with underscores
      LFGHelperVisibleInstances[sanitizedName] = true
    end
  end
end

function CreateInstanceCheckboxes()
    local rowsPerColumnRaids = 3
    local rowsPerColumnDungeons = 13
    local function CreateSection(title, instanceType, rowsPerColumn, yStart)
        -- Title Label
        local titleFont = LFGHelperFilterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleFont:SetText(title)
        -- titleFont:SetPoint("TOPLEFT", 20, yStart)
        titleFont:SetPoint("TOPLEFT", LFGHelperFilterFrame, "TOPLEFT", 25, yStart)
        local row = 0
        local column = 0
        local yOffset = -20
        local xStart = 30
        local xSpacing = 180

        local currentY = yStart - 20

        for _, data in ipairs(LFGHelperInstancesDB) do
            if data.type == instanceType then
                if row >= rowsPerColumn then
                    row = 0
                    column = column + 1
                end
                local sanitizedName = string.gsub(data.instanceName, "%s+", "_")  -- Replace spaces with underscores
                local checkbox = CreateFrame("CheckButton", "LFGInstanceCheckbox_" .. sanitizedName, LFGHelperFilterFrame, "UICheckButtonTemplate")
                checkbox:SetWidth(20)
                checkbox:SetHeight(20)
                checkbox.dataReference = data
                checkbox:SetChecked(data.show)
                getglobal(checkbox:GetName().."Text"):SetText(data.instanceName)
                checkbox:SetPoint("TOPLEFT", xStart + (column * xSpacing), currentY + (row * yOffset))
                -- Set initial state
                checkbox:SetChecked(data.show)
                -- OnClick to update DB
                checkbox:SetScript("OnClick", function()
                  local checked = this:GetChecked()
                  this.dataReference.show = checked
                  if checked then
                    LFGHelperVisibleInstances[sanitizedName] = true
                  else
                    LFGHelperVisibleInstances[sanitizedName] = nil
                  end
                  UpdateMainFrame()
                end)
                row = row + 1
            end
        end
        -- Return final Y position for next section
        return currentY + (row * yOffset) - 40
    end
    local nextSectionY = -40
    nextSectionY = CreateSection("Raids", "raid", rowsPerColumnRaids, nextSectionY)
    CreateSection("Dungeons", "dungeon", rowsPerColumnDungeons, nextSectionY)
end

-- Function to populate the option window
function LoadLFGHelperOptions()
    local frame = LFGHelperOptionFrame
    local cleanupMinutes = LFGHelperSettings.cleanupMinutes or 15

    if not frame.cleanupSlider then
        local slider = CreateFrame("Slider", "LFGHelperCleanupSlider", frame, "OptionsSliderTemplate")
        slider:SetWidth(200)
        slider:SetHeight(20)
        slider:SetMinMaxValues(1, 60)
        slider:SetValueStep(1)
        slider:SetValue(cleanupMinutes)
        slider:SetPoint("TOP", 0, -60)

        getglobal(slider:GetName() .. 'Low'):SetText("1 min")
        getglobal(slider:GetName() .. 'High'):SetText("60 mins")
        getglobal(slider:GetName() .. 'Text'):SetText("Auto-Remove Postings After (mins)")

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("TOP", slider, "BOTTOM", 0, -10)
        valueText:SetText(cleanupMinutes .. " minutes")

        slider:SetScript("OnValueChanged", function()
            local value = math.floor(slider:GetValue())
            valueText:SetText(value .. " minutes")
            LFGHelperSettings.cleanupMinutes = value  -- Save the value in the variable
        end)
        frame.cleanupSlider = slider
        frame.cleanupSliderValueText = valueText
    else
        frame.cleanupSlider:SetValue(cleanupMinutes)
        frame.cleanupSliderValueText:SetText(cleanupMinutes .. " minutes")
    end
end

function CreateLFGHelperMinimapButton()
    local minimapButton = CreateFrame("Button", "LFGHelperMinimapButton", Minimap)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    minimapButton:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, 0)
    minimapButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(minimapButton, "ANCHOR_TOP")
      GameTooltip:AddLine("LFG Helper");
      GameTooltip:AddLine("Left-click to open/close the main window", 1, 1, 1);
      GameTooltip:AddLine("Right-click to open the options", 1, 1, 1);
      GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local texture = minimapButton:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    texture:SetAllPoints(minimapButton)
    minimapButton.texture = texture
    minimapButton:SetScript("OnClick", function()
      local button = arg1  -- In 1.12, use arg1 instead of self/button arguments

      if button == "LeftButton" then
          if LFGHelperFrame:IsVisible() then
              LFGHelperFrame:Hide()
          else
              LFGHelperFrame:Show()
              UpdateMainFrame()
          end
      elseif button == "RightButton" then
          if LFGHelperOptionFrame:IsVisible() then
              LFGHelperOptionFrame:Hide()
          else
              LFGHelperOptionFrame:Show()
          end
      end
    end)
    minimapButton:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    minimapButton:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)
end

-- On Addon Load
function LFGHelper_OnLoad()
    if not LFGHelperInstancesDB then
        LFGHelperInstancesDB = {
            { instanceName = "Ragefire Chasm", type = "dungeon", acronym = {"rfc", "ragefire"}, show = false },
            { instanceName = "The Deadmines", type = "dungeon", acronym = {"deadmines", "deadmine"}, show = false },
            { instanceName = "Wailing Caverns", type = "dungeon", acronym = {"wc", "wailing"}, show = false },
            { instanceName = "The Stockade", type = "dungeon", acronym = {"stockade"}, show = false },
            { instanceName = "Shadowfang Keep", type = "dungeon", acronym = {"sfk"}, show = false },
            { instanceName = "Blackfathom Deeps", type = "dungeon", acronym = {"bfd"}, show = false },
            { instanceName = "Scarlet Monastery Graveyard", type = "dungeon", acronym = {"sm grave", "smg", "graveyard"}, show = false },
            { instanceName = "Scarlet Monastery Library", type = "dungeon", acronym = {"sm lib", "library"}, show = false },
            { instanceName = "Gnomeregan", type = "dungeon", acronym = {"gnome", "gnomeregan"}, show = false },
            { instanceName = "Razorfen Kraul", type = "dungeon", acronym = {"rfk", "kraul"}, show = false },
            { instanceName = "The Crescent Grove", type = "dungeon", acronym = {"crescent", "cg", "grove"}, show = false },
            { instanceName = "Scarlet Monastery Armory", type = "dungeon", acronym = {"sm arm", "armory"}, show = false },
            { instanceName = "Scarlet Monastery Cathedral", type = "dungeon", acronym = {"sm cath", "cathedral", "cath"}, show = false },
            { instanceName = "Razorfen Down", type = "dungeon", acronym = {"rfd"}, show = false },
            { instanceName = "Uldaman", type = "dungeon", acronym = {"uld", "uldaman"}, show = false },
            { instanceName = "Gilneas City", type = "dungeon", acronym = {"gc", "gilneas"}, show = false },
            { instanceName = "Zul'Farrak", type = "dungeon", acronym = {"zf", "farrak"}, show = false },
            { instanceName = "Maraudon", type = "dungeon", acronym = {"maraudon", "mar"}, show = false },
            { instanceName = "Maraudon Princess", type = "dungeon", acronym = {"princess"}, show = false },
            { instanceName = "Temple of Atal'Hakkar", type = "dungeon", acronym = {"sunken", "temple", "atal"}, show = false },
            { instanceName = "Hateforge Quarry", type = "dungeon", acronym = {"hq", "hateforge", "quarry"}, show = false },
            { instanceName = "Blackrock Depths Arena", type = "dungeon", acronym = {"arena"}, show = false },
            { instanceName = "Blackrock Depths", type = "dungeon", acronym = {"brd"}, show = false },
            { instanceName = "Blackrock Depths Emperor", type = "dungeon", acronym = {"emperor", "emp"}, show = false },
            { instanceName = "Dire Maul", type = "dungeon", acronym = {"dm", "dmw", "dme", "dmn"}, show = false },
            { instanceName = "Scholomance", type = "dungeon", acronym = {"scholo", "scholomance"}, show = false },
            { instanceName = "Stratholme", type = "dungeon", acronym = {"strat"}, show = false },
            { instanceName = "Karazhan Crypt", type = "dungeon", acronym = {"crypt"}, show = false },
            { instanceName = "Black Morass", type = "dungeon", acronym = {"morass", "black", "bm"}, show = false },
            { instanceName = "Stormwind Vault", type = "dungeon", acronym = {"vault"}, show = false },
            { instanceName = "Upper Blackrock Spire", type = "dungeon", acronym = {"ubrs"}, show = false },
            { instanceName = "Lower Blackrock Spire", type = "dungeon", acronym = {"lbrs"}, show = false },
            { instanceName = "Molten Core", type = "raid", acronym = {"mc", "molten"}, show = false },
            { instanceName = "BlackWing Lair", type = "raid", acronym = {"bwl"}, show = false },
            { instanceName = "Emerald Sanctum", type = "raid", acronym = {"es", "emerald", "sanctum"}, show = false },
            { instanceName = "Karazhan", type = "raid", acronym = {"kara"}, show = false },
            { instanceName = "Onyxia", type = "raid", acronym = {"ony", "onyxia"}, show = false },
            { instanceName = "Zul'Gurub", type = "raid", acronym = {"zg", "gurub"}, show = false },
            { instanceName = "Naxxramas", type = "raid", acronym = {"naxx"}, show = false },
            { instanceName = "Ahn'Qiraj", type = "raid", acronym = {"aq", "ahn"}, show = false }
        }
    end

    if not LFGHelperPostingDB then
        LFGHelperPostingDB = {}
    end
    if not LFGHelperVisibleInstances then
        LFGHelperVisibleInstances = {}
    end
    if not LFGHelperSettings then
      LFGHelperSettings = {}
    end
    -- Default fallback in case cleanupMinutes isn't set
    if not LFGHelperSettings.cleanupMinutes then
        LFGHelperSettings.cleanupMinutes = 15
    end
end
-- Create main event frame
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_CHANNEL")
f:RegisterEvent("VARIABLES_LOADED")
f:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    contentFrame = LFGHelperScrollContent
    LFGHelper_OnLoad()
    InitializeVisibleInstance()
    CreateLFGHelperMinimapButton()
    -- Register slash command once UI is loaded
    SLASH_LFGHELPER1 = "/lfghelper"
    SlashCmdList["LFGHELPER"] = function(msg)
        msg = string.lower(msg or "")

        if msg == "show" then
            LFGHelperFrame:Show()
            UpdateMainFrame()

        elseif msg == "hide" then
            LFGHelperFrame:Hide()

        elseif msg == "options" then
            if LFGHelperOptionFrame:IsVisible() then
                LFGHelperOptionFrame:Hide()
            else
                LFGHelperOptionFrame:Show()
            end

        else
            -- Default toggle if no argument is provided
            if LFGHelperFrame:IsVisible() then
                LFGHelperFrame:Hide()
            else
                LFGHelperFrame:Show()
                UpdateMainFrame()
            end
        end
    end

  elseif event == "CHAT_MSG_CHANNEL" and LFGHelperFrame:IsVisible() then
    local msg = arg1
    local sender = arg2
    local language = arg3
    local channelNumber = arg8
    if (channelNumber == 2 or channelNumber == 4) then
      CleanupOldEntries()
      local lowerMsg = string.lower(msg)
        for i = 1, table.getn(keywords) do
          if string.find(lowerMsg, keywords[i]) then
            local dungeonName = extractDungeonName(lowerMsg)
            if dungeonName ~= nil then
              local sanitizedName = string.gsub(dungeonName, "%s+", "_") 
              if LFGHelperVisibleInstances[sanitizedName] then
                CreateOrUpdatePosting(sender, sanitizedName, msg, channelNumber, keyword)
                UpdateMainFrame()
              end
            end
          end
        end
    end
  end
end)