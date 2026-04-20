--!optimize 2
--!strict

--------------------------------------------------------------------------------------
--                             RichTextParserUtilities                              --
--                                       v1.0                                       --     
--																					--
-- This is a library that offers utilities for iterating over the characters of a	--
-- rich text string.																--
--------------------------------------------------------------------------------------
--                                       API                                        --
--																					--
-- 	Classes:																		--
--		RichTextParser:																--
--			Methods:																--
--				Length																--
--				Iterator															--
--	Functions:																		--
--		RichTextIterator															--
--		RichTextLength																--
--------------------------------------------------------------------------------------
-- Author: razvanpacku/RazvanPacu													--
-- Contributors: 																	--
-- Date created: 20.04.2026															--
-- Date updated: 20.04.2026															--
--------------------------------------------------------------------------------------

local RichTextUtils = {}

--=== TYPES ===--

type Token = {
	Type: "escapse" | "char" | "self",
	Char: string?,
	Tags: {string},
	Tag : string?
}

export type RichTextParser = {
	__tokens: {Token},
	__len: number,
	
	Length: (self: RichTextParser) -> number,
	Iterator: (self: RichTextParser) -> (() -> (number?, string?, string))
}

--=== CONSTANTS ===--

-- What character each escape sequence maps too
local escapes : {[string]: string} = {
	["&lt;"] = "<",
	["&gt;"] = ">",
	["&quot;"] = "\"",
	["&apos;"] = "'",
	["&amp;"] = "&",
}

-- Some self closing tags map to a character
local selfClosingTags : {[string]: string} = {
	["<br/>"] = "\n",
}

--=== UTILITY FUNCTIONS ===---

