--!optimize 2
--!strict

--------------------------------------------------------------------------------------
--                                  RichTextUtils                                   --
--                                       v1.1                                       --     
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
--				TagEvents															--
--				EventIterator														--
--				PlaybackIterator													--
--	Functions:																		--
--		RichTextIterator															--
--		RichTextLength																--
--------------------------------------------------------------------------------------
-- Author: razvanpacku/RazvanPacu													--
-- Contributors: 																	--
-- Date created: 20.04.2026															--
-- Date updated: 21.09.2026															--
--------------------------------------------------------------------------------------

local RichTextUtils = {}

--=== TYPES ===--

type Token = {
	Type: "escape" | "char" | "self",
	Char: string?,
	Tags: {string},
	Tag : string?
}

export type TagEvent = {
	Kind: "Entered" | "Closed" | "SelfClosed",
	Name: string,
	Properties: {[string]: string},
	Raw: string,
}

export type EventItem =
	{Type: "tag", Event: TagEvent}
|	{Type: "text", Text: string}

export type PlaybackItem =
	{Type: "tag", Event: TagEvent}
| 	{
	Type: "character",
	Index: number,
	Char: string,
	Current: string,
	IsLastChar: boolean,
}

export type RichTextParser = {
	__tokens: {Token},
	__tagEvents: {TagEvent},
	__eventItems: {EventItem},
	__len: number,

	Length: (self: RichTextParser) -> number,
	Iterator: (self: RichTextParser) -> (() -> (number?, string?, string)),
	TagEvents: (self: RichTextParser) -> (() -> TagEvent?),
	EventIterator: (self: RichTextParser) -> (() -> EventItem?),
	PlaybackIterator: (self: RichTextParser) -> (() -> PlaybackItem?),
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

local function getSelfClosingText(tag: string) : string?
	local readableText = selfClosingTags[tag]
	if readableText then
		return readableText
	end

	local tagName = tag:match("^<%s*([%w:_-]+)")
	if tagName == "br" then
		return "\n"
	end

	return nil
end

--=== UTILITY FUNCTIONS ===---

--[[
	Takes a string alongside a tag kind, and if it is a tag, returns a parsed table of the tag's kind, name and properties; and if not, returns nil.
	Parameters:
		@param tag: string - The tag to parse
		@param kind: "Entered" | "Closed" | "SelfClosed" - The kind of tag to parse
	Returns:
		@return tagEvent: TagEvent? - The parsed tag if it is a tag, else nil.

]]
local function parseTag(tag: string, kind: "Entered" | "Closed" | "SelfClosed") : TagEvent?
	local _, name, attributeText = tag:match("^<%s*(/?)%s*([%w:_-]+)(.-)>$")
	if not name then
		return nil
	end

	local properties : {[string]: string} = {}
	local position = 1
	local attributes: string = attributeText or ""
	if kind == "SelfClosed" then
		attributes = attributes:gsub("/%s*$", "")
	end

	while position <= #attributes do
		local whitespaceEnd = attributes:find("%S", position)
		if not whitespaceEnd then
			break
		end
		position = whitespaceEnd

		local propertyName, propertyEnd = attributes:match("([%w:_-]+)()", position)
		if not propertyName or not propertyEnd then
			break
		end
		position = propertyEnd

		local equalsStart = attributes:find("%S", position)
		local propertyValue = ""
		if equalsStart and attributes:sub(equalsStart, equalsStart) == "=" then
			position = equalsStart + 1
			local valueStart = attributes:find("%S", position)
			if valueStart then
				position = valueStart
				local quote = attributes:sub(position, position)
				if quote == "\"" or quote == "'" then
					local valueEnd = attributes:find(quote, position + 1, true)
					if valueEnd then
						propertyValue = attributes:sub(position + 1, valueEnd - 1)
						position = valueEnd + 1
					else
						propertyValue = attributes:sub(position + 1)
						position = #attributes + 1
					end
				else
					local valueEnd = attributes:find("%s", position)
					if valueEnd then
						propertyValue = attributes:sub(position, valueEnd - 1)
						position = valueEnd
					else
						propertyValue = attributes:sub(position)
						position = #attributes + 1
					end
				end
			end
		end

		properties[propertyName] = propertyValue
	end

	return {
		Kind = kind,
		Name = name,
		Properties = properties,
		Raw = tag,
	}
end

--[[
	Takes a rich text string, and returns an ordered list of the tokens it's made up of, alongside the number of readable tokens (characters, escape sequences and some self closing tags)
	
	Parameters:
		@param text: string - the string to be parsed
	Returns:
		@return tokens: {Token} - ordered list of the tokens the string is made up of
		@return readableTokenCount: number - number of readable tokens
]]
local function ParseRichText(text: string) : ({Token}, number, {TagEvent}, {EventItem})
	local tokens : {Token} = {}
	local tagEvents : {TagEvent} = {}
	local eventItems : {EventItem} = {}
	local stack : {string} = {}

	local charTokenCount : number = 0

	local nextValidPosition : number = 1

	for first, last in utf8.graphemes(text) do
		if first < nextValidPosition then continue end

		local char = text:sub(first, last)

		--==== ESCAPE SEQUENCES ====--
		local matchedEscape : boolean = false
		for escape, _ in escapes do
			if text:sub(first, first + #escape -1) == escape then
				table.insert (tokens, {
					Type = "escape",
					Char = escape,
					Tags = table.clone(stack)
				} :: Token)
				table.insert(eventItems, {Type = "text", Text = escapes[escape]})
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
				local tagKind : "Entered" | "Closed" | "SelfClosed"
				--self closing tag
				if tag:match("/%s*>$") then
					tagKind = "SelfClosed"
					table.insert(tokens, {
						Type = "self",
						Tag = tag,
						Tags = table.clone(stack)
					} :: Token)
					-- closing tag
				elseif tag:sub(1, 2) == "</" then
					tagKind = "Closed"
					table.remove(stack)
					-- opening tag
				else
					tagKind = "Entered"
					table.insert(stack, tag)
				end

				local parsedTag = parseTag(tag, tagKind)
				if parsedTag then
					table.insert(tagEvents, parsedTag)
					table.insert(eventItems, {Type = "tag", Event = parsedTag})
				end

				nextValidPosition = first + #tag
				local readableSelfClosingText = getSelfClosingText(tag)
				if readableSelfClosingText then
					charTokenCount += 1
					table.insert(eventItems, {Type = "text", Text = readableSelfClosingText})
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
		table.insert(eventItems, {Type = "text", Text = char})
		charTokenCount += 1
	end

	return tokens, charTokenCount, tagEvents, eventItems
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

			buffer[#buffer+1] = token.Char :: string
			tokenIndex += 1

			return tokenIndex, token.Char, buildCurrentString()
		elseif token.Type == "escape" then
			syncTags(token.Tags)

			buffer[#buffer+1] = token.Char :: string

			return tokenIndex, escapes[token.Char :: string] :: string, buildCurrentString()
		elseif token.Type == "self" then
			syncTags(token.Tags)

			buffer[#buffer+1] = token.Tag :: string

			local charToReturn = ""
			if token.Tag and getSelfClosingText(token.Tag) then
				charToReturn = getSelfClosingText(token.Tag) :: string
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

	local t, l, tagEvents, eventItems = ParseRichText(text)
	self.__tokens = t
	self.__tagEvents = tagEvents
	self.__eventItems = eventItems
	self.__len = l

	return (self :: any) :: RichTextParser
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

--[[
	Returns a new iterator over tag lifecycle events in source order.
	The returned events include the tag name, raw tag text, and parsed properties.

	Returns:
		@return iterator: () -> TagEvent? - iterator function that returns tag events in source order
]]
function RichTextParser.TagEvents(self: RichTextParser) : () -> TagEvent?
	local index = 0
	return function() : TagEvent?
		index += 1
		return self.__tagEvents[index]
	end
end

--[[
	Returns a new iterator over tag events and readable text in source order.
	Tag events are returned before the text that follows them.

	Returns:
		@return iterator: () -> EventItem? - iterator function that returns tag events and text in source order
]]
function RichTextParser.EventIterator(self: RichTextParser) : () -> EventItem?
	local index = 0
	return function() : EventItem?
		index += 1
		return self.__eventItems[index]
	end
end

--[[
	Returns a new iterator over tag events and readable characters in source order.
	Tag events are returned before the character or readable self-closing tag that follows them.

	Parameters:
		@param self: RichTextParser - The parser whose text should be iterated
	Returns:
		@return iterator: () -> PlaybackItem? - An iterator that returns tag events and character data
		@return item: PlaybackItem? - A tag event, or a character with its formatted text and last-character state
]]
function RichTextParser.PlaybackIterator(self: RichTextParser) : () -> PlaybackItem?
	local eventIndex = 0
	local readableIndex = 0
	local textIterator = _RichTextIterator_helper(self.__tokens)

	return function() : PlaybackItem?
		eventIndex += 1
		local eventItem = self.__eventItems[eventIndex]
		if not eventItem then
			return nil
		end

		if eventItem.Type == "tag" then
			if eventItem.Event.Kind == "SelfClosed" then
				textIterator()
			end
			return eventItem
		end

		local _, character, current = textIterator()
		if not character or not current then
			return nil
		end

		readableIndex += 1
		return {
			Type = "character",
			Index = readableIndex,
			Char = character,
			Current = current,
			IsLastChar = readableIndex == self.__len,
		}
	end
end

RichTextUtils.RichTextParser = RichTextParser

return RichTextUtils