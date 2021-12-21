--[[--
This module contains miscellaneous helper functions for the KOReader frontend.
]]

local BaseUtil = require("ffi/util")
local _ = require("gettext")
local T = BaseUtil.template

local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local bor = bit.bor

local util = {}

---- Strips all punctuation marks and spaces from a string.
---- @string text the string to be stripped
---- @treturn string stripped text
function util.stripPunctuation(text)
    if not text then return end
    -- strip ASCII punctuation marks around text
    -- and strip any generic punctuation marks (U+2000 - U+206F) in the text
    return text:gsub("\226[\128-\131][\128-\191]", ''):gsub("^%p+", ''):gsub("%p+$", '')
end

-- Various whitespace trimming helpers, from http://lua-users.org/wiki/CommonFunctions & http://lua-users.org/wiki/StringTrim
---- Remove leading whitespace from string.
---- @string s the string to be trimmed
---- @treturn string trimmed text
function util.ltrim(s)
    return (s:gsub("^%s*", ""))
end

---- Remove trailing whitespace from string.
---- @string s the string to be trimmed
---- @treturn string trimmed text
function util.rtrim(s)
    local n = #s
    while n > 0 and s:find("^%s", n) do
        n = n - 1
    end
    return s:sub(1, n)
end

---- Remove leading & trailing whitespace from string.
---- @string s the string to be trimmed
---- @treturn string trimmed text
function util.trim(s)
   local from = s:match"^%s*()"
   return from > #s and "" or s:match(".*%S", from)
end

--[[--
Splits a string by a pattern

Lua doesn't have a string.split() function and most of the time
you don't really need it because string.gmatch() is enough.
However string.gmatch() has one significant disadvantage for me:
You can't split a string while matching both the delimited
strings and the delimiters themselves without tracking positions
and substrings. The gsplit function below takes care of
this problem.

Author: Peter Odding

License: MIT/X11

Source: <a href="http://snippets.luacode.org/snippets/String_splitting_130">http://snippets.luacode.org/snippets/String_splitting_130</a>
]]
----@string str string to split
----@param pattern the pattern to split against
----@bool capture
----@bool capture_empty_entity
function util.gsplit(str, pattern, capture, capture_empty_entity)
    pattern = pattern and tostring(pattern) or '%s+'
    if (''):find(pattern) then
        error('pattern matches empty string!', 2)
    end
    return coroutine.wrap(function()
        local index = 1
        repeat
            local first, last = str:find(pattern, index)
            if first and last then
                if index < first or (index == first and capture_empty_entity) then
                    coroutine.yield(str:sub(index, first - 1))
                end
                if capture then
                    coroutine.yield(str:sub(first, last))
                end
                index = last + 1
            else
                if index <= #str then
                    coroutine.yield(str:sub(index))
                end
                break
            end
        until index > #str
    end)
end

-- Stupid helper for the duration stuff
local function passthrough(n)
    return n
end

--[[--
Converts seconds to a clock string.

Source: <a href="https://gist.github.com/jesseadams/791673">https://gist.github.com/jesseadams/791673</a>
]]
---- @int seconds number of seconds
---- @bool withoutSeconds if true 00:00, if false 00:00:00
---- @treturn string clock string in the form of 00:00 or 00:00:00
function util.secondsToClock(seconds, withoutSeconds, withDays)
    seconds = tonumber(seconds)
    if not seconds then
        if withoutSeconds then
            return "--:--"
        else
            return "--:--:--"
        end
    elseif seconds == 0 or seconds ~= seconds then
        if withoutSeconds then
            return "00:00"
        else
            return "00:00:00"
        end
    else
        local round = withoutSeconds and require("optmath").round or passthrough
        local days = "0"
        local hours
        if withDays then
            days = string.format("%d", seconds / (24*3600)) -- implicit math.floor for string.format
            hours = string.format("%02d", (seconds / 3600) % 24)
        else
            hours = string.format("%02d", seconds / 3600)
        end
        local mins = string.format("%02d", round(seconds % 3600 / 60))
        if withoutSeconds then
            if mins == "60" then
                -- Can only happen because of rounding, which only happens if withoutSeconds...
                mins = string.format("%02d", 0)
                hours = string.format("%02d", hours + 1)
            end
            return  (days ~= "0" and (days .. "d") or "") .. hours .. ":" .. mins
        else
            local secs = string.format("%02d", seconds % 60)
            return (days ~= "0" and (days .. "d") or "") .. hours .. ":" .. mins .. ":" .. secs
        end
    end
end

--- Converts seconds to a period of time string.
---- @int seconds number of seconds
---- @bool withoutSeconds if true 1h30', if false 1h30'10''
---- @bool hmsFormat, if true format 1h30m10s
---- @bool withDays, if true format 1d12h30m10s
---- @treturn string clock string in the form of 1h30'10'' or 1h30m10s
function util.secondsToHClock(seconds, withoutSeconds, hmsFormat, withDays)
    local SECONDS_SYMBOL = "\""
    seconds = tonumber(seconds)
    if seconds == 0 then
        if withoutSeconds then
            if hmsFormat then
                return T(_("%1m"), "0")
            else
                return "0'"
            end
        else
            if hmsFormat then
                return T(_("%1s"), "0")
            else
                return "0" .. SECONDS_SYMBOL
            end
        end
    elseif seconds < 60 then
        if withoutSeconds and seconds < 30 then
            if hmsFormat then
                -- @translators This is the 'm' for minute, like in 30m30s. This is a duration.
                return T(_("%1m"), "0")
            else
                return "0'"
            end
        elseif withoutSeconds and seconds >= 30 then
            if hmsFormat then
                -- @translators This is the 'm' for minute, like in 30m30s. This is a duration.
                return T(_("%1m"), "1")
            else
                return "1'"
            end
        else
            if hmsFormat then
                -- @translators This is the 'm' for minute and 's' for seconds, like in 30m30s. This is a duration.
                return T(_("%1m%2s"), "0", string.format("%02d", seconds))
            else
                return "0'" .. string.format("%02d", seconds) .. SECONDS_SYMBOL
            end
        end
    else
        local time_string = util.secondsToClock(seconds, withoutSeconds, withDays)
        if withoutSeconds then
            time_string = time_string .. ":"
        end
        if hmsFormat then
            -- @translators This is the 'h' for hour, like in 1h30m30s. This is a duration.
            time_string = time_string:gsub(":", _("h"), 1)
            -- @translators This is the 'm' for minute, like in 1h30m30s. This is a duration.
            time_string = time_string:gsub(":", _("m"), 1)
            time_string = time_string:gsub("^00" .. _("h"), "") -- delete leading "00h"
            time_string = time_string:gsub("^0", "") -- delete leading "0"
            -- @translators This is the 's' for second, like in 1h30m30s. This is a duration.
            return withoutSeconds and time_string or (time_string .. _("s"))
        else
            -- @translators This is the 'h' for hour, like in 1h30m30s. This is a duration.
            time_string = time_string:gsub(":", _("h"), 1)
            time_string = time_string:gsub(":", "'", 1)
            time_string = time_string:gsub("^00" .. _("h"), "") -- delete leading "00h"
            time_string = time_string:gsub("^0", "") -- delete leading "0"
            return withoutSeconds and time_string or (time_string .. SECONDS_SYMBOL)
        end
    end
