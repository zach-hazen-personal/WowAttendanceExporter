-- Attendance Exporter Addon
-- Exports attendance to CSV via slash commands

local addonName = "AttendanceExporter"
local frame = CreateFrame("Frame")

-- Function to get current date/time string for filename
local function GetDateTimeString()
    -- Get server time using WoW's time functions
    local time = time()
    local dateStr = date("%Y%m%d", time)
    local timeStr = date("%H%M%S", time)
    return dateStr .. "_" .. timeStr
end

-- Function to get player's realm name (wrapper to handle nil)
local function GetRealmNameSafe()
    return GetRealmName() or "Unknown"
end

-- Function to get all raid members and their servers
local function GetRaidAttendance()
    local attendance = {}
    
    -- Check if we're in a raid group
    if not IsInRaid() then
        return nil, "You must be in a raid group to take attendance."
    end
    
    -- Get number of raid members
    local numRaidMembers = GetNumGroupMembers()
    
    if numRaidMembers == 0 then
        return nil, "No raid members found."
    end
    
    -- Try using UnitName API first (more reliable in WoW 12.0)
    for i = 1, numRaidMembers do
        local unitID = "raid" .. i
        local name, realm = nil, nil
        
        -- Try to get the unit name, with error handling
        local success, err = pcall(function()
            if UnitExists(unitID) then
                name, realm = UnitName(unitID)
            end
        end)
        
        -- If we didn't get a name, try alternative unit IDs
        if not name then
            if i == 1 then
                unitID = "player"
            else
                unitID = "party" .. (i - 1)
            end
            if UnitExists(unitID) then
                pcall(function()
                    name, realm = UnitName(unitID)
                end)
            end
        end
        
        if name then
            -- If realm is nil, use current realm
            if not realm or realm == "" then
                realm = GetRealmNameSafe()
            end
            table.insert(attendance, {
                name = name,
                server = realm or "Unknown"
            })
        end
    end
    
    -- Fallback to GetRaidRosterInfo if UnitName didn't work or if no members collected yet
    if #attendance == 0 then
        for i = 1, numRaidMembers do
            local success, name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = pcall(function()
                return GetRaidRosterInfo(i)
            end)
            
            if success and name then
                -- Extract server name from name (format: "Name-Server" or just "Name")
                local playerName, serverName = strsplit("-", name, 2)
                
                -- If no server specified, use current realm
                if not serverName then
                    serverName = GetRealmNameSafe()
                end
                
                table.insert(attendance, {
                    name = playerName or name,
                    server = serverName or "Unknown"
                })
            end
        end
    end
    
    if #attendance == 0 then
        return nil, "Failed to retrieve any raid member names."
    end
    
    return attendance, nil
end

