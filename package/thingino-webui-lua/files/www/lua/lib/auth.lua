local auth = {}
local utils = require("utils")

-- Verify user credentials against system passwd/shadow
function auth.verify_user(username, password)
    if not username or not password or username == "" or password == "" then
        return false
    end

    -- In thingino single-user mode, only root user exists
    if username ~= "root" then
        return false
    end

    -- Read root's password hash from shadow file
    local shadow_file = io.open("/etc/shadow", "r")
    if not shadow_file then
        -- If no shadow file, try fallback authentication
        return auth.verify_fallback_auth(password)
    end

    local root_hash = nil
    for line in shadow_file:lines() do
        local user, hash = line:match("^([^:]+):([^:]+)")
        if user == "root" then
            root_hash = hash
            break
        end
    end
    shadow_file:close()

    if not root_hash then
        -- No root entry found, try fallback
        return auth.verify_fallback_auth(password)
    end

    if root_hash == "" or root_hash == "*" or root_hash == "!" then
        -- Root account disabled or no password set, try fallback
        return auth.verify_fallback_auth(password)
    end

    -- Verify password using system crypt
    return auth.verify_password_hash(password, root_hash)
end

-- Fallback authentication for thingino systems
function auth.verify_fallback_auth(password)
    -- No fallback authentication - must use proper password verification
    return false
end

-- Verify password against hash using system crypt
function auth.verify_password_hash(password, hash)
    -- Use thingino's BusyBox mkpasswd for password verification
    local salt = auth.extract_salt(hash)
    if not salt then
        return false
    end

    -- Try BusyBox mkpasswd first (thingino camera)
    local cmd = "mkpasswd -S '" .. salt .. "'"

    if hash:match("^%$6%$") then
        cmd = cmd .. " -m sha512"
    elseif hash:match("^%$5%$") then
        cmd = cmd .. " -m sha256"
    elseif hash:match("^%$1%$") then
        cmd = cmd .. " -m md5"
    else
        cmd = cmd .. " -m des"
    end

    cmd = cmd .. " '" .. password:gsub("'", "'\"'\"'") .. "'"

    local handle = io.popen(cmd .. " 2>/dev/null")
    if handle then
        local computed_hash = handle:read("*line")
        handle:close()

        if computed_hash and computed_hash:gsub("%s+$", "") == hash then
            return true
        end
    end

    -- Fallback to standard mkpasswd (development environment)
    cmd = "mkpasswd -S '" .. salt .. "'"

    if hash:match("^%$6%$") then
        cmd = cmd .. " -m sha512crypt"
    elseif hash:match("^%$5%$") then
        cmd = cmd .. " -m sha256crypt"
    elseif hash:match("^%$1%$") then
        cmd = cmd .. " -m md5crypt"
    else
        cmd = cmd .. " -m descrypt"
    end

    cmd = cmd .. " '" .. password:gsub("'", "'\"'\"'") .. "'"

    handle = io.popen(cmd .. " 2>/dev/null")
    if handle then
        local computed_hash = handle:read("*line")
        handle:close()

        if computed_hash and computed_hash:gsub("%s+$", "") == hash then
            return true
        end
    end

    return false
end

-- Extract salt from password hash
function auth.extract_salt(hash)
    if not hash then
        return nil
    end

    -- Handle different hash formats
    if hash:match("^%$6%$") then
        -- SHA-512 format: $6$salt$hash
        return hash:match("^%$6%$([^%$]+)%$")
    elseif hash:match("^%$5%$") then
        -- SHA-256 format: $5$salt$hash
        return hash:match("^%$5%$([^%$]+)%$")
    elseif hash:match("^%$1%$") then
        -- MD5 format: $1$salt$hash
        return hash:match("^%$1%$([^%$]+)%$")
    else
        -- Traditional DES format (first 2 characters are salt)
        return hash:sub(1, 2)
    end
end

-- Check if user exists in system
function auth.user_exists(username)
    if not username or username == "" then
        return false
    end

    local passwd_file = io.open("/etc/passwd", "r")
    if not passwd_file then
        return false
    end

    local exists = false
    for line in passwd_file:lines() do
        local user = line:match("^([^:]+):")
        if user == username then
            exists = true
            break
        end
    end
    passwd_file:close()

    return exists
