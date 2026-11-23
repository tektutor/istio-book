-- tenant-check in Lua: the same checks as the Wasm plugins, with the
-- tenants written into the script. Lua has no counters, so this version
-- only rejects and stamps the response.
local header = "x-tenant"
local tenants = {acme = true, globex = true}                   -- (1)

local function reject(handle, status, reason)
  handle:respond(                                               -- (2)
    {[":status"] = status, ["content-type"] = "application/json"},
    '{"error": "' .. reason .. '"}\n')
end

function envoy_on_request(handle)                               -- (3)
  local tenant = handle:headers():get(header)
  if tenant == nil then
    reject(handle, "400", "missing tenant header")
  elseif not tenants[tenant] then
    reject(handle, "403", "unknown tenant")
  else
    handle:streamInfo():dynamicMetadata():set(                  -- (4)
      "envoy.filters.http.lua", "tenant", tenant)
  end
end

function envoy_on_response(handle)                              -- (5)
  local meta = handle:streamInfo():dynamicMetadata():get(
    "envoy.filters.http.lua")
  if meta ~= nil and meta["tenant"] ~= nil then
    handle:headers():add("x-tenant-checked", meta["tenant"])
  end
end