end

--- Converts seconds to a clock type (classic or modern), based on the given format preference
--- "Classic" format calls secondsToClock, and "Modern" format calls secondsToHClock
---- @string Either "modern" for 1h30'10" or "classic" for 1:30:10
---- @bool withoutSeconds if true 1h30' or 1h30m, if false 1h30'10" or 1h30m10s
---- @bool hmsFormat, modern format only, if true format 1h30m or 1h30m10s
---- @bool withDays, if hours>=24 include days in clock string 1d12h10m10s
---- @treturn string clock string in the specific format of 1h30', 1h30'10" resp. 1h30m, 1h30m10s
function util.secondsToClockDuration(format, seconds, withoutSeconds, hmsFormat, withDays)
    if format == "modern" then
        return util.secondsToHClock(seconds, withoutSeconds, hmsFormat, withDays)
    else
        -- Assume "classic" to give safe default
        return util.secondsToClock(seconds, withoutSeconds, withDays)
    end
end

if jit.os == "Windows" then
    --- Converts timestamp to an hour string
    ---- @int seconds number of seconds
    ---- @bool twelve_hour_clock
    ---- @treturn string hour string
    ---- @note: The MS CRT doesn't support either %l & %k, or the - format modifier (as they're not technically C99 or POSIX).
    ----        They are otherwise supported on Linux, BSD & Bionic, so, just special-case Windows...
    ----        We *could* arguably feed the os.date output to gsub("^0(%d)(.*)$", "%1%2"), but, while unlikely,
    ----        it's conceivable that a translator would put something other that the hour at the front of the string ;).
    function util.secondsToHour(seconds, twelve_hour_clock)
        if twelve_hour_clock then
            if os.date("%p", seconds) == "AM" then
                -- @translators This is the time in the morning using a 12-hour clock (%I is the hour, %M the minute).
                return os.date(_("%I:%M AM"), seconds)
            else
                -- @translators This is the time in the afternoon using a 12-hour clock (%I is the hour, %M the minute).
                return os.date(_("%I:%M PM"), seconds)
            end
        else
            -- @translators This is the time using a 24-hour clock (%H is the hour, %M the minute).
            return os.date(_("%H:%M"), seconds)
        end
    end
else
    function util.secondsToHour(seconds, twelve_hour_clock, pad_with_spaces)
        if twelve_hour_clock then
            if os.date("%p", seconds) == "AM" then
                if pad_with_spaces then
                    -- @translators This is the time in the morning using a 12-hour clock (%_I is the hour, %M the minute).
                    return os.date(_("%_I:%M AM"), seconds)
                else
                    -- @translators This is the time in the morning using a 12-hour clock (%-I is the hour, %M the minute).
                    return os.date(_("%-I:%M AM"), seconds)
                end
            else
                if pad_with_spaces then
                    -- @translators This is the time in the afternoon using a 12-hour clock (%_I is the hour, %M the minute).
                    return os.date(_("%_I:%M PM"), seconds)
                else
                    -- @translators This is the time in the afternoon using a 12-hour clock (%-I is the hour, %M the minute).
                    return os.date(_("%-I:%M PM"), seconds)
                end
            end
        else
            if pad_with_spaces then
                -- @translators This is the time using a 24-hour clock (%_H is the hour, %M the minute).
                return os.date(_("%_H:%M"), seconds)
            else
                -- @translators This is the time using a 24-hour clock (%-H is the hour, %M the minute).
                return os.date(_("%-H:%M"), seconds)
            end
        end
    end
end

--- Converts timestamp to a date string
---- @int seconds number of seconds
---- @bool twelve_hour_clock
---- @treturn string date string
function util.secondsToDate(seconds, twelve_hour_clock)
    local BD = require("ui/bidi")
    -- In order to keep stuff aligned, we'll want to *keep* the padding, but using blanks instead of zeroes.
    local time = util.secondsToHour(seconds, twelve_hour_clock, true)
    -- @translators This is the date (%Y is the year, %m the month, %d the day)
    local day = os.date(_("%Y-%m-%d"), seconds)
    return BD.wrap(day) .. " " .. BD.wrap(time)
end

--[[--
Compares values in two different tables.

Source: <https://stackoverflow.com/a/32660766/2470572>
]]
---- @param o1 Lua table
---- @param o2 Lua table
---- @bool ignore_mt
---- @treturn boolean
function util.tableEquals(o1, o2, ignore_mt)
    if o1 == o2 then return true end
    local o1Type = type(o1)
    local o2Type = type(o2)
    if o1Type ~= o2Type then return false end
    if o1Type ~= 'table' then return false end

    if not ignore_mt then
        local mt1 = getmetatable(o1)
        if mt1 and mt1.__eq then
            --compare using built in method
            return o1 == o2
        end
    end

    local keySet = {}

    for key1, value1 in pairs(o1) do
        local value2 = o2[key1]
        if value2 == nil or util.tableEquals(value1, value2, ignore_mt) == false then
            return false
        end
        keySet[key1] = true
    end

    for key2, _ in pairs(o2) do
        if not keySet[key2] then return false end
    end
    return true
end