-- Function to copy text to clipboard using EditBox workaround
local clipboardFrame = nil
local function CopyToClipboard(text)
    if not text or text == "" then
        return false
    end
    
    -- Clean up any existing clipboard frame
    if clipboardFrame then
        clipboardFrame:Hide()
        clipboardFrame = nil
    end
    
    -- Create a visible EditBox window for copying
    clipboardFrame = CreateFrame("Frame", "AttendanceExporterClipboardFrame", UIParent, "BasicFrameTemplateWithInset")
    clipboardFrame:SetSize(600, 400)
    clipboardFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    clipboardFrame:SetMovable(true)
    clipboardFrame:EnableMouse(true)
    clipboardFrame:RegisterForDrag("LeftButton")
    clipboardFrame:SetScript("OnDragStart", clipboardFrame.StartMoving)
    clipboardFrame:SetScript("OnDragStop", clipboardFrame.StopMovingOrSizing)
    
    -- Title
    local title = clipboardFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", clipboardFrame, "TOP", 0, -10)
    title:SetText("Attendance Data - Press Ctrl+C to Copy")
    
    -- EditBox for the CSV data (read-only)
    local editBox = CreateFrame("EditBox", "AttendanceExporterClipboardEditBox", clipboardFrame, "InputBoxTemplate")
    editBox:SetSize(580, 350)
    editBox:SetPoint("TOP", clipboardFrame, "TOP", 0, -35)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetText(text)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true) -- Allow selection
    editBox:EnableKeyboard(true) -- Allow keyboard for copy (Ctrl+C)
    
    -- Store original text
    editBox.originalText = text
    
    editBox:SetScript("OnEscapePressed", function(self)
        clipboardFrame:Hide()
    end)
    
    -- Make it read-only by preventing text changes
    editBox:SetScript("OnChar", function(self, char)
        -- Prevent any character input - restore original text immediately
        self:SetText(self.originalText)
        self:HighlightText() -- Re-select all text
    end)
    
    editBox:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput and self:GetText() ~= self.originalText then
            -- Restore original text if user tries to modify
            self:SetText(self.originalText)
            self:HighlightText() -- Re-select all text
        end
    end)
    
    -- Prevent paste operations
    editBox:SetScript("OnEditFocusGained", function(self)
        -- When focused, select all text for easy copying
        C_Timer.After(0.05, function()
            if self:HasFocus() then
                self:HighlightText()
            end
        end)
    end)
    
    -- ScrollFrame for the EditBox
    local scrollFrame = CreateFrame("ScrollFrame", "AttendanceExporterClipboardScrollFrame", clipboardFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOP", clipboardFrame, "TOP", 0, -35)
    scrollFrame:SetPoint("BOTTOM", clipboardFrame, "BOTTOM", 0, 10)
    scrollFrame:SetPoint("LEFT", clipboardFrame, "LEFT", 10, 0)
    scrollFrame:SetPoint("RIGHT", clipboardFrame, "RIGHT", -30, 0)
    scrollFrame:SetScrollChild(editBox)
    
    -- The BasicFrameTemplateWithInset template already includes a close button, so we don't need to add one
    
    -- Show and select all text
    clipboardFrame:Show()
    C_Timer.After(0.1, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    
    return true
end

-- Function to save attendance to CSV format in memory
local function WriteAttendanceToCSV(attendance)
    if not attendance or #attendance == 0 then
        return false, "No attendance data to write."
    end
    
    -- Create timestamp for reference
    local dateTimeStr = GetDateTimeString()
    local fileName = "Attendance_" .. dateTimeStr .. ".csv"
    
    -- Create CSV content
    local csvContent = "Character Name,Server\n"
    
    for _, member in ipairs(attendance) do
        -- Escape commas in names/servers by wrapping in quotes if needed
        local name = member.name:gsub('"', '""')  -- Escape quotes
        local server = member.server:gsub('"', '""')
        
        -- Wrap in quotes if contains comma
        if name:find(",") then
            name = '"' .. name .. '"'
        end
        if server:find(",") then
            server = '"' .. server .. '"'
        end
        
        csvContent = csvContent .. name .. "," .. server .. "\n"
    end
    
    -- Save to SavedVariables (replace previous entry, don't accumulate)
    if not AttendanceExporterDB then
        AttendanceExporterDB = {}
    end
    
    -- Replace the entire table with just the latest entry
    AttendanceExporterDB = {
        timestamp = dateTimeStr,
        fileName = fileName,
        csvContent = csvContent,
        data = attendance
    }
    
    -- Store in global variable for manual copy via slash command
    _AttendanceExporterLastCSV = csvContent
    
    -- Copy to clipboard
    CopyToClipboard(csvContent)
    
    return true, nil
end

-- Function to gather attendance and copy to clipboard
local function GatherAndCopyAttendance()
    -- Get attendance data with error handling
    local success, result = pcall(function()
        return GetRaidAttendance()
    end)
    
    if not success then
        print("|cFFFF0000Attendance Exporter:|r Error: " .. tostring(result))
        return false
    end
    
    local attendance, errorMsg = result, nil
    if type(result) == "string" then
        -- If result is a string, it's an error message
        errorMsg = result
        attendance = nil
    end
    
    if errorMsg then
        print("|cFFFF0000Attendance Exporter:|r " .. errorMsg)
        return false
    end
    
    if not attendance or #attendance == 0 then
        print("|cFFFF0000Attendance Exporter:|r No raid members found.")
        return false
    end
    
    -- Write CSV (this will also set the global variables and copy to clipboard)
    local writeSuccess, writeResult = pcall(function()
        return WriteAttendanceToCSV(attendance)
    end)
    
    if not writeSuccess then
        print("|cFFFF0000Attendance Exporter:|r Error: " .. tostring(writeResult))
        return false
    end
    
    local csvSuccess = writeResult
    if type(writeResult) == "string" then
        -- If it's a string, it's an error message
        print("|cFFFF0000Attendance Exporter:|r " .. writeResult)
        return false
    elseif type(writeResult) == "boolean" then
        csvSuccess = writeResult
    end
    
    if csvSuccess then
        print("|cFF00FF00Attendance Exporter:|r Copied " .. #attendance .. " members to clipboard!")
        return true
    else
        print("|cFFFF0000Attendance Exporter:|r Failed to export attendance.")
        return false
    end
end

-- Slash command handler (register early so it's always available)
SLASH_ATTENDANCEEXPORTER1 = "/attendance"
SLASH_ATTENDANCEEXPORTER2 = "/att"
SlashCmdList["ATTENDANCEEXPORTER"] = function(msg)
    if not msg or msg == "" then
        msg = "copy"
    end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") -- Trim whitespace
    
    -- Handle "copy" command - gather attendance and copy to clipboard
    if msg == "copy" then
        -- Always gather fresh attendance and copy to clipboard
        GatherAndCopyAttendance()
    elseif msg == "test" then
        print("|cFFFFFF00Attendance Exporter:|r Running test...")
        if not IsInRaid() then
            print("|cFFFF0000Attendance Exporter:|r You must be in a raid group to test.")
            return
        end
        
        -- Call GetRaidAttendance directly (it handles errors internally)
        local attendance, errorMsg = GetRaidAttendance()
        
        if errorMsg then
            print("|cFFFF0000Attendance Exporter:|r " .. errorMsg)
            return
        end
        
        if attendance and #attendance > 0 then
            print("|cFF00FF00Attendance Exporter:|r Test successful! Found " .. #attendance .. " raid members:")
            for i, member in ipairs(attendance) do
                print("  " .. i .. ". " .. member.name .. " - " .. member.server)
            end
        else
            print("|cFFFF0000Attendance Exporter:|r No raid members found or empty result")
        end
    elseif msg == "debug" then
        print("|cFFFFFF00=== ATTENDANCE EXPORTER DEBUG ===")
        print("|cFFFFFF00Addon Name:|r " .. addonName)
        print("|cFFFFFF00In Raid:|r " .. tostring(IsInRaid()))
        if IsInRaid() then
            print("|cFFFFFF00Raid Members:|r " .. GetNumGroupMembers())
        end
        print("|cFFFFFF00Last CSV Stored:|r " .. tostring(_AttendanceExporterLastCSV ~= nil))
        if AttendanceExporterDB and AttendanceExporterDB.csvContent then
            print("|cFFFFFF00Saved Record:|r Yes (timestamp: " .. (AttendanceExporterDB.timestamp or "unknown") .. ")")
        else
            print("|cFFFFFF00Saved Record:|r No (DB not initialized or empty)")
        end
        print("|cFFFFFF00=== END DEBUG ===")
    else
        print("|cFFFFFF00Attendance Exporter Commands:|r")
        print("  |cFF00FF00/attendance copy|r or |cFF00FF00/att copy|r - Gather attendance and copy to clipboard")
        print("  |cFF00FF00/attendance test|r or |cFF00FF00/att test|r - Test raid member detection")
        print("  |cFF00FF00/attendance debug|r or |cFF00FF00/att debug|r - Show debug information")
    end
end

-- Initialize addon
local function Initialize()
    print("|cFF00FF00Attendance Exporter|r loaded successfully!")
    print("|cFFFFFF00Attendance Exporter:|r Type |cFF00FF00/attendance copy|r or |cFF00FF00/att copy|r to gather attendance and copy to clipboard.")
    
    -- Verify slash command registration
    if SlashCmdList["ATTENDANCEEXPORTER"] then
        print("|cFF00FF00Attendance Exporter:|r Slash commands registered: /attendance, /att")
    else
        print("|cFFFF0000Attendance Exporter:|r WARNING: Slash commands not registered!")
    end
end

-- Run initialization when addon loads
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == addonName then
        Initialize()
    end
end)
