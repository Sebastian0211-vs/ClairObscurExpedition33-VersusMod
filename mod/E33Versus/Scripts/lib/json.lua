-- Minimal JSON for the E33 Versus net bridge: encode Lua tables (arrays = sequences) and decode objects/arrays.
JSON = JSON or {}
local esc = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function encStr(s) return '"' .. s:gsub('[%c"\\]', function(c) return esc[c] or ("\\u%04x"):format(c:byte()) end) .. '"' end
local function isArray(t)
  local n = 0; for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end
function JSON.encode(v)
  local ty = type(v)
  if ty == "nil" then return "null"
  elseif ty == "boolean" then return v and "true" or "false"
  elseif ty == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    return (("%.14g"):format(v))
  elseif ty == "string" then return encStr(v)
  elseif ty == "table" then
    local arr, n = isArray(v)
    local parts = {}
    if arr and n > 0 then
      for i = 1, n do parts[i] = JSON.encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, x in pairs(v) do parts[#parts + 1] = encStr(tostring(k)) .. ":" .. JSON.encode(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode " .. ty)
end

local function skip(s, i) local _, e = s:find("^[ \n\r\t]*", i); return e + 1 end
local decodeValue
local function decodeString(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" then error("unterminated string") end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local n = s:sub(j + 1, j + 1)
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if n == "u" then
        local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
        out[#out + 1] = utf8 and utf8.char(cp) or string.char(cp % 256); j = j + 6
      else out[#out + 1] = map[n] or n; j = j + 2 end
    else
      out[#out + 1] = c; j = j + 1
    end
  end
end
function decodeValue(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}; i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
      local k; k, i = decodeString(s, skip(s, i)); i = skip(s, i)
      if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
      t[k], i = decodeValue(s, i + 1); i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return t, i + 1 elseif d ~= "," then error("expected , or } at " .. i) end
      i = i + 1
    end
  elseif c == "[" then
    local t = {}; i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
      t[#t + 1], i = decodeValue(s, i); i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return t, i + 1 elseif d ~= "," then error("expected , or ] at " .. i) end
      i = i + 1
    end
  elseif c == '"' then return decodeString(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return nil, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num or num == "" then error("bad json at " .. i) end
    return tonumber(num), i + #num
  end
end
function JSON.decode(s) local v = decodeValue(s, 1); return v end