--[[--
Makes a deep copy of a table.

Source: <https://stackoverflow.com/a/16077650/2470572>
]]
---- @param o Lua table
---- @treturn Lua table
function util.tableDeepCopy(o, seen)
  seen = seen or {}
  if o == nil then return nil end
  if seen[o] then return seen[o] end

  local no
  if type(o) == "table" then
    no = {}
    seen[o] = no

    for k, v in next, o, nil do
      no[util.tableDeepCopy(k, seen)] = util.tableDeepCopy(v, seen)
    end
    setmetatable(no, util.tableDeepCopy(getmetatable(o), seen))
  else -- number, string, boolean, etc
    no = o
  end
  return no
end

--- Returns number of keys in a table.
---- @param t Lua table
---- @treturn int number of keys in table t
function util.tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

--- Append all elements from t2 into t1.
---- @param t1 Lua table
---- @param t2 Lua table
function util.arrayAppend(t1, t2)
    for _, v in ipairs(t2) do
        table.insert(t1, v)
    end
end

--[[--
Remove elements from an array, fast.

Swap & pop, like <http://lua-users.org/lists/lua-l/2013-11/msg00027.html> / <https://stackoverflow.com/a/28942022>, but preserving order.
c.f., <https://stackoverflow.com/a/53038524>

@table t Lua array to filter
@func keep_cb Filtering callback. Takes three arguments: table, index, new index. Returns true to *keep* the item. See link above for potential uses of the third argument.

@usage

local foo = { "a", "b", "c", "b", "d", "e" }
local function drop_b(t, i, j)
    -- Discard any item with value "b"
    return t[i] ~= "b"
end
util.arrayRemove(foo, drop_b)
]]
function util.arrayRemove(t, keep_cb)
    local j, n = 1, #t

    for i = 1, n do
        if keep_cb(t, i, j) then
            -- Move i's kept value to j's position, if it's not already there.
            if i ~= j then
                t[j] = t[i]
                t[i] = nil
            end
            -- Increment position of where we'll place the next kept value.
            j = j + 1
        else
            t[i] = nil
        end
    end

    return t
end

--- Reverse array elements in-place in table t
---- @param t Lua table
function util.arrayReverse(t)
    local i, j = 1, #t
    while i < j do
        t[i], t[j] = t[j], t[i]
        i = i + 1
        j = j - 1
    end
end

--- Test whether t contains a value equal to v
--- (or such a value that callback returns true),
--- and if so, return the index.
---- @param t Lua table
---- @param v
---- @func callback(v1, v2)
function util.arrayContains(t, v, cb)
    cb = cb or function(v1, v2) return v1 == v2 end
    for _k, _v in ipairs(t) do
        if cb(_v, v) then
            return _k
        end
    end
    return false
end

--- Test whether array t contains a reference to array n (at any depth at or below m)
---- @param t Lua table (array only)
---- @param n Lua table (array only)
---- @int m Max nesting level
function util.arrayReferences(t, n, m, l)
    if not m then m = 15 end
    if not l then l = 0 end
    if l > m then
        return false
    end

    if type(t) == "table" then
        if t == n then
            return true, l
        end

        for _, v in ipairs(t) do
            local matched, depth = util.arrayReferences(v, n, m, l + 1)
            if matched then
                return matched, depth
            end
        end
    end

    return false
end

