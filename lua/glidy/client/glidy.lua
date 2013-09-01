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


-- bit magic
-- go die

--[[local function candian4(num)
	return bit.bor(bit.bor(bit.bor((bit.band((bit.rshift(num,24)),0xff)), (bit.band(bit.lshift(num,8),0xff0000))),bit.band((bit.rshift(num,8)),0xff00)),bit.band(bit.lshift(num,24),0xff000000))
end]]

local function b2byte(fbyte1,fbyte2)
	return bit.bor( bit.lshift(fbyte1,8) , fbyte2 )
end


local MThd = 0x4D546864
local MTrk = 0x4D54726B


--Msg( tohex( byte or 0 ) .. " " )


local f = file.Find("glidy/*.mid", "DATA")

local function OpenFile(f)
	assert(f, "NO FILE, DUMBASS")
	
	f = file.Open("glidy/"..f, "r", "DATA")
	assert(f, "Something went wrong while opening the file.")
	return f
end

local function ReadFileHeader(f)
	assert(bit.bswap(f:ReadLong()) == MThd, "File is not a MIDI file!")
	
	local length = f:ReadLong()
	length = bit.bswap(length)
	
	assert(length == 6, "Length should be 6, something's bad.")
	
	local format = b2byte(f:ReadByte(), f:ReadByte())
	local tracknum = b2byte(f:ReadByte(), f:ReadByte())
	local deltatick = b2byte(f:ReadByte(), f:ReadByte())
	return format, tracknum, deltatick
end

local function ReadTracks(f, tracknum)
	local tracks = {}
	
	for i=1, tracknum do
		local id = bit.bswap(f:ReadLong())
		local length = bit.bswap(f:ReadLong()) or 1
			
		print(string.format("Reading track %d with length %d...", i, length))
			
		if id == MTrk then
			print(" -> reading")
			local data = {}
			
			local track_end = f:Tell() + length
			
			while f:Tell() < track_end do
				print("calculating delay at: "..tohex(f:Tell()))
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
				print("parsing command byte: "..tohex(cbyte).." and I was at "..tohex(f:Tell()))
				
				if cbyte ~= 0xFF then -- normal event
					local cmd = bit.band(cbyte, 0xF0)
					local channel = bit.band(cbyte, 0xF)
					
					print("Parsing: ",tohex(cbyte),cmd)
					
					if cmd == 0x80 then -- note on
						table.insert(data, {
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0x90 then -- note off
						table.insert(data, {
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0xA0 then -- key after-touch
						table.insert(data, {
							channel = channel,
							cmd = cmd,
							note = f:ReadByte(),
							velocity = f:ReadByte()
						})
					elseif cmd == 0xB0 then -- control change
						table.insert(data, {
							channel = channel,
							cmd = cmd,
							controller = f:ReadByte(),
							value = f:ReadByte()
						})
					elseif cmd == 0xC0 then -- patch change
						table.insert(data, {
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
							channel = channel,
							cmd = cmd,
							bottom = f:ReadByte(),
							top = f:ReadByte()
						})
					else error("NO. "..cmd)
					end
				else -- meta event
					local cmd = f:ReadByte()
					local len = f:ReadByte()
					--table.insert(data, {})
					f:Skip(len) print"skip"
				end
			end
			
			table.insert(tracks, data)
			--f:Skip(length)
		else
			print(" -> skipping")
			f:Skip(length)
		end
	end
end

local f = OpenFile(f[1])
local format, tracknum, deltatick = ReadFileHeader(f)
ReadTracks(f, tracknum)


f:Close()