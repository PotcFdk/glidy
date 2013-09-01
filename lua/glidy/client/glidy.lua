GLIDY_NOTE_OFF            = 0x80
GLIDY_NOTE_ON             = 0x90
GLIDY_KEY_AFTER_TOUCH     = 0xA0
GLIDY_CONTROL_CHANGE      = 0xB0
GLIDY_PROGRAM_CHANGE      = 0xC0
GLIDY_CHANNEL_AFTER_TOUCH = 0xD0
GLIDY_PITCH_WHEEL_CHANGE  = 0xE0

GLIDY_META_SEQUENCE_NUMBER = 0x00
GLIDY_META_TEXT            = 0x01
GLIDY_META_TEXT_COPYRIGHT  = 0x02
GLIDY_META_TRACK_NAME      = 0x03
GLIDY_META_INSTRUMENT_NAME = 0x04
GLIDY_META_LYRIC           = 0x05
GLIDY_META_MARKER          = 0x06
GLIDY_META_CUE_POINT       = 0x07
GLIDY_META_END             = 0x2F
GLIDY_META_TEMPO           = 0x51
GLIDY_META_TIME_SIGNATURE  = 0x58
GLIDY_META_KEY_SIGNATURE   = 0x59
--GLIDY_META_SEQUENCER_INF   = 0x7F

GLIDY_NOTEMAP_DECODE = {}
GLIDY_NOTEMAP_ENCODE = {}

-- fill notemaps

local notes = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
for i=0,0x7F do
	local note, n, o
	n = notes[math.mod(i,12)+1]
	o = math.floor(i/12)
	note = n..o
	GLIDY_NOTEMAP_DECODE[i] = note
	GLIDY_NOTEMAP_ENCODE[note] = i
end

-- helpers

local function tohex(IN)
	if IN == 0 then return 0 end
    local B,K,OUT,I,D=16,"0123456789ABCDEF","",0
    while IN>0 do
        I=I+1
        IN,D=math.floor(IN/B),math.mod(IN,B)+1
        OUT=string.sub(K,D,D)..OUT
    end
    return OUT
end

local function b2byte(fbyte1,fbyte2)
	return bit.bor( bit.lshift(fbyte1,8) , fbyte2 )
end
local function b3byte(fbyte1,fbyte2,fbyte3)
	return bit.bor( bit.lshift(b2byte(fbyte1,fbyte2),8) , fbyte3 )
end

-- parser

local MThd = 0x4D546864
local MTrk = 0x4D54726B


local function OpenFile(f)
	assert(f, "NO FILE, DUMBASS")
	
	f = file.Open("glidy/"..f, "rb", "DATA")
	assert(f, "Something went wrong while opening the file.")
	return f
end

local function ReadFileHeader(f)
	assert(bit.bswap(f:ReadLong()) == MThd, "File is not a MIDI file!")
	
	local length = f:ReadLong()
	length = bit.bswap(length)
	
	assert(length == 6, "Length should be 6, something's bad.")
	
	local format = b2byte(f:ReadByte(), f:ReadByte())
	assert(format ~= 2, "Asynchronous tracks are not implemented!")
	local tracknum = b2byte(f:ReadByte(), f:ReadByte())
	local deltatick = b2byte(f:ReadByte(), f:ReadByte())
	return format, tracknum, deltatick
end

local function ReadTracks(f, tracknum)
	local tracks = {}
	
	for i=1, tracknum do
		local id = bit.bswap(f:ReadLong())
		local length = bit.bswap(f:ReadLong())
			
		print(string.format("Reading track %d of %d with length %d...", i, tracknum, length))
			
		if id == MTrk then
			print(" -> reading")
			local data = {}
			
			local track_end = f:Tell() + length
			
			while f:Tell() < track_end do
				--print("calculating delay at: "..tohex(f:Tell()))
				local delay = 0
				local msb 
				repeat
					local td = f:ReadByte()
					msb = bit.rshift(td, 7)
					delay = bit.lshift(delay, 8)
					delay = bit.bor(delay, td)
				until msb == 0
				msb = nil	
				
				local cbyte = f:ReadByte()
				print("READING "..tohex(cbyte).." AT "..tohex(f:Tell()))
				
				if cbyte ~= 0xFF then -- normal event
					local cmd = bit.band(cbyte, 0xF0)
					local channel = bit.band(cbyte, 0xF)
					
					--print("Parsing: ",tohex(cbyte),cmd)
					
					if cmd == 0x80 then -- note on
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0x90 then -- note off
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0xA0 then -- key after-touch
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0xB0 then -- control change
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							controller = f:ReadByte(),
							value = f:ReadByte()
						})
					elseif cmd == 0xC0 then -- patch change
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							value = f:ReadByte()
						})
					elseif cmd == 0xD0 then -- channel after-touch
						table.insert(data, {
							channel = channel,
							cmd = cmd,
							channel = f:ReadByte()
						})
					elseif cmd == 0xE0 then -- pitch wheel change
						table.insert(data, {
							delay = delay,
							channel = channel,
							cmd = cmd,
							bottom = f:ReadByte(),
							top = f:ReadByte()
						})
					else error("NO. "..cmd)
					end
				else -- meta event
					local cmd = f:ReadByte()
					--print("MetaParsing: ",tohex(cmd))
					if cmd == 0x00 then -- sequence number
						f:Skip(1)
						table.insert(data, {
							meta = true,
							delay = delay,
							cmd = cmd,
							bottom = b2byte(f:ReadByte(),f:ReadByte())
						})
					elseif cmd == 0x01 or cmd == 0x02 or cmd == 0x03 or cmd == 0x04
						or cmd == 0x05 or cmd == 0x06 or cmd == 0x07 or cmd == 0x08 then -- text events
						local len = f:ReadByte()
						local str = ""
						for i=1,len do
							str = str .. string.char(f:ReadByte())
						end
						str = string.sub(str,1,-2)
						--print(" ** DECODED STRING "..str) 
						table.insert(data, {
							meta = true,
							delay = delay,
							cmd = cmd,
							text = str
						})
					elseif cmd == 0x2F then -- end of track
						f:Skip(1)
						print"-- ended track --"
						break
					elseif cmd == 0x51 then -- set tempo
						f:Skip(1)
						table.insert(data, {
							meta = true,
							delay = delay,
							cmd = cmd,
							tempo = b3byte(f:ReadByte(),f:ReadByte(),f:ReadByte())
						})
					elseif cmd == 0x58 then -- time signature
						f:Skip(1)
						table.insert(data, {
							meta = true,
							delay = delay,
							cmd = cmd,
							numerator = f:ReadByte(),
							denominator = f:ReadByte(),
							tickcount = f:ReadByte(),
							note32count = f:ReadByte()
						})
					elseif cmd == 0x59 then -- key signature
						f:Skip(1)
						table.insert(data, {
							meta = true,
							delay = delay,
							cmd = cmd,
							sharts_flats = f:ReadByte(),
							major_minor = f:ReadByte()
						})
					elseif cmd == 0x7F then -- sequencer specific information
						local len = f:ReadByte()
						f:Skip(len)
					else
						print("unknown meta event: ",tohex(cmd),"at",tohex(f:Tell()))
						f:Skip(f:ReadByte())
					end
				end
			end
			
			table.insert(tracks, data)
			--f:Skip(length)
		else
			print(" -> skipping")
			f:Skip(length)
		end
	end
	return tracks
end

-- test

local f = OpenFile("everythings_alright.mid")
local format, tracknum, deltatick = ReadFileHeader(f)
local tracks = ReadTracks(f, tracknum)
f:Close()

PrintTable(tracks)
