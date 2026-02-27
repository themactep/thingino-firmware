local session = {}
local utils = require("utils")

-- Session configuration
local SESSION_DIR = "/run/sessions" -- Use tmpfs to avoid flash writes
local SESSION_TIMEOUT = 7200 -- 2 hours (increased from 30 minutes)
local COOKIE_NAME = "thingino_session"

-- Generate a random session ID
function session.generate_id()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = ""
    
    -- Use current time and process ID for randomness
    math.randomseed(os.time() + (os.clock() * 1000000))
    
    for i = 1, 32 do
        local rand = math.random(1, #chars)
        id = id .. chars:sub(rand, rand)
    end
    
    return id
end

-- Create a new session
function session.create(username, remote_addr)
    local sess = {
        id = session.generate_id(),
        user = username,
        created = os.time(),
        last_activity = os.time(),
        remote_addr = remote_addr or "unknown"
    }
    
    -- Save session to file
    session.save(sess)
    
    return sess
end

-- Save session to file
function session.save(sess)
    -- Ensure session directory exists
    os.execute("mkdir -p " .. SESSION_DIR .. " 2>/dev/null")

    local session_file = SESSION_DIR .. "/" .. sess.id
    local file = io.open(session_file, "w")

    if file then
        file:write("user=" .. sess.user .. "\n")
        file:write("created=" .. sess.created .. "\n")
        file:write("last_activity=" .. sess.last_activity .. "\n")
        file:write("remote_addr=" .. sess.remote_addr .. "\n")
        file:close()

        -- Set file permissions (readable only by owner) - only if file exists
        local check_file = io.open(session_file, "r")
        if check_file then
            check_file:close()
            os.execute("chmod 600 " .. session_file .. " 2>/dev/null")
        end
    end
end

-- Load session from file
function session.load(session_id)
    if not session_id or session_id == "" then
        return nil
    end
    
    local session_file = SESSION_DIR .. "/" .. session_id
    local file = io.open(session_file, "r")
    
    if not file then
        return nil
    end
    
    local sess = {
        id = session_id
    }
    
    for line in file:lines() do
        local key, value = line:match("([^=]+)=(.+)")
        if key and value then
            if key == "created" or key == "last_activity" then
                sess[key] = tonumber(value)
            else
                sess[key] = value
            end
        end
    end
    
    file:close()
    
    -- Validate session data
    if not sess.user or not sess.created or not sess.last_activity then
        session.destroy(session_id)
        return nil
    end
    
    return sess
end

-- Get session from HTTP request
function session.get(env)
    local cookie_header = env.HTTP_COOKIE
    if not cookie_header then
        return nil
    end
    
    -- Parse cookies
    local session_id = nil
    for cookie in cookie_header:gmatch("([^;]+)") do
        local name, value = cookie:match("^%s*([^=]+)=(.+)%s*$")
        if name == COOKIE_NAME then
            session_id = value
            break
        end
    end
    
    if not session_id then
        return nil
    end
    
    return session.load(session_id)
end

-- Check if session is expired
function session.is_expired(sess)
    if not sess or not sess.last_activity then
        utils.log("Session expired: no session or last_activity")
        return true
    end

    -- Session timeout disabled - sessions are permanent until explicitly logged out
    return false

    -- Original timeout logic (disabled):
    -- local now = os.time()
    -- local time_diff = now - sess.last_activity
    -- local is_expired = time_diff > SESSION_TIMEOUT
    -- if is_expired then
    --     utils.log("Session expired: " .. time_diff .. "s > " .. SESSION_TIMEOUT .. "s (user: " .. (sess.user or "unknown") .. ")")
    -- end
    -- return is_expired
end

-- Update session activity
function session.update_activity(sess)
    if sess then
        local old_activity = sess.last_activity
        sess.last_activity = os.time()
        session.save(sess)
        utils.log("Session activity updated for " .. (sess.user or "unknown") .. ": " .. old_activity .. " -> " .. sess.last_activity)
    end
end

-- Create session cookie
function session.make_cookie(session_id)
    -- Set cookie to expire well after session timeout to avoid browser-side issues
    local expires = os.time() + (SESSION_TIMEOUT * 2)
    local expires_str = os.date("!%a, %d %b %Y %H:%M:%S GMT", expires)

    return COOKIE_NAME .. "=" .. session_id ..
           "; expires=" .. expires_str ..
           "; path=/; HttpOnly; SameSite=Strict"
end

-- Destroy session
function session.destroy(session_id)
    if session_id then
        local session_file = SESSION_DIR .. "/" .. session_id
        os.remove(session_file)
    end
end

-- Clean up expired sessions (disabled - sessions are permanent)
function session.cleanup_expired()
    -- Session cleanup disabled - sessions persist until explicitly logged out
    -- This prevents automatic session invalidation that could cause logout issues

    -- Original cleanup logic (disabled):
    -- local now = os.time()
    -- local handle = io.popen("ls " .. SESSION_DIR .. "/ 2>/dev/null")
    -- if handle then
    --     for filename in handle:lines() do
    --         local sess = session.load(filename)
    --         if sess and session.is_expired(sess) then
    --             session.destroy(filename)
    --         end
    --     end
    --     handle:close()
    -- end
end

-- Initialize session system
function session.init()
    -- Create session directory if it doesn't exist
    os.execute("mkdir -p " .. SESSION_DIR .. " 2>/dev/null")
    os.execute("chmod 700 " .. SESSION_DIR .. " 2>/dev/null")

    -- Clean up expired sessions
    session.cleanup_expired()
end

-- Initialize on module load
session.init()

return session
