function handle_request(env)
    local path = env.REQUEST_URI:match("^/lua(.*)") or "/"

    if path == "/debug" then
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: text/html\r\n")
        uhttpd.send("\r\n")
        uhttpd.send("<h1>Debug Test</h1><p>REMOTE_ADDR: " .. (env.REMOTE_ADDR or "none") .. "</p><p>HTTP_HOST: " .. (env.HTTP_HOST or "none") .. "</p>")
        return
    end

    uhttpd.send("Status: 200 OK\r\n")
    uhttpd.send("Content-Type: text/html\r\n")
    uhttpd.send("\r\n")
    uhttpd.send("<h1>Minimal Test</h1><p>Path: " .. path .. "</p>")
end