-- Merge t2 into t1, overwriting existing elements if they already exist
-- Probably not safe with nested tables (c.f., https://stackoverflow.com/q/1283388)
---- @param t1 Lua table
---- @param t2 Lua table
function util.tableMerge(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
end

--[[--
Gets last index of character in string (i.e., strrchr)

Returns the index within this string of the last occurrence of the specified character
or -1 if the character does not occur.

To find . you need to escape it.
]]
---- @string string
---- @string ch
---- @treturn int last occurrence or -1 if not found
function util.lastIndexOf(string, ch)
    local i = string:match(".*" .. ch .. "()")
    if i == nil then return -1 else return i - 1 end
end

--- Pattern which matches a single well-formed UTF-8 character, including
--- theoretical >4-byte extensions.
-- Taken from <https://www.lua.org/manual/5.4/manual.html#pdf-utf8.charpattern>
util.UTF8_CHAR_PATTERN = '[%z\1-\127\194-\253][\128-\191]*'

--- Reverse the individual greater-than-single-byte characters
-- @string string to reverse
-- Taken from <https://github.com/blitmap/lua-utf8-simple#utf8reverses>
function util.utf8Reverse(text)
    text = text:gsub(util.UTF8_CHAR_PATTERN, function (c) return #c > 1 and c:reverse() end)
    return text:reverse()
end

--- Splits string into a list of UTF-8 characters.
---- @string text the string to be split.
---- @treturn table list of UTF-8 chars
function util.splitToChars(text)
    local tab = {}
    if text ~= nil then
        local prevcharcode, charcode = 0
        -- Supports WTF-8 : https://en.wikipedia.org/wiki/UTF-8#WTF-8
        -- a superset of UTF-8, that includes UTF-16 surrogates
        -- in UTF-8 bytes (forbidden in well-formed UTF-8).
        -- We may get that from bad producers or converters.
        -- (luajson, used to decode Wikipedia API json, will not correctly decode
        -- this sample: <span lang=\"got\">\ud800\udf45</span> : single Unicode
        -- char https://www.compart.com/en/unicode/U+10345 and will give us
        -- "\xed\xa0\x80\xed\xbd\x85" as UTF8, instead of the correct "\xf0\x90\x8d\x85")
        -- From http://www.unicode.org/faq/utf_bom.html#utf16-1
        --   Surrogates are code points from two special ranges of
        --   Unicode values, reserved for use as the leading, and
        --   trailing values of paired code units in UTF-16. Leading,
        --   also called high, surrogates are from D800 to DBFF, and
        --   trailing, or low, surrogates are from DC00 to DFFF. They
        --   are called surrogates, since they do not represent
        --   characters directly, but only as a pair.
        local hi_surrogate
        local hi_surrogate_uchar
        for uchar in text:gmatch(util.UTF8_CHAR_PATTERN) do
            charcode = BaseUtil.utf8charcode(uchar)
            -- (not sure why we need this prevcharcode check; we could get
            -- charcode=nil with invalid UTF-8, but should we then really
            -- ignore the following charcode ?)
            if prevcharcode then -- utf8
                if charcode and charcode >= 0xD800 and charcode <= 0xDBFF then
                    if hi_surrogate then -- previous unconsumed one, add it even if invalid
                        table.insert(tab, hi_surrogate_uchar)
                    end
                    hi_surrogate = charcode
                    hi_surrogate_uchar = uchar -- will be added if not followed by low surrogate
                elseif hi_surrogate and charcode and charcode >= 0xDC00 and charcode <= 0xDFFF then
                    -- low surrogate following a high surrogate, good, let's make them a single char
                    charcode = lshift((hi_surrogate - 0xD800), 10) + (charcode - 0xDC00) + 0x10000
                    table.insert(tab, util.unicodeCodepointToUtf8(charcode))
                    hi_surrogate = nil
                else
                    if hi_surrogate then -- previous unconsumed one, add it even if invalid
                        table.insert(tab, hi_surrogate_uchar)
                    end
                    hi_surrogate = nil
                    table.insert(tab, uchar)
                end
            end
            prevcharcode = charcode
        end
    end
    return tab
end

--- Tests whether c is a CJK character
---- @string c
---- @treturn boolean true if CJK
function util.isCJKChar(c)
    -- Smallest CJK codepoint is 0x1100 which requires at least 3 utf8 bytes to
    -- encode (U+07FF is the largest codepoint that can be represented in 2
    -- bytes with utf8). So if the character is shorter than 3 bytes it's
    -- definitely not CJK and no need to decode it.
    if #c < 3 then
        return false
    end
    local code = BaseUtil.utf8charcode(c)
    -- The weird bracketing is intentional -- we use the lowest possible
    -- codepoint as a shortcut so if the codepoint is below U+1100 we
    -- immediately return false.
    return -- BMP (Plane 0)
            code >=  0x1100 and (code <=  0x11FF  or -- Hangul Jamo
           (code >=  0x2E80 and  code <=  0x9FFF) or -- Numerous CJK Blocks (NB: has some gaps)
           (code >=  0xA960 and  code <=  0xA97F) or -- Hangul Jamo Extended-A
           (code >=  0xAC00 and  code <=  0xD7AF) or -- Hangul Syllables
           (code >=  0xD7B0 and  code <=  0xD7FF) or -- Hangul Jame Extended-B
           (code >=  0xF900 and  code <=  0xFAFF) or -- CJK Compatibility Ideographs
           (code >=  0xFE30 and  code <=  0xFE4F) or -- CJK Compatibility Forms
           (code >=  0xFF00 and  code <=  0xFFEF) or -- Halfwidth and Fullwidth Forms
           -- SIP (Plane 2)
           (code >= 0x20000 and  code <= 0x2A6DF) or -- CJK Unified Ideographs Extension B
           (code >= 0x2A700 and  code <= 0x2B73F) or -- CJK Unified Ideographs Extension C
           (code >= 0x2B740 and  code <= 0x2B81F) or -- CJK Unified Ideographs Extension D
           (code >= 0x2B820 and  code <= 0x2CEAF) or -- CJK Unified Ideographs Extension E
           (code >= 0x2CEB0 and  code <= 0x2EBEF) or -- CJK Unified Ideographs Extension F
           (code >= 0x2F800 and  code <= 0x2FA1F) or -- CJK Compatibility Ideographs Supplement
           -- TIP (Plane 3)
           (code >= 0x30000 and  code <= 0x3134F))   -- CJK Unified Ideographs Extension G
end

--- Tests whether str contains CJK characters
---- @string str
---- @treturn boolean true if CJK
function util.hasCJKChar(str)
    for c in str:gmatch(util.UTF8_CHAR_PATTERN) do
        if util.isCJKChar(c) then
            return true
        end
    end
    return false
end

--- Split texts into a list of words, spaces and punctuation marks.
---- @string text text to split
---- @treturn table list of words, spaces and punctuation marks
function util.splitToWords(text)
    local wlist = {}
    for word in util.gsplit(text, "[%s%p]+", true) do
        -- if space split word contains CJK characters
        if util.hasCJKChar(word) then
            -- split all non-ASCII characters separately (FIXME ideally we
            -- would split only the CJK characters, but you cannot define CJK
            -- characters trivially with a byte-only Lua pattern).
            for char in util.gsplit(word, "[\192-\255][\128-\191]+", true) do
                table.insert(wlist, char)
            end
        else
            table.insert(wlist, word)
        end
    end
    return wlist
end

-- We don't want to split on a space if it is followed by some
-- specific punctuation marks : e.g. "word :" or "word )"
-- (In French, there is a non-breaking space before a colon, and it better
-- not be wrapped there.)
local non_splittable_space_tailers = ":;,.!?)]}$%=-+*/|<>»”"
-- Same if a space has some specific other punctuation mark before it
local non_splittable_space_leaders = "([{$=-+*/|<>«“"


-- Similar rules exist for CJK text. Taken from :
-- https://en.wikipedia.org/wiki/Line_breaking_rules_in_East_Asian_languages

local cjk_non_splittable_tailers = table.concat( {
    -- Simplified Chinese
    "!%),.:;?]}¢°·’\"†‡›℃∶、。〃〆〕〗〞﹚﹜！＂％＇），．：；？！］｝～",
    -- Traditional Chinese
    "!),.:;?]}¢·–—’\"•、。〆〞〕〉》」︰︱︲︳﹐﹑﹒﹓﹔﹕﹖﹘﹚﹜！），．：；？︶︸︺︼︾﹀﹂﹗］｜｝､",
    -- Japanese
    ")]｝〕〉》」』】〙〗〟’\"｠»ヽヾーァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ々〻‐゠–〜?!‼⁇⁈⁉・、:;,。.",
    -- Korean
    "!%),.:;?]}¢°’\"†‡℃〆〈《「『〕！％），．：；？］｝",
})

local cjk_non_splittable_leaders = table.concat( {
    -- Simplified Chinese
    "$(£¥·‘\"〈《「『【〔〖〝﹙﹛＄（．［｛￡￥",
    -- Traditional Chinese
    "([{£¥‘\"‵〈《「『〔〝︴﹙﹛（｛︵︷︹︻︽︿﹁﹃﹏",
    -- Japanese
    "([｛〔〈《「『【〘〖〝‘\"｟«",
    -- Korean
    "$([{£¥‘\"々〇〉》」〔＄（［｛｠￥￦#",
})

local cjk_non_splittable = table.concat( {
    -- Japanese
    "—…‥〳〴〵",
})

--- Test whether a string can be separated by this char for multi-line rendering.
-- Optional next or prev chars may be provided to help make the decision
---- @string c
---- @string next_c
---- @string prev_c
---- @treturn boolean true if splittable, false if not
function util.isSplittable(c, next_c, prev_c)
    if util.isCJKChar(c) then
        -- a CJKChar is a word in itself, and so is splittable
        if cjk_non_splittable:find(c, 1, true) then
            -- except a few of them
            return false
        elseif next_c and cjk_non_splittable_tailers:find(next_c, 1, true) then
            -- but followed by a char that is not permitted at start of line
            return false
        elseif prev_c and cjk_non_splittable_leaders:find(prev_c, 1, true) then
            -- but preceded by a char that is not permitted at end of line
            return false
        else
            -- we can split on this CJKchar
            return true
        end
    elseif c == " " then
        -- we only split on a space (so a punctuation mark sticks to prev word)
        -- if next_c or prev_c is provided, we can make a better decision
        if next_c and non_splittable_space_tailers:find(next_c, 1, true) then
            -- this space is followed by some punctuation mark that is better kept with us
            return false
        elseif prev_c and non_splittable_space_leaders:find(prev_c, 1, true) then
            -- this space is lead by some punctuation mark that is better kept with us
            return false
        else
            -- we can split on this space
            return true
        end
    end
    -- otherwise, not splittable
    return false
end

--- Gets filesystem type of a path.
--
-- Checks if the path occurs in <code>/proc/mounts</code>
---- @string path an absolute path
---- @treturn string filesystem type
function util.getFilesystemType(path)
    local mounts = io.open("/proc/mounts", "r")
    if not mounts then return nil end
    local type
    for line in mounts:lines() do
        local mount = {}
        for param in line:gmatch("%S+") do table.insert(mount, param) end
        if string.match(path, mount[2]) then
            type = mount[3]
            if mount[2] ~= '/' then
                break
            end
        end
    end
    mounts:close()
    return type
end

--- Recursively scan directory for files inside
-- @string path
-- @func callback(fullpath, name, attr)
function util.findFiles(dir, cb)
    local function scan(current)
        local ok, iter, dir_obj = pcall(lfs.dir, current)
        if not ok then return end
        for f in iter, dir_obj do
            local path = current.."/"..f
            -- lfs can return nil here, as it will follow symlinks!
            local attr = lfs.attributes(path) or {}
            if attr.mode == "directory" then
                if f ~= "." and f ~= ".." then
                    scan(path)
                end
            elseif attr.mode == "file" or attr.mode == "link" then
                cb(path, f, attr)
            end
        end
    end
    scan(dir)
end

--- Checks if directory is empty.
---- @string path
---- @treturn bool
function util.isEmptyDir(path)
    local lfs = require("libs/libkoreader-lfs")
    -- lfs.dir will crash rather than return nil if directory doesn't exist O_o
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then return end
    for filename in iter, dir_obj do
        if filename ~= '.' and filename ~= '..' then
            return false
        end
    end
    return true
end

--- check if the given path is a file
---- @string path
---- @treturn bool
function util.fileExists(path)
    local file = io.open(path, "r")
    if file ~= nil then
         file:close()
         return true
    end
end

--- Checks if the given path exists. Doesn't care if it's a file or directory.
---- @string path
---- @treturn bool
function util.pathExists(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") ~= nil
end

--- As `mkdir -p`.
-- Unlike [lfs.mkdir](https://keplerproject.github.io/luafilesystem/manual.html#mkdir)(),
-- does not error if the directory already exists, and creates intermediate directories as needed.
-- @string path the directory to create
-- @treturn bool true on success; nil, err_message on error
function util.makePath(path)
    path = path:gsub("/+$", "")
    if util.pathExists(path) then return true end

    local success, err = util.makePath((util.splitFilePathName(path)))
    if not success then
        return nil, err.." (creating "..path..")"
    end

    local lfs = require("libs/libkoreader-lfs")
    return lfs.mkdir(path)
end

--- As `rm`
-- @string path of the file to remove
-- @treturn bool true on success; nil, err_message on error
function util.removeFile(file)
    local lfs = require("libs/libkoreader-lfs")
    if file and lfs.attributes(file, "mode") == "file" then
        return os.remove(file)
    elseif file then
        return nil, file .. " is not a file"
    else
        return nil, "file is nil"
    end
end

-- Gets total, used and available bytes for the mountpoint that holds a given directory.
-- @string path of the directory
-- @treturn table with total, used and available bytes
function util.diskUsage(dir)
    -- safe way of testing df & awk
    local function doCommand(d)
        local handle = io.popen("df -k " .. d .. " 2>&1 | awk '$3 ~ /[0-9]+/ { print $2,$3,$4 }' 2>&1 || echo ::ERROR::")
        if not handle then return end
        local output = handle:read("*all")
        handle:close()
        if not output:find "::ERROR::" then
            return output
        end
    end
    local err = { total = nil, used = nil, available = nil }
    local lfs = require("libs/libkoreader-lfs")
    if not dir or lfs.attributes(dir, "mode") ~= "directory" then return err end
    local usage = doCommand(dir)
    if not usage then return err end
    local stage, result = {}, {}
    for size in usage:gmatch("%w+") do
        table.insert(stage, size)
    end
    for k, v in pairs({"total", "used", "available"}) do
        if stage[k] ~= nil then
            -- sizes are in kb, return bytes here
            result[v] = stage[k] * 1024
        end
    end
    return result
end


--- Replaces characters that are invalid filenames.
--
-- Replaces the characters <code>\/:*?"<>|</code> with an <code>_</code>.
-- These characters are problematic on Windows filesystems. On Linux only
-- <code>/</code> poses a problem.
---- @string str filename
---- @treturn string sanitized filename
local function replaceAllInvalidChars(str)
    if str then
        return str:gsub('[\\,%/,:,%*,%?,%",%<,%>,%|]','_')
    end
end

--- Replaces slash with an underscore.
---- @string str
---- @treturn string
local function replaceSlashChar(str)
    if str then
        return str:gsub('%/','_')
    end
end

--[[--
Replaces characters that are invalid in filenames.

Replaces the characters `\/:*?"<>|` with an `_` unless an optional path is provided. These characters are problematic on Windows filesystems. On Linux only the `/` poses a problem.

If an optional path is provided, @{util.getFilesystemType}() will be used to determine whether stricter VFAT restrictions should be applied.
]]
---- @string str
---- @string path
---- @int limit
---- @treturn string safe filename
function util.getSafeFilename(str, path, limit, limit_ext)
    local filename, suffix = util.splitFileNameSuffix(str)
    local replaceFunc = replaceAllInvalidChars
    local safe_filename
    -- VFAT supports a maximum of 255 UCS-2 characters, although it's probably treated as UTF-16 by Windows
    -- default to a slightly lower limit just in case
    limit = limit or 240
    limit_ext = limit_ext or 10

    -- Always assume the worst on Android (#7837)
    if path and not BaseUtil.isAndroid() then
        local file_system = util.getFilesystemType(path)
        if file_system ~= "vfat" and file_system ~= "fuse.fsp" then
            replaceFunc = replaceSlashChar
        end
    end

    if suffix:len() > limit_ext then
        -- probably not an actual file extension, or at least not one we'd be
        -- dealing with, so strip the whole string
        filename = str
        suffix = nil
    end

    filename = util.htmlToPlainTextIfHtml(filename)
    filename = filename:sub(1, limit)
    -- the limit might result in broken UTF-8, which we don't want in the result
    filename = util.fixUtf8(filename, "")

    if suffix and suffix ~= "" then
        safe_filename = replaceFunc(filename) .. "." .. replaceFunc(suffix)
    else
        safe_filename = replaceFunc(filename)
    end

    return safe_filename
end

--- Splits a file into its directory path and file name.
--- If the given path has a trailing /, returns the entire path as the directory
--- path and "" as the file name.
---- @string file
---- @treturn string directory, filename
function util.splitFilePathName(file)
    if file == nil or file == "" then return "", "" end
    if string.find(file, "/") == nil then return "", file end
    return file:match("(.*/)(.*)")
end

--- Splits a file name into its pure file name and suffix
---- @string file
---- @treturn string path, extension
function util.splitFileNameSuffix(file)
    if file == nil or file == "" then return "", "" end
    if string.find(file, "%.") == nil then return file, "" end
    return file:match("(.*)%.(.*)")
end

--- Gets file extension
---- @string filename
---- @treturn string extension
function util.getFileNameSuffix(file)
    local _, suffix = util.splitFileNameSuffix(file)
    return suffix
end

--- Companion helper function that returns the script's language,
--- based on the file extension.
---- @string filename
---- @treturn string (lowercase) (or nil if not Device:canExecuteScript(file))
function util.getScriptType(file)
    local file_ext = string.lower(util.getFileNameSuffix(file))
    if file_ext == "sh" then
        return "shell"
    elseif file_ext == "py" then
        return "python"
    end
end

--- Gets human friendly size as string
---- @int size (bytes)
---- @bool right_align (by padding with spaces on the left)
---- @treturn string
function util.getFriendlySize(size, right_align)
    local frac_format = right_align and "%6.1f" or "%.1f"
    local deci_format = right_align and "%6d" or "%d"
    size = tonumber(size)
    if not size or type(size) ~= "number" then return end
    if size > 1000*1000*1000 then
        -- @translators This is an abbreviation for the gigabyte, a unit of computer memory or data storage capacity.
        return T(_("%1 GB"), string.format(frac_format, size/1000/1000/1000))
    end
    if size > 1000*1000 then
        -- @translators This is an abbreviation for the megabyte, a unit of computer memory or data storage capacity.
        return T(_("%1 MB"), string.format(frac_format, size/1000/1000))
    end
    if size > 1000 then
        -- @translators This is an abbreviation for the kilobyte, a unit of computer memory or data storage capacity.
        return T(_("%1 kB"), string.format(frac_format, size/1000))
    else
        -- @translators This is an abbreviation for the byte, a unit of computer memory or data storage capacity.
        return T(_("%1 B"), string.format(deci_format, size))
    end
end

--- Gets formatted size as string (1273334 => "1,273,334")
---- @int size (bytes)
---- @treturn string
function util.getFormattedSize(size)
    local s = tostring(size)
    s = s:reverse():gsub("(%d%d%d)", "%1,")
    s = s:reverse():gsub("^,", "")
    return s
end

--[[--
Replaces invalid UTF-8 characters with a replacement string.

Based on <http://notebook.kulchenko.com/programming/fixing-malformed-utf8-in-lua>.
c.f.,    FixUTF8 @ <https://github.com/pkulchenko/ZeroBraneStudio/blob/master/src/util.lua>.

@string str the string to be checked for invalid characters
@string replacement the string to replace invalid characters with
@treturn string valid UTF-8
]]
function util.fixUtf8(str, replacement)
    local pos = 1
    local len = #str
    while pos <= len do
        if     str:find("^[%z\1-\127]", pos) then pos = pos + 1
        elseif str:find("^[\194-\223][\128-\191]", pos) then pos = pos + 2
        elseif str:find(       "^\224[\160-\191][\128-\191]", pos)
            or str:find("^[\225-\236][\128-\191][\128-\191]", pos)
            or str:find(       "^\237[\128-\159][\128-\191]", pos)
            or str:find("^[\238-\239][\128-\191][\128-\191]", pos) then pos = pos + 3
        elseif str:find(       "^\240[\144-\191][\128-\191][\128-\191]", pos)
            or str:find("^[\241-\243][\128-\191][\128-\191][\128-\191]", pos)
            or str:find(       "^\244[\128-\143][\128-\191][\128-\191]", pos) then pos = pos + 4
        else
            str = str:sub(1, pos - 1) .. replacement .. str:sub(pos + 1)
            pos = pos + #replacement
            len = len + #replacement - 1
        end
    end
    return str
end

--- Splits input string with the splitter into a table. This function ignores the last empty entity.
--
--- @string str the string to be split
--- @string splitter
--- @bool capture_empty_entity
--- @treturn an array-like table
function util.splitToArray(str, splitter, capture_empty_entity)
    local result = {}
    for word in util.gsplit(str, splitter, false, capture_empty_entity) do
        table.insert(result, word)
    end
    return result
end

--- Convert a Unicode codepoint (number) to UTF-8 char
--- c.f., <https://stackoverflow.com/a/4609989>
---     & <https://stackoverflow.com/a/38492214>
--- See utf8charcode in ffi/util for a decoder.
--
--- @int c Unicode codepoint
--- @treturn string UTF-8 char
function util.unicodeCodepointToUtf8(c)
    if c < 0x80 then
        return string.char(c)
    elseif c < 0x800 then
        return string.char(
                bor(0xC0, rshift(c, 6)),
                bor(0x80, band(c, 0x3F))
        )
    elseif c < 0x10000 then
        if c >= 0xD800 and c <= 0xDFFF then
            return '�' -- Surrogates -> U+FFFD REPLACEMENT CHARACTER
        end
        return string.char(
                bor(0xE0, rshift(c, 12)),
                bor(0x80, band(rshift(c, 6), 0x3F)),
                bor(0x80, band(c, 0x3F))
        )
    elseif c < 0x110000 then
        return string.char(
                bor(0xF0, rshift(c, 18)),
                bor(0x80, band(rshift(c, 12), 0x3F)),
                bor(0x80, band(rshift(c, 6), 0x3F)),
                bor(0x80, band(c, 0x3F))
        )
    else
        return '�' -- Invalid -> U+FFFD REPLACEMENT CHARACTER
    end
end

-- we need to use an array of arrays to keep them ordered as written
local HTML_ENTITIES_TO_UTF8 = {
    {"&lt;", "<"},
    {"&gt;", ">"},
    {"&quot;", '"'},
    {"&apos;", "'"},
    {"&nbsp;", "\xC2\xA0"},
    {"&#(%d+);", function(x) return util.unicodeCodepointToUtf8(tonumber(x)) end},
    {"&#x(%x+);", function(x) return util.unicodeCodepointToUtf8(tonumber(x, 16)) end},
    {"&amp;", "&"}, -- must be last
}
--[[--
Replace HTML entities with their UTF-8 encoded equivalent in text.

Supports only basic ones and those with numbers (no support for named entities like `&eacute;`).

@int string text with HTML entities
@treturn string UTF-8 text
]]
function util.htmlEntitiesToUtf8(text)
    for _, t in ipairs(HTML_ENTITIES_TO_UTF8) do
        text = text:gsub(t[1], t[2])
    end
    return text
end

--[[--
Convert simple HTML to plain text.

This may fail on complex HTML (with styles, scripts, comments), but should be fine enough with simple HTML as found in EPUB's `<dc:description>`.

@string text HTML text
@treturn string plain text
]]
function util.htmlToPlainText(text)
    -- Replace <br> with \n
    text = text:gsub("%s*<%s*br%s*/?>%s*", "\n") -- <br> and <br/>
    -- Replace <p> with \n\t (\t, unlike any combination of spaces,
    -- ensures a constant indentation when text is justified.)
    text = text:gsub("%s*</%s*p%s*>%s*", "\n") -- </p>
    text = text:gsub("%s*<%s*p%s*/>%s*", "\n") -- standalone <p/>
    text = text:gsub("%s*<%s*p%s*>%s*", "\n\t") -- <p>
        -- (this one last, so \t is not removed by the others' %s)
    -- Remove all HTML tags
    text = text:gsub("<[^>]*>", "")
    -- Convert HTML entities
    text = util.htmlEntitiesToUtf8(text)
    -- Trim spaces and new lines at start and end, including
    -- the \t we added (this looks fine enough with multiple
    -- paragraphs, but feels nicer with a single paragraph,
    -- whether it contains <br>s or not).
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    return text
end

--- Convert HTML to plain text if text seems to be HTML
-- Detection of HTML is simple and may raise false positives
-- or negatives, but seems quite good at guessing content type
-- of text found in EPUB's <dc:description>.
--
--- @string text the string with possibly some HTML
--- @treturn string cleaned text
function util.htmlToPlainTextIfHtml(text)
    local is_html = false
    -- Quick way to check if text is some HTML:
    -- look for html tags
    local _, nb_tags
    _, nb_tags = text:gsub("<%w+.->", "")
    if nb_tags > 0 then
        is_html = true
    else
        -- no <tag> found
        -- but we may meet some text badly/twice encoded html containing "&lt;br&gt;"
        local nb_encoded_tags
        _, nb_encoded_tags = text:gsub("&lt;%a+&gt;", "")
        if nb_encoded_tags > 0 then
            is_html = true
            -- decode one of the two encodes
            text = util.htmlEntitiesToUtf8(text)
        end
    end

    if is_html then
        text = util.htmlToPlainText(text)
    else
        -- if text ends with ]]>, it probably comes from <![CDATA[ .. ]]> that
        -- crengine has extracted correctly, but let the ending tag in, so
        -- let's remove it
        text = text:gsub("]]>%s*$", "")
    end
    return text
end

--- Encode the HTML entities in a string
--- @string text the string to escape
-- Taken from https://github.com/kernelsauce/turbo/blob/e4a35c2e3fb63f07464f8f8e17252bea3a029685/turbo/escape.lua#L58-L70
function util.htmlEscape(text)
    return text:gsub("[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;",
    })
end

--- Prettify a CSS stylesheet
-- Not perfect, but enough to make some ugly CSS readable.
-- By default, each selector and each property is put on its own line.
-- With condensed=true, condense each full declaration on a single line.
--
--- @string CSS string
--- @boolean condensed[opt=false] true to condense each declaration on a line
--- @treturn string the CSS prettified
function util.prettifyCSS(css_text, condensed)
    if not condensed then
        -- Get rid of \t so we can use it as a replacement/hiding char
        css_text = css_text:gsub("\t", " ")
        -- Wrap and indent declarations
        css_text = css_text:gsub("%s*{%s*", " {\n    ")
        css_text = css_text:gsub(";%s*}%s*", ";\n}\n")
        css_text = css_text:gsub(";%s*([^}])", ";\n    %1")
        css_text = css_text:gsub("%s*}%s*", "\n}\n")
        -- Cleanup declarations
        css_text = css_text:gsub("{[^}]*}", function(s)
            s = s:gsub("%s*:%s*", ": ")
            -- Temporarily hide/replace ',' in declaration so they
            -- are not matched and made multi-lines by followup gsub
            s = s:gsub("%s*,%s*", "\t")
            return s
        end)
        -- Have each selector (separated by ',') on a new line
        css_text = css_text:gsub("%s*,%s*", " ,\n")
        -- Restore hidden ',' in declarations
        css_text = css_text:gsub("\t", ", ")
    else
        -- Go thru previous method to have something standard to work on
        css_text = util.prettifyCSS(css_text)
        -- And condense that
        css_text = css_text:gsub(" {\n    ", " { ")
        css_text = css_text:gsub(";\n    ", "; ")
        css_text = css_text:gsub("\n}", " }")
        css_text = css_text:gsub(" ,\n", ", ")
    end
    return css_text
end

--- Escape list for shell usage
--- @table args the list of arguments to escape
--- @treturn string the escaped and concatenated arguments
function util.shell_escape(args)
    local escaped_args = {}
    for _, arg in ipairs(args) do
        arg = "'" .. arg:gsub("'", "'\\''") .. "'"
        table.insert(escaped_args, arg)
    end
    return table.concat(escaped_args, " ")
end

--- Clear all the elements from a table without reassignment.
--- @table t the table to be cleared
function util.clearTable(t)
    local c = #t
    for i = 0, c do t[i] = nil end
end

--- Encode URL also known as percent-encoding see https://en.wikipedia.org/wiki/Percent-encoding
--- @string text the string to encode
--- @treturn encode string
--- Taken from https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
function util.urlEncode(url)
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w%-%.%_%~%!%*%'%(%)])", char_to_hex)
    return url
end

--- Decode URL (reverse process to util.urlEncode())
--- @string text the string to decode
--- @treturn decode string
--- Taken from https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
function util.urlDecode(url)
    local hex_to_char = function(x)
        return string.char(tonumber(x, 16))
    end
    if url == nil then
        return
    end
    url = url:gsub("%%(%x%x)", hex_to_char)
    return url
end

--- Check lua syntax of string
--- @string text lua code text
--- @treturn string with parsing error, nil if syntax ok
function util.checkLuaSyntax(lua_text)
    local lua_code_ok, err = loadstring(lua_text)
    if lua_code_ok then
        return nil
    end
    -- Replace: [string "blah blah..."]:3: '=' expected near '123'
    -- with: Line 3: '=' expected near '123'
    err = err:gsub("%[string \".-%\"]:", "Line ")
    return err
end

--- Simple startsWith string helper.
--
-- C.f., <http://lua-users.org/wiki/StringRecipes>.
-- @string str source string
-- @string start string to match
-- @treturn bool true on success
function util.stringStartsWith(str, start)
   return str:sub(1, #start) == start
end

--- Simple endsWith string helper.
-- @string str source string
-- @string ending string to match
-- @treturn bool true on success
function util.stringEndsWith(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

local WrappedFunction_mt = {
    __call = function(self, ...)
        if self.before_callback then
            self.before_callback(self.target_table, ...)
        end
        if self.func then
            return self.func(...)
        end
    end,
}

--- Wrap (or replace) a table method with a custom method, in a revertable way.
-- This allows you extend the features of an existing module by modifying its
-- internal methods, and then revert them back to normal later if necessary.
--
-- The most notable use-case for this is VirtualKeyboard's inputbox method
-- wrapping to allow keyboards to add more complicated state-machines to modify
-- how characters are input.
--
-- The returned table is the same table `target_table[target_field_name]` is
-- set to. In addition to being callable, the new method has two sub-methods:
--
--  * `:revert()` will un-wrap the method and revert it to the original state.
--
--    Note that if a method is wrapped multiple times, reverting it will revert
--    it to the state of the method when util.wrapMethod was called (and if
--    called on the table returned from util.wrapMethod, that is the state when
--    that particular util.wrapMethod was called).
--
--  * `:raw_call(...)` will call the original method with the given arguments
--    and return whatever it returns.
--
--    This makes it more ergonomic to use the wrapped table methods in the case
--    where you've replaced the regular function with your own implementation
--    but you need to call the original functions inside your implementation.
--
--  * `:raw_method_call(...)` will call the original method with the arguments
--    `(target_table, ...)` and return whatever it returns. Note that the
--    target_table used is the one associated with the util.wrapMethod call.
--
--    This makes it more ergonomic to use the wrapped table methods in the case
--    where you've replaced the regular function with your own implementation
--    but you need to call the original functions inside your implementation.
--
--    This is effectively short-hand for `:raw_call(target_table, ...)`.
--
-- This is loosely based on busted/luassert's spies implementation (MIT).
--   <https://github.com/Olivine-Labs/luassert/blob/v1.7.11/src/spy.lua>
--
-- @tparam table target_table The table whose method will be wrapped.
-- @tparam string target_field_name The name of the field to wrap.
-- @tparam nil|func new_func If non-nil, this function will be called instead of the original function after wrapping.
-- @tparam nil|func before_callback If non-nil, this function will be called (with the arguments (target_table, ...)) before the function is called.
function util.wrapMethod(target_table, target_field_name, new_func, before_callback)
    local old_func = target_table[target_field_name]
    local wrapped = setmetatable({
        target_table = target_table,
        target_field_name = target_field_name,
        old_func = old_func,

        before_callback = before_callback,
        func = new_func or old_func,

        revert = function(self)
            if not self.reverted then
                self.target_table[self.target_field_name] = self.old_func
                self.reverted = true
            end
        end,

        raw_call = function(self, ...)
            if self.old_func then
                return self.old_func(...)
            end
        end,

        raw_method_call = function(self, ...)
            return self:raw_call(self.target_table, ...)
        end,
    }, WrappedFunction_mt)
    target_table[target_field_name] = wrapped
    return wrapped
end

return util