--[[
	Takes a rich text string, and returns an ordered list of the tokens it's made up of, alongside the number of readable tokens (characters, escape sequences and some self closing tags)
	
	Parameters:
		@param text: string - the string to be parsed
	Return:
		@return tokens: {Token} - ordered list of the tokens the string is made up of
		@return readableTokenCount: number - number of readable tokens
]]
local function ParseRichText(text: string) : ({Token}, number)
	local tokens : {Token} = {}
	local stack : {string} = {}
	
	local charTokenCount : number = 0
	
	local nextValidPosition : number = 1
	
	for first, last in utf8.graphemes(text) do
		if first < nextValidPosition then continue end
		
		local char = text:sub(first, last)
		
		--==== ESCAPE SEQUENCES ====--
		local matchedEscape : boolean = false
		for escape, _ in pairs(escapes) do
			if text:sub(first, first + #escape -1) == escape then
				table.insert (tokens, {
					Type = "escape",
					Char = escape,
					Tags = table.clone(stack)
				} :: Token)
				nextValidPosition = first + #escape
				matchedEscape = true
				break
			end
		end
		if matchedEscape then continue end
		
		--=== TAGS ===---
		if char == "<" then
			local tag = text:match("^<[^>]->", first)
			if tag then
				--self closing tag
				if tag:sub(-2) == "/>" then
					table.insert(tokens, {
						Type = "self",
						Tag = tag,
						Tags = table.clone(stack)
					} :: Token)
				-- closing tag
				elseif tag:sub(1, 2) == "</" then
					table.remove(stack)
				-- opening tag
				else
					table.insert(stack, tag)
				end
				
				nextValidPosition = first + #tag
				if selfClosingTags[tag] then
					charTokenCount += 1
				end
				continue
			end
		end
		
		--=== NORMAL CHARACTERS ===--
		table.insert(tokens, {
			Type = "char",
			Char = char,
			Tags = table.clone(stack)
		} :: Token)
		charTokenCount += 1
	end
	
	return tokens, charTokenCount
end

--[[
	Takes an ordered list of tokens (obtained thtough a call to ParseRichText), and returns an iterator for iterating over the string in readable token order, returning the readable token index, the readable character, and the the string up to that character, however with the closing tags included so that it formats correctly.
	
	Parameters:
		@param tokens: {Token} - ordered list of tokens (obtained thtough a call to ParseRichText)
	Returns:
		@return iterator: () -> (number?, string?, string) - iterator function:
			@return index : number? - the index of the current character in the readable string
			@return currentChar : string? - the current readable character
			@return partialString: string  - the string constructed up to the current character, including the closing tags for currently opened ones.
]]
function _RichTextIterator_helper(tokens : {Token}) : () -> (number?, string?, string)
	local index : number = 0
	local tokenIndex : number = 0
	local buffer : {string} = {}
	local activeTags : {string} = {}
	local closeCache = {}

	local function contains<T>(tbl: {T}, value: T) : boolean
		for i = 1, #tbl do
			if tbl[i] == value then
				return true
			end
		end
		return false
	end

	local function closeTag(tag: string) : string
		-- cache for performance
		local cached = closeCache[tag]
		if cached then
			return cached
		end

		-- extract tag name
		-- matches: <tag ...> → tag
		local tagName = tag:match("^<%s*/?%s*([%w]+)")

		if not tagName then
			cached = "</>"
		else
			cached = "</" .. tagName .. ">"
		end

		closeCache[tag] = cached
		return cached
	end

	local function syncTags(targetTags: {string})
		-- CLOSE tags (reverse order)
		for i = #activeTags, 1, -1 do
			local tag = activeTags[i]
			if not contains(targetTags, tag) then
				buffer[#buffer+1] = closeTag(tag)
				table.remove(activeTags, i)
			end
		end

		-- OPEN tags
		for i = 1, #targetTags do
			local tag = targetTags[i]
			if not contains(activeTags, tag) then
				buffer[#buffer+1] = tag
				activeTags[#activeTags+1] = tag
			end
		end
	end

	local function buildCurrentString()
		-- copy buffer reference
		local temp = table.create(#buffer + #activeTags)

		-- copy buffer
		for i = 1, #buffer do
			temp[i] = buffer[i]
		end

		local offset = #buffer

		-- append closing tags (in reverse)
		for i = #activeTags, 1, -1 do
			temp[offset + 1] = closeTag(activeTags[i])
			offset += 1
		end

		return table.concat(temp)
	end

	return function()
		index += 1
		local token = tokens[index]
		if not token then
			return nil, nil, buildCurrentString()
		end

		if token.Type == "char" then
			syncTags(token.Tags)

			buffer[#buffer+1] = token.Char
			tokenIndex += 1

			return tokenIndex, token.Char, buildCurrentString()
		elseif token.Type == "escape" then
			syncTags(token.Tags)

			buffer[#buffer+1] = token.Char

			return tokenIndex, escapes[token.Char], buildCurrentString()
		elseif token.Type == "self" then
			syncTags(token.Tags)

			buffer[#buffer+1] = token.Tag

			local charToReturn = ""
			if token.Tag and selfClosingTags[token.Tag] then
				charToReturn = selfClosingTags[token.Tag]
				tokenIndex += 1
			end

			return tokenIndex, charToReturn, buildCurrentString()
		end

		return -1, "", buildCurrentString()
	end
end

---=== PUBLIC INTERFACE ===---

--[[
	Takes a rich text string, and returns a rich text iterator for string. See _RichTextIterator_helper and ParseRichText for more info.
	If you need both the iterator and the length, it's recommended to use a RichTextParser object.
	
	Parameters:
		@param text: string - The rich text to parse
	Returns:
		@return iterator: () -> (number, string, string) - iterator function, see _RichTextIterator_helper for more info 
]]
function RichTextUtils.RichTextIterator(text: string) : () -> (number, string, string)
	local tokens, _ = ParseRichText(text)
	return _RichTextIterator_helper(tokens) :: () -> (number, string, string)
end

--[[
	Takes a rich text string, and returns the number of readable characters it has. See ParseRichText for more info.
	If you need both the iterator and the length, it's recommended to use a RichTextParser object.
	
	Parameters:
		@param text: string - The rich text
	Returns:
		@return length: number - The readable character length of the rich text
]]
function RichTextUtils.RichTextLength(text: string) : number
	local _, len = ParseRichText(text)
	return len
end

--[[
	RichTextParser
	
	Stores the readable character length of a rich text string, and allows iteration over the string.
	It is recommended to use this if you need both the iterator and the length of the rich text, since it only calls ParseRichText once.
	
	Fields:
		@private __tokens: {Token} - The tokens of the rich text
		@private __len: number - The readable length of the rich text
	Constructors:
		new: (text: string) - Creates a RichTextParser from the given rich text
	Methods:
		@public Length: (self) -> (number) - Returns the readable character length of the rich text
		@public Iterator: (self) -> () -> (number, string, string) - Returns the rich text iterator for the given rich text. See _RichTextIterator_helper for more info
]]
local RichTextParser = {}
RichTextParser.__index = RichTextParser

--[[
	Constructs a RichTextParser object for the given rich text.
	Parameters:
		@param text: string - The rich text to parse
	Returns:
		@return self: RichTextParser - The constructed RichTextParser object
]]
function RichTextParser.new(text: string) : RichTextParser
	local self = setmetatable({}, RichTextParser)
	
	local t, l = ParseRichText(text)
	self.__tokens = t
	self.__len = l
	
	return self :: RichTextParser
end

--[[
	Returns the readable character length of the rich text associated with the parser. See ParseRichText for more info.
	
	Returns:
		@return length: number - The readable character length of the rich text
]]
function RichTextParser.Length(self: RichTextParser) : number
	return self.__len
end

--[[
	Returns a new iterator of the rich text associated with the parser. See _RichTextIterator_helper for more info.
	
	Returns:
		@return iterator: () -> (number, string, string) - iterator function, see _RichTextIterator_helper for more info 
]]
function RichTextParser.Iterator(self: RichTextParser) : () -> (number, string, string)
	return _RichTextIterator_helper(self.__tokens) :: () -> (number, string, string)
end

RichTextUtils.RichTextParser = RichTextParser

return RichTextUtils
