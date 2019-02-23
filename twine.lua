local Twine = {}
Twine.__index = Twine

function Twine:load( twineSource )
	-- Stage 1 Parse
	local passages = self:stage1Parser( twineSource )
	-- Stage 2 Parse
	local passageTable = self:stage2Parser( passages )

	return passageTable
end

-- helper function
function Twine:strTrim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- stage1Parser() -- Converts twine source into a table ready for further processing.
function Twine:stage1Parser( twineSource )
	if not love.filesystem.exists( twineSource ) then print('file not found: ', twineSource) return end

	local twineSourceTable = {}
	for line in love.filesystem.lines(twineSource) do
	  table.insert(twineSourceTable, line)
	end

	--[[
	-- Change the target table once the '#' separator is reached.
	-- TODO love.filesystem.lines is currently bugged on Mac OS 10.13
	-- therefore we have to use a quick workaround
	local str = love.filesystem.read(twineSource)
	for line in str:gmatch("[^\r\n]+") do
			--if line == '#' then
			--		twineSourceTable = edges
			--else
					twineSourceTable[#twineSourceTable + 1] = line
					print(line)
			--end
	end	]]

	local passageTable = {}
	local curPassage

	-- fix leading error Twine 1.4.2
	if string.sub(twineSourceTable[1],0,3) == string.char(0xEF,0xBB,0xBF) then
		twineSourceTable[1] = string.sub(twineSourceTable[1],4)
	end

	for i = 1, #twineSourceTable do
		-- Start new passage?
		if( string.sub( twineSourceTable[i], 1, 2 ) == "::" ) then
			curPassage = {}
			passageTable[#passageTable+1] = curPassage

			curPassage.name = string.sub( twineSourceTable[i], 3 )
			curPassage.name = self:strTrim( curPassage.name )

			curPassage.content = ""

			--print("New Passage:", curPassage.name)

		-- Add content to current passage
		elseif( curPassage ~= nil ) then
			if(string.len(curPassage.content) == 0 ) then
				curPassage.content = twineSourceTable[i]
			else
				curPassage.content = curPassage.content .. "\n" .. twineSourceTable[i]
			end

			--print(twineSourceTable[i])
			--print(curPassage.content)

		-- Huh?  Ignore leading junk
		else
			print( " -------------------------------------------------- " )
			print( "Warning!!, line " .. i .. ". Not in passage yet?  Ignoring line"  )
			print( " -------------------------------------------------- " )
			print( twineSourceTable[i] )
			print( " -------------------------------------------------- \n" )
		end
	end

--	love.filesystem.write("passageTable.txt", ndump(passageTable), string.len(ndump(passageTable)))
	return passageTable
end

-- Fix for obsolete linebreak (CR ist \r and LF is \n) in Twine
function Twine:cleanChars( line )
	local result = line

	-- Replace ...
	-- fixes for Twine 1.3.5 exports
	if string.len(result) <= 2 then
		result = string.gsub(result,"\r\n","") -- paired \n\r with single <br>
		result = string.gsub(result,"\n","")   -- Any remaining \n with <br>
		result = string.gsub(result,"\r","")   -- Any remaining \r with <br>

	-- Twine: fix linebreak of first line, for Twine 1.3.5 exports
	elseif string.sub(result,0,2) == "\r\n" then	-- \r\n is CRLF
		result = string.sub(result, 3)

	-- Twine: fix linebreak of first line, for Twine 1.4.2 exports
	elseif string.sub(result,0,1) == "\n" then	-- \n is LF
		result = string.sub(result, 2)
	end

	return result
end

-- stage2Parser() -- Converts stage 1 parsed passage table into table split as follows:
--
-- 1. TEXT   - Plain text segments (may contain Richtext Syntax).
-- 2. CHOICE - A basic choice as defined by a statement like this [[Hallway]].
--			   Without specifing a link the dialogue ends.
--
--			   Here you see a choice with a Link to a new Node. The Choicetext and the Link are seperated by '|'.
-- 			   [[Let\'s start with you. Who are you?|Link5]]
--
-- 3. CODE - Anything encoded in a pair of '//' / '//'  tags gets encoded as CODE as is otherwise ignored.  You can expand this functionality as you desire.
--
-- 4. SPECIAL - Similar to code, but with these tags '{{' / '}}'  - currently unused
function Twine:stage2Parser( passageTable )
	if not passageTable then return end

	local newPassageTable = {}

	-- Step over the passage table and remove the trailing carriage returns added by the twine exporter.
	--
	for i = 1, #passageTable do
		local newPassage = {}
		local name = passageTable[i].name

		newPassageTable[i] = newPassage
		newPassageTable[name] = newPassage

		newPassage.name = name
		local rawContent = passageTable[i].content
		--newPassage.rawContent = rawContent

		local ignoreRest = false

		local j = 1
		local k = 1

		local curToken

		while k <= #rawContent do
			local curLetters = string.sub( rawContent, k, k+1)

			-- Is the next bit a 'choice'?
			if( curLetters == "[[" ) then
			    -- Extract the prior text if any
				if( k > j ) then
					local tmpContent = self:cleanChars( string.sub( rawContent, j, k-1) )
					if string.len(tmpContent) > 0 then
						curToken = {}
						curToken.type = "text"
						curToken.value = tmpContent
						--print("TEXT", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
					end
				end

				-- Find the end marker for this 'choice'
				k = k + 2
				j = k
				while k <= #rawContent do
					if( string.sub( rawContent, k, k+1) == "]]" ) then
						local tmpContent = string.sub( rawContent, j, k-1)
						curToken = {}
						curToken.type = "choice"
						curToken.value = tmpContent
						--print("CHOICE", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
						k = k + 2
						j = k
						break
					end
					k = k + 1
				end
			end

			-- Is the next bit 'code'?  You can also use: << and >>
			if( curLetters == "//" ) then
			    -- Extract the prior text if any
				if( k > j ) then
					local tmpContent = self:cleanChars( string.sub( rawContent, j, k-1) )
					if string.len(tmpContent) > 0 then
						curToken = {}
						curToken.type = "text"
						curToken.value = tmpContent
						--print("TEXT", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
					end
				end

				-- Find the end marker for this 'code'
				k = k + 2
				j = k
				while k <= #rawContent do
					if( string.sub( rawContent, k, k+1) == "//" ) then
						local tmpContent = string.sub( rawContent, j, k-1)
						curToken = {}
						curToken.type = "code"
						curToken.value = tmpContent
						--print("CODE", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
						k = k + 2
						j = k
						break
					end
					k = k + 1
				end
			end

			-- Is the next bit 'special'?
			if( curLetters == "<<" ) then
			    -- Extract the prior text if any
				if( k > j ) then
					local tmpContent = self:cleanChars( string.sub( rawContent, j, k-1) )
					if string.len(tmpContent) > 0 then
						curToken = {}
						curToken.type = "text"
						curToken.value = tmpContent
						--print("TEXT", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
					end
				end

				-- Find the end marker for this 'special'
				k = k + 2
				j = k
				while k <= #rawContent do
					if( string.sub( rawContent, k, k+1) == ">>" ) then
						local tmpContent = string.sub( rawContent, j, k-1)
						curToken = {}
						curToken.type = "special"
						curToken.value = tmpContent
						--print("SPECIAL", "||"..tmpContent.."||")
						newPassage[#newPassage+1] = curToken
						k = k + 2
						j = k
						break
					end
					k = k + 1
				end
			end

			k = k + 1
		end
	end

--	love.filesystem.write("newPassageTable.txt", ndump(newPassageTable), string.len(ndump(newPassageTable)))
	return newPassageTable
end

return Twine
