local JSON = require("json")
local logger = require("logger")
local _ = require("gettext")

local GoogleSearch = {
    search_server = "https://customsearch.googleapis.com",
    search_path = "/customsearch/v1",
    search_params = {
        cx = "", -- The Programmable Search Engine ID to use for this request
        key = "", -- API key
        num = 5,
    },
   -- Can be set so HTTP requests will be done under Trapper and
   -- be interruptible
   trap_widget = nil,
   -- For actions done with Trapper:dismissable methods, we may throw
   -- and error() with this code. We make the value of this error
   -- accessible here so that caller can know it's a user dismiss.
   dismissed_error_code = "Interrupted by user",
}


-- Get URL content
local function getUrlContent(url, timeout, maxtime)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local socket_url = require("socket.url")

    local parsed = socket_url.parse(url)
    if parsed.scheme ~= "http" and parsed.scheme ~= "https" then
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 10 end

    local sink = {}
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
    }

    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local content = table.concat(sink) -- empty or content accumulated till now
    -- logger.dbg("code:", code)
    -- logger.dbg("headers:", headers)
    -- logger.dbg("status:", status)
    -- logger.dbg("#content:", #content)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", code)
        return false, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", code, status)
        return false, "Network or remote server unavailable"
    end
    if not code or string.sub(code, 1, 1) ~= "2" then -- all 200..299 HTTP codes are OK
        logger.warn("HTTP status not okay:", code, status)
        return false, "Remote server error or unavailable"
    end
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, "Incomplete content received"
        end
    end
    return true, content
end

function GoogleSearch:setTrapWidget(trap_widget)
    self.trap_widget = trap_widget
end

function GoogleSearch:resetTrapWidget()
    self.trap_widget = nil
end

function GoogleSearch:loadPage(text)
    local url = require("socket.url")

    local parsed = url.parse(self.search_server)
    parsed.path = self.search_path
    parsed.query = ""

    for k, v in pairs(self.search_params) do
        parsed.query = string.format("%s%s=%s&", parsed.query, k, v)
    end
    parsed.query = parsed.query.."q="..url.escape("define "..text)

    local built_url = url.build(parsed)
    local completed, success, content
    if self.trap_widget then -- if previously set with GoogleSearch:setTrapWidget()
        local Trapper = require("ui/trapper")
        local timeout, maxtime = 30, 60
        -- We use dismissableRunInSubprocess with complex return values:
        completed, success, content = Trapper:dismissableRunInSubprocess(function()
            return getUrlContent(built_url, timeout, maxtime)
        end, self.trap_widget)
        if not completed then
            error(self.dismissed_error_code) -- "Interrupted by user"
        end
    else
        local timeout, maxtime = 10, 60
        success, content = getUrlContent(built_url, timeout, maxtime)
    end
    if not success then
        error(content)
    end

    if content ~= "" and string.sub(content, 1,1) == "{" then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            logger.dbg("google search result json:", result)
            return result
        else
            logger.warn("google search result json decoding error:", result)
            error("Failed decoding JSON")
        end
    else
        logger.warn("google search response is not json:", content)
        error("Response is not JSON")
    end
end

function GoogleSearch:searchAndGetResult(text)
    local result = self:loadPage(text)
    if result then
        return result.items
    end
end

return GoogleSearch