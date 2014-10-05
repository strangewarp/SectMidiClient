
local SectClient = pd.Class:new():register("sect-midi-client-lua")

function SectClient:initialize(sel, atoms)

	-- 1. Incoming MIDI-over-UDP commands from Sect
	-- 2. Incoming MIDI from user devices {cmd name, byte1, ... byte n}
	-- 3. Metronome ticks
	self.inlets = 3

	-- 1. Outgoing MIDI-over-UDP commands for Sect
	-- 2. Outgoing MIDI to user devices
	-- 3. Metronome timing value
	self.outlets = 3

	self.sus = {} -- Holds all sustain data for commands FROM Sect TO user devices

	-- Populate the sustain-data table
	for i = 0, 15 do
		self.sus[i] = {}
	end

	return true

end

-- On program-quit, send NOTE-OFFs for all active sustains
function SectClient:finalize()

	for i = 0, 15 do
		for k, _ in pairs(self.sus[i]) do
			self:outlet(2, "list", {"note", k, 0, i})
		end
	end

end

-- Get incoming MIDI-over-UDP commands from Sect, and send them to user devices
function SectClient:in_1_list(list)

	-- Convert incoming ASCII values into the table of commands they represent
	local conv = ""
	local t = {}
	for _, v in ipairs(list) do
		conv = conv .. string.char(v)
	end
	for unit in string.gmatch(conv, "%S+") do
		t[#t + 1] = ((#t == 2) and unit) or tonumber(unit)
	end

	pd.post("FROM SECT: " .. table.concat(t, " ")) -- debugging

	-- Get BPM and TPQ values, leaving note values in table form
	local bpm = table.remove(t, 1)
	local tpq = table.remove(t, 1)

	-- Update timing of external [metro] command, to trigger once every tick at current BPM/TPQ values
	local ms = 60000 / (bpm * tpq * 4)
	self:outlet(3, "float", {ms})

	-- Format outgoing MIDI command for Pd's weird MIDI-send style
	local out = {}
	if t[5] == nil then
		out = {t[1], t[4], t[3]}
	elseif t[6] == nil then
		out = {t[1], t[4], t[5], t[3]}
	else
		out = {t[1], t[5], t[6], t[4]}
	end

	-- Send MIDI command to external MIDI device
	self:outlet(2, "list", out)

	-- Record the note, and its duration, in the sustain-tracking table
	if t[1] == "note" then
		self.sus[t[4]][t[5]] = t[3]
	end

end

-- Get incoming MIDI commands from user devices, and send them to Sect
function SectClient:in_2_list(t)

	-- Reorganize note into Sect-style formatting, with a placeholder duration of 1 tick
	local out = {
		t[1],
		1,
		t[4],
		t[2],
		t[3],
	}

	-- Send the note to the [netsend] apparatus
	self:outlet(1, "list", t)

end


-- React to incoming metronome ticks
function SectClient:in_3_bang()

	-- Send automatic noteoffs for Sect-to-user-device notes whose durations have expired
	for chan, notes in pairs(self.sus) do
		for note, dur in pairs(notes) do
		
			-- Decrease the sustain's duration value
			self.sus[chan][note] = dur - 1
		
			-- If the duration has expired, send a note-off for the note, and unset its table value
			if self.sus[chan][note] <= 1 then
				self:outlet(2, "list", {"note", note, 0, chan})
				self.sus[chan][note] = nil
			end
			
		end
	end

end