end

-- Get user information
function auth.get_user_info(username)
    if not username or username == "" then
        return nil
    end

    local passwd_file = io.open("/etc/passwd", "r")
    if not passwd_file then
        return nil
    end

    local user_info = nil
    for line in passwd_file:lines() do
        local user, x, uid, gid, gecos, home, shell = line:match("^([^:]+):([^:]*):([^:]+):([^:]+):([^:]*):([^:]+):([^:]+)")
        if user == username then
            user_info = {
                username = user,
                uid = tonumber(uid),
                gid = tonumber(gid),
                gecos = gecos,
                home = home,
                shell = shell
            }
            break
        end
    end
    passwd_file:close()

    return user_info
end

-- Check if user has admin privileges
function auth.is_admin(username)
    local user_info = auth.get_user_info(username)
    if not user_info then
        return false
    end

    -- Root user (UID 0) is always admin
    if user_info.uid == 0 then
        return true
    end

    -- Check if user is in admin groups
    local groups_cmd = "groups " .. username .. " 2>/dev/null"
    local handle = io.popen(groups_cmd)
    if handle then
        local groups = handle:read("*line")
        handle:close()

        if groups then
            -- Check for common admin groups
            for group in groups:gmatch("%S+") do
                if group == "wheel" or group == "sudo" or group == "admin" then
                    return true
                end
            end
        end
    end

    return false
end

-- Rate limiting for login attempts
local login_attempts = {}

function auth.check_rate_limit(remote_addr)
    if not remote_addr then
        return true
    end

    local now = os.time()
    local attempts = login_attempts[remote_addr]

    if not attempts then
        login_attempts[remote_addr] = {count = 0, last_attempt = now}
        return true
    end

    -- Reset counter if last attempt was more than 15 minutes ago
    if (now - attempts.last_attempt) > 900 then
        attempts.count = 0
        attempts.last_attempt = now
        return true
    end

    -- Allow up to 5 attempts per 15 minutes
    return attempts.count < 5
end

function auth.record_login_attempt(remote_addr, success)
    if not remote_addr then
        return
    end

    local now = os.time()
    local attempts = login_attempts[remote_addr]

    if not attempts then
        login_attempts[remote_addr] = {count = 0, last_attempt = now}
        attempts = login_attempts[remote_addr]
    end

    if success then
        -- Reset counter on successful login
        attempts.count = 0
    else
        -- Increment counter on failed login
        attempts.count = attempts.count + 1
    end

    attempts.last_attempt = now
end

-- Clean up old rate limit entries
function auth.cleanup_rate_limits()
    local now = os.time()
    for addr, attempts in pairs(login_attempts) do
        if (now - attempts.last_attempt) > 3600 then -- 1 hour
            login_attempts[addr] = nil
        end
    end
end

-- Password strength validation
function auth.validate_password_strength(password)
    if not password then
        return false, "Password is required"
    end

    if #password < 8 then
        return false, "Password must be at least 8 characters long"
    end

    if not password:match("%d") then
        return false, "Password must contain at least one number"
    end

    if not password:match("%l") then
        return false, "Password must contain at least one lowercase letter"
    end

    if not password:match("%u") then
        return false, "Password must contain at least one uppercase letter"
    end

    return true, "Password is strong"
end

-- Change user password
function auth.change_password(username, old_password, new_password)
    -- Verify current password
    if not auth.verify_user(username, old_password) then
        return false, "Current password is incorrect"
    end

    -- Validate new password strength
    local valid, message = auth.validate_password_strength(new_password)
    if not valid then
        return false, message
    end

    -- Use system passwd command to change password
    local cmd = string.format("echo '%s:%s' | chpasswd",
                             username:gsub("'", "'\"'\"'"),
                             new_password:gsub("'", "'\"'\"'"))

    local result = os.execute(cmd)
    if result == 0 then
        return true, "Password changed successfully"
    else
        return false, "Failed to change password"
    end
end

return auth
