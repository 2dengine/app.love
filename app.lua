local lfs = love.filesystem

local app = {}

app.ready = false
app.url = "http://2dengine.com/report/"

--- Prints an error and saves the report to file
-- @param e Error
function app.error(e)
  if not e then
    return
  end
  print(e)
  -- store report to file
  lfs.write("/error.txt", e)
  -- callback
  local func = app.onerror
  if type(func) == "function" then
    func(e)
  end
end

--- Sends and deletes the previously saved error report
-- @return response body if successful
function app.report(stamp)
  local e = lfs.read("/error.txt")
  if not e then
    return
  end
  -- subject line
  local identity = lfs.getIdentity()
  local sys = love.system and love.system.getOS() or "unknown"
  local out = identity.." "..sys
  local bits
  local ffi = ffi or app.pcall(require, "ffi")
  if ffi then
    bits = ffi.abi("64bit") and "64" or "32"
  end
  if bits then
    out = out.." "..bits
  end
  if stamp then
    out = out.." "..stamp
  end
  -- sending report
  local url = require("socket.url")
  local subject = url.escape(out)
  local body = url.escape(e)
  local query = string.format("subject=%s&body=%s", subject, body)
  local http = require("socket.http")
  local b, c = http.request(app.url, query)
  if c == 200 then
    lfs.remove("/error.txt")
    return b
  end
end

--- Protected call to a function
-- @param func function
-- @param ... arguments
-- @return the first return argument if such
function app.pcall(func, ...)
  local ok, e = pcall(func, ...)
  if ok then
    return e
  end
  app.error(e)
end

--- Loads a string using a sandbox environment
-- @param sz string
-- @return function result or environment
function app.loadstring(sz, safe)
  if not safe then
    if not sz or sz:byte(1) == 27 then
      -- binary bytecode prohibited
      return
    end
  end
  local f = app.pcall(loadstring, sz)
  if not f then
    return
  end
  local env
  if not safe then
    env = {}
    setfenv(f, env)
  end
  return app.pcall(f) or env
end

--- Loads and executes a Lua file
-- @param fn filename
-- @return file return value
function app.load(fn, safe)
  if app.exists(fn) then
    local sz = app.pcall(lfs.read, fn)
    return app.loadstring(sz, safe)
  end
end

--- Loads text file
-- @param fn filename
-- @return file contents or nil
function app.read(fn, ...)
  if app.exists(fn) then
    return lfs.read(fn, ...)
  end
end

--- Saves text file
-- @param fn filename
-- @return true on success
function app.save(fn, sz)
  local ok, e = lfs.write(fn, sz)
  if not ok then
    app.error(e)
  end
  return ok
end

--- Creates a new directory
-- @param path destination path
-- @return true on success
function app.mkdir(path)
  local ok, e = lfs.createDirectory(path)
  if not ok then
    app.error(e)
  end
  return ok
end

--- Deletes a file or directory recursevly
-- @param path target path
function app.delete(path)
  if lfs.getInfo(path, "directory") then
    local d, e = lfs.getDirectoryItems(path)
    if not d then
      app.error(e)
    else
      for _, v in ipairs(d) do
        app.delete(path.."/"..v)
      end
    end
  end
  lfs.remove(path)
end

--- Finds all items within a directory
-- @param path target path
-- @ext extension filter
function app.getdir(path, ext)
  local d, e = lfs.getDirectoryItems(path)
  if not d then
    app.error(e)
  end
  if ext then
    for i = #d, 1, -1 do
      local f = d[i]
      if f:match("%.(%w+)$") ~= ext then
        table.remove(d, i)
      end
    end
  end
  return d
end

--- Checks is a file or directory exists
-- @param fn filename
-- @return true if the file exists
function app.exists(fn)
  return lfs.getInfo(fn) ~= nil
end

--- Prints to the console and log file
-- @param ... strings
local _print = print
function app.print(...)
  local s = {...}
  for i, v in ipairs(s) do
    s[i] = tostring(v)
  end
  s = table.concat(s, "\t")
  local t = os.clock()
  local n = math.floor(t*1000)
  s = n..":"..tostring(s)
  _print(s)
  if app.log then
    app.log:write(s.."\n")
  end
end

--- Loads options from file
-- @param fn filename
-- @param op destination table
function app.loadoptions(fn, op)
  local t = app.load(fn)
  if type(t) == "table" then
    for k, dv in pairs(op) do
      local sv = t[k]
      if type(dv) == type(sv) then
        op[k] = sv
      end
    end
  end
end

--- Saves options to file
-- @param fn filename
-- @param op source table
function app.saveoptions(fn, op)
  local out = ""
  for n, v in pairs(op) do
    if type(v) == "string" then
      v = string.format("%q", v)
    else
      v = tostring(v)
    end
    out = out..(n.."="..v.."\n")
  end
  app.save(fn, out)
end

--- Initializes the app and opens the log file
-- @param identity name
function app.init(identity)
  if app.ready then
    return
  end
  -- set up app identity
  app.ready = true
  lfs.setIdentity(identity)
  -- improper shutdown detection
  app.crash = app.read("/log.txt")
  if app.crash then
    app.save("/crash.txt", app.crash)
  end
  -- open new log file
  app.log = lfs.newFile("/log.txt", "w")
  print = app.print
end

--- Releases the app and closes the log file
function app.release()
  if not app.ready then
    return
  end
  app.ready = false
  -- clean up the log
  if app.log then
    app.log:close()
    app.log = nil
  end
  app.delete("/log.txt")
  app.delete("/crash.txt")
end

return app