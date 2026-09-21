# Rich Text Utils

Rich Text Utils parses rich-text strings and makes their readable characters,
formatting, and tag metadata available to Luau code.

## API

### Functions

* `RichTextIterator(text)` returns an iterator of readable characters.
* `RichTextLength(text)` returns the number of readable characters.

### RichTextParser

Create a parser when several kinds of information are needed from the same
string:

```lua
local parser = RichTextUtils.RichTextParser.new(text)
```

Methods:

* `Length()` returns the number of readable characters.
* `Iterator()` returns `(index, character, currentText)` for each readable item.
* `TagEvents()` returns tag events in source order.
* `EventIterator()` returns tag events and readable text in source order.
* `PlaybackIterator()` returns tag events and formatted character data for
  typewriter or dialogue playback.

## Basic iteration

`currentText` contains the text assembled up to the current character, including
the formatting tags needed to display it correctly.

```lua
for index, character, currentText in parser:Iterator() do
    textLabel.Text = currentText
end
```

The readable length includes normal characters, supported escape sequences, and
readable self-closing tags such as `<br/>`. Formatting tags do not contribute to
the length.

## Tag events

`TagEvents()` exposes the tags without requiring callers to parse tag strings:

```lua
for event in parser:TagEvents() do
    print(event.Kind, event.Name, event.Raw)

    for property, value in event.Properties do
        print(property, value)
    end
end
```

Each event contains:

* `Kind`: `"Entered"`, `"Closed"`, or `"SelfClosed"`.
* `Name`: the tag name.
* `Properties`: a map of property names to string values.
* `Raw`: the original tag text.

Quoted and unquoted property values are supported. A property without `=` has
an empty-string value, and duplicate properties use the last value. Property
types are application-specific, so numeric values can be converted with
`tonumber`.

Self-closing tags emit one `"SelfClosed"` event and do not create an active
scope. `<br/>` and `<br />` produce a newline as a readable item.

## Event iteration

`EventIterator()` returns a discriminated stream containing either a tag event or
readable text:

```lua
for item in parser:EventIterator() do
    if item.Type == "tag" then
        local event = item.Event
        -- Handle the tag event.
    else
        local text = item.Text
        -- Handle readable text.
    end
end
```

## Playback iteration

`PlaybackIterator()` combines tag events with the formatted character data used
by typewriter and dialogue systems:

```lua
for item in parser:PlaybackIterator() do
    if item.Type == "tag" then
        -- Handle custom tags...
    else
        --textLabel.Text = item.Current

        local character = item.Char
        local isLastCharacter = item.IsLastChar
        -- Extra character handling...
    end
end
```

Character items contain:

* `Index`: the readable character index.
* `Char`: the current readable character or escape result.
* `Current`: the formatted text up to the current character.
* `IsLastChar`: whether this is the final readable character.

Self-closing control tags do not affect `Index` or `IsLastChar`.

## Nested state example

Tags that represent temporary state, such as typing speed, can be handled with
a stack. Entering a tag saves the current value; closing it restores that value.

```lua
local speed = 1
local speedStack = {}

for item in parser:PlaybackIterator() do
    if item.Type == "tag" then
        local event = item.Event

        if event.Name == "speed" and event.Kind == "Entered" then
            table.insert(speedStack, speed)
            speed = tonumber(event.Properties.value) or speed
        elseif event.Name == "speed" and event.Kind == "Closed" then
            speed = table.remove(speedStack) or speed
        elseif event.Name == "pause" and event.Kind == "SelfClosed" then
            local duration = tonumber(event.Properties.duration)
            if duration then
                task.wait(duration)
            end
        end
    else
        -- Use speed before displaying item.Current.
    end
end
```

For reliable nesting, close tags in the same order that their opening tags were
entered. Closing tags remove the most recently active formatting scope.