local QBCore = exports["qb-core"]:GetCoreObject()
local Util = exports["giga-util"]:GetUtils()

-- K:V locks on player -> vehicleNetworkId
-- used for ensuring that identifiers are
-- not set by two clients at the same time
local SEMAPHORES = {}

function Debugger(identifier)
  return Util.Debugger("giga-keys:" .. identifier)
end

local function generateUUID()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

local function isVehicleExempt(vehicle)
  if not DoesEntityExist(vehicle) then return false end
  local vehicleModel = GetEntityModel(vehicle)
  for _, hash in ipairs(Config.Exempt.Vehicles) do
    if vehicleModel == hash then return true end
  end
  return false
end

local function _getPlayerIdFromCitizenId(citizenId)
  if type(citizenId) ~= "string" then return end
  local id = MySQL.scalar.await(SQL.get.player.id.from.citizenid, { citizenId, })
  if type(id) ~= "number" then return end
  return id
end
local GetPlayerIdFromCitizenId = Util.Function.Memoize(_getPlayerIdFromCitizenId)

local function getPlayerIDFromSource(playerSrc)
  local Player = QBCore.Functions.GetPlayer(playerSrc)
  if type(Player) ~= "table" then return end
  local playerData = Player.PlayerData
  if type(playerData) ~= "table" then return end
  if type(playerData.id) == "number" then return playerData.id end
  local citizenId = playerData.citizenid
  if type(citizenId) ~= "string" then return end
  return GetPlayerIdFromCitizenId(citizenId)
end

local function getVehicleIdFromIdentifier(identifier)
  if type(identifier) ~= "string" then return nil end
  local result = MySQL.scalar.await(SQL.get.vehicle.id.from.identifier, { identifier, })
  return result
end

local function getVehicleIdentifierFromNetworkId(vehicleNetworkId)
  if not vehicleNetworkId then return nil end
  local vehicle = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not DoesEntityExist(vehicle) then return nil end

  local vehicleData = Entity(vehicle).state.data
  if not vehicleData or not vehicleData.identifier then return nil end
  return vehicleData.identifier
end

local function getNetworkIdFromIdentifier(identifier)
  local debug = Debugger("GetNetworkIdFromIdentifier")
  debug({ identifier = identifier, })
  local vehicles = GetAllVehicles()
  debug({ vehicles = vehicles, })
  if type(vehicles) == "number" then return end
  for _, entityId in ipairs(vehicles) do
    local networkId = NetworkGetNetworkIdFromEntity(entityId)
    local vehicleData = Entity(entityId).state.data
    local vehicleIdentifier = (vehicleData or {}).identifier
    if vehicleIdentifier == identifier then return networkId end
  end
end

-- Memoized function for getting a role ID
local function _getVehicleRoleIdFromSlug(slug)
  if not ROLE[slug] then return nil end
  return MySQL.scalar.await(SQL.get.vehicle.role.id.from.slug, { slug, })
end
local getVehicleRoleIdFromSlug = Util.Function.Memoize(_getVehicleRoleIdFromSlug)

local function grantPlayerVehicleRole(playerSrc, vehicleNetworkId, role)
  local roleId = getVehicleRoleIdFromSlug(role)
  if not roleId then return false end
  local playerId = getPlayerIDFromSource(playerSrc)
  if type(playerId) ~= "number" then return false end
  local rowId = getVehicleIdFromIdentifier(getVehicleIdentifierFromNetworkId(vehicleNetworkId))
  if not rowId then return false end
  local result = MySQL.insert.await(SQL.create.player.vehicle.role, { playerId, rowId, roleId, })
  if result then return true end
  return false
end

local function getPlayerVehicleRole(playerSrc, identifier)
  local playerId = getPlayerIDFromSource(playerSrc)
  if type(playerId) ~= "number" then return end
  if type(identifier) ~= "string" then return end
  local vehicleId = getVehicleIdFromIdentifier(identifier)
  if type(vehicleId) ~= "number" then return end
  local result = MySQL.single.await(SQL.get.player.vehicle.role, { playerId, vehicleId, })
  if type(result) ~= "table" then return end
  return result
end

local function setVehicleState(vehicleNetworkId, state)
  if not STATE[state] then return false end

  local rowId = getVehicleIdFromIdentifier(getVehicleIdentifierFromNetworkId(vehicleNetworkId))
  if not rowId then return false end

  return MySQL.transaction.await({
    [1] = { query = SQL.deactivate.vehicle.states, values = { rowId, }, },
    [2] = { query = SQL.create.vehicle.state, values = { state, rowId, }, },
  })
end

local function getVehicleState(identifier)
  local debug = Debugger("GetVehicleState")
  local rowId = getVehicleIdFromIdentifier(identifier)
  debug({ "rowId", rowId = rowId, })
  if type(rowId) ~= "number" or rowId < 1 then return end
  local result = MySQL.single.await(SQL.get.vehicle.state, { rowId, })
  debug({ result = result, })
  return result
end

local function setVehicleGarage(vehicleRowId, garage)
  return MySQL.update.await(SQL.update.vehicle.garage, { garage, vehicleRowId, })
end

-- Don't just get keys that this player OWNS
-- but get ALL keys they have.
local function getAllKeysByPlayer(playerSrc)
  local debug = Debugger("GetAllKeysByPlayer")

  local Player = QBCore.Functions.GetPlayer(playerSrc)
  local returner = {}
  if type(Player) ~= "table" then
    debug("player is not a table")
    return nil
  end
  local items = Player.PlayerData.items
  for slot, item in pairs(items) do
    local infoJson, parsedItemInfo
    if not slot or not item then
      debug("no slot")
      goto continue
    end
    if type(item) ~= "table" then
      debug("item is not a table...")
      goto continue
    end
    if tostring(item.name) ~= "keys" then goto continue end
    debug({ info = items[slot].info, })

    infoJson = item.info
    if type(infoJson) ~= "string" then
      debug("item info is not a string...")
      goto continue
    end
    parsedItemInfo = Util.String.JSON.Try.Decode(infoJson)
    if type(parsedItemInfo) ~= "table" then
      debug("failed to decode item info...")
      goto continue
    end
    returner[#returner+1] = { slot = slot, item = item, parsedItemInfo = parsedItemInfo, }
    ::continue::
  end
  return Player, returner
end

local function getKeysSlot(playerSrc)
  local debug = Debugger("GetKeysSlot")
  local Player = QBCore.Functions.GetPlayer(playerSrc)
  if type(Player) ~= "table" then
    debug("player is not a table")
    return nil
  end
  local items = Player.PlayerData.items
  for slot, item in pairs(items) do
    local infoJson, parsedItemInfo, owner
    if not slot or not item then
      debug("no slot")
      goto continue
    end

    debug({ info = items[slot].info, })
    if type(item) ~= "table" then
      debug("item is not a table...")
      goto continue
    end
    infoJson = item.info
    if type(infoJson) ~= "string" then
      debug("item info is not a string...")
      goto continue
    end
    parsedItemInfo = Util.String.JSON.Try.Decode(infoJson)
    if type(parsedItemInfo) ~= "table" then
      debug("failed to decode item info...")
      goto continue
    end
    owner = parsedItemInfo.owner
    if not owner then
      debug("found no owner...")
      goto continue
    end
    if owner == Player.PlayerData.citizenid then
      debug("owner is the correct player, found keys")
      return
          Player, slot, item, parsedItemInfo
    end
    ::continue::
  end
  debug("did not find keys")
  return Player
end

local function playerHasKeyForVehicle(playerSrc, identifier)
  local Player, allKeys = getAllKeysByPlayer(playerSrc)
  if type(Player) ~= "table" then
    return false
  end
  if type(allKeys) ~= "table" then return false end

  for _, keysData in ipairs(allKeys) do
    local slot = keysData.slot
    local keysItem = keysData.item
    local parsedItemInfo = keysData.parsedItemInfo
    if not slot or type(parsedItemInfo) ~= "table" or type(keysItem) ~= "table" then
      return false
    end

    local hasKey = parsedItemInfo.vehicles[identifier] ~= nil
    return hasKey, Player, slot, keysItem, parsedItemInfo
  end
end

local function giveVehicleKey(playerSrc, identifier)
  local debug = Debugger("GiveVehicleKey")
  if type(identifier) ~= "string" then return false, "Vehicle does not support keys." end

  local Player, slot, keysItem, parsedItemInfo = getKeysSlot(playerSrc)
  debug("got keysItem reference...")

  debug({ "keysItem", keysItem = keysItem, })
  debug({ "slot", slot = slot, })
  debug({ "parsedItemInfo", parsedItemInfo = parsedItemInfo, })

  if type(Player) ~= "table" then
    debug("Player is not a table...")
    return false, "Could not identify target player."
  end

  if type(keysItem) ~= "table" or not slot or type(parsedItemInfo) ~= "table" then
    debug("player does not have a keys item, creating one")
    local encoded = json.encode({ vehicles = { [identifier] = Util.Time.Epoch(), }, owner = Player.PlayerData.citizenid, })
    debug({ "encoded", encoded = encoded, })
    Player.Functions.AddItem(Config.KeysItem, 1, nil, encoded)
    return true, "Gave a vehicle key to " .. Player.PlayerData.citizenid .. "!"
  end

  if parsedItemInfo.vehicles[identifier] then
    debug("player already has a key to that vehicle")
    return false, "Player already has a key to that vehicle."
  end

  parsedItemInfo.vehicles[identifier] = Util.Time.Epoch()
  debug({ "set vehicle...", parsedItemInfo = parsedItemInfo, })

  -- It seems like we're unable to reassign item data inline?
  Player.Functions.RemoveItem(Config.KeysItem, 1, slot)
  Player.Functions.AddItem(Config.KeysItem, 1, slot, json.encode(parsedItemInfo))

  Player.PlayerData.items[slot].info = json.encode(parsedItemInfo)

  return true, "Gave a vehicle key to " .. Player.PlayerData.citizenid .. "!"
end

local function toggleVehicleLock(vehicle, toState)
  local debug = Debugger("ToggleVehicleLock")
  debug({ vehicle = vehicle, toState = toState, })
  if toState ~= nil then
    SetVehicleDoorsLocked(vehicle, toState)
    return toState < 2 and false or true
  end

  local currentState = GetVehicleDoorStatus(vehicle)
  debug({ currentStatus = currentState, })

  toState = 0
  if currentState < 2 then toState = 2 end
  debug({ toState = toState, })
  SetVehicleDoorsLocked(vehicle, toState)
  return toState < 2 and false or true
end

local function setVehicleIdentifier(vehicleNetworkId, identifier, job)
  local debug = Debugger("SetVehicleIdentifier")
  debug({ "SetVehicleIdentifier", vehicleNetworkId = vehicleNetworkId, identifier = identifier, })
  local vehicleEntity = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not vehicleEntity or not DoesEntityExist(vehicleEntity) then return debug("no vehicle entity") end

  if not identifier or identifier == "" then
    identifier = generateUUID()
  end
  debug({ "identifier", identifier = identifier, })

  local rowId = getVehicleIdFromIdentifier(identifier)
  debug({ "rowId", rowId = rowId, })

  -- Release a lock if there is one
  if SEMAPHORES[vehicleNetworkId] then SEMAPHORES[vehicleNetworkId] = nil end

  return identifier, (type(rowId) == "number" and rowId > 0) and true or false
end

local function handleSetVehicleIdentifier(src, args)
  local debug = Debugger("HandleSetVehicleIdentifier")
  debug("HandleSetVehicleIdentifier")

  if not args or type(args) ~= "table" then return end
  local vehicleNetworkId = args.vehicleNetworkId
  local suppliedIdentifier = args.identifier
  local grantedRole = args.role
  local job = args.job
  local shouldGrantKey = args.key
  local player = (args.player ~= nil) and args.player or src

  debug({ "args", args = args, })

  -- If we didn't get a lock on this vehicle, then someone else may be provisioning it
  -- so we should just give a key
  if SEMAPHORES[vehicleNetworkId] ~= nil and SEMAPHORES[vehicleNetworkId] ~= player then
    debug("player does not have lock")
    return
  end

  local vehicleEntity = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not DoesEntityExist(vehicleEntity) then return debug("vehicle does not exist") end
  local vehicleData = Entity(vehicleEntity).state.data
  local existingIdentifier = (vehicleData or {}).identifier
  if existingIdentifier then
    local rowId = getVehicleIdFromIdentifier(existingIdentifier)
    return existingIdentifier, (type(rowId) == "number" and rowId > 0) and true or false
  end

  local identifier, isPersistentVehicle = setVehicleIdentifier(vehicleNetworkId, suppliedIdentifier, job)
  debug({
    isPersistentVehicle = isPersistentVehicle,
    identifier = identifier,
    player = player,
    vehicleNetworkId = vehicleNetworkId,
  })
  if shouldGrantKey then
    giveVehicleKey(player, identifier)
  end
  if isPersistentVehicle then
    debug("is persistent vehicle")
    setVehicleState(vehicleNetworkId, STATE.out)
  end
  if not isPersistentVehicle or not grantedRole or not ROLE[grantedRole] then
    debug("not granting player vehicle role")
  else
    grantPlayerVehicleRole(player, vehicleNetworkId, grantedRole)
  end
  return identifier, isPersistentVehicle
end

RegisterNetEvent("giga-keys:server:AddKey")
AddEventHandler("giga-keys:server:AddKey", function(identifier)
  local debug = Debugger("event:server:AddKey")
  debug({ identifier = identifier, })
  local src = source
  giveVehicleKey(src, identifier)
end)

RegisterNetEvent("giga-keys:server:StoreVehicle")
AddEventHandler("giga-keys:server:StoreVehicle", function(vehicleNetworkId, state, option)
  local debug = Debugger("event:server:StoreVehicle")
  local identifier = getVehicleIdentifierFromNetworkId(vehicleNetworkId)
  debug({ "identifier", identifier = identifier, })
  if not identifier then return debug("not identifier") end

  local s = state ~= nil and STATE[state] or STATE["?"]
  debug({ "passed-in state", state = s, })
  local id = getVehicleIdFromIdentifier(identifier)
  debug({ "id", id = id, })
  if id then
    debug("setting vehicle state...")
    setVehicleState(vehicleNetworkId, s)
    if option and state == "garage" then
      debug("state == garage...")
      setVehicleGarage(id, option)
    end
  end
  debug("emitting VehicleStored client event...")
  TriggerClientEvent("giga-keys:client:VehicleStored", -1, identifier)
end)

RegisterNetEvent("giga-keys:server:GiveVehicleKey")
AddEventHandler("giga-keys:server:GiveVehicleKey", function(identifier, targetPlayer)
  local debug = Debugger("event:server:GiveVehicleKey")
  local src = source
  if not src or type(src) ~= "number" then return Debug("src is junk") end
  if type(targetPlayer) ~= "number" then
    debug("targetPlayer is junk")
    return TriggerClientEvent("QBCore:Notify", src,
      "Could not identify the recipient.", "error")
  end
  local TargetPlayer = QBCore.Functions.GetPlayer(targetPlayer)
  if type(TargetPlayer) ~= "table" then
    debug("TargetPlayer is junk")
    return TriggerClientEvent("QBCore:Notify", src,
      "Could not identify the recipient.", "error")
  end

  local Player = QBCore.Functions.GetPlayer(src)
  if type(Player) ~= "table" then
    debug("Player is junk")
    return TriggerClientEvent("QBCore:Notify", src,
      "Could not give keys.", "error")
  end
  local hasKeys = playerHasKeyForVehicle(src, identifier)
  local role = getPlayerVehicleRole(src, identifier)
  debug({ hasKeys = hasKeys, role = role, })
  if not hasKeys or not role or (role.role_access ~= "own" and role.role_access ~= "duplicate") then
    debug("hasKeys or role is junk")
    return TriggerClientEvent("QBCore:Notify", src,
      "You cannot give keys to this vehicle.", "error")
  end
  debug("giving keys...")
  giveVehicleKey(targetPlayer, identifier)
  debug("returning...")
  return TriggerClientEvent("QBCore:Notify", src,
    "Keys given.", "success")
end)

RegisterNetEvent("giga-keys:server:RemoveKeys", function(identifiers)
  local src = source
  local Player, keys = getAllKeysByPlayer(src)
  if type(Player) ~= "table" then return end
  if type(keys) ~= "table" or #keys < 1 then return end
  for _, keyData in ipairs(keys) do
    local slot = keyData.slot
    local keysItem = keyData.item
    local parsedItemInfo = keyData.parsedItemInfo
    if type(slot) ~= "number" or type(keysItem) ~= "table" or type(parsedItemInfo) ~= "table" then goto continue end
    local vehicles = parsedItemInfo.vehicles
    local owner = parsedItemInfo.owner
    if type(vehicles) ~= "table" or type(owner) ~= "string" then goto continue end
    for _, identifier in ipairs(identifiers) do
      if type(identifier) ~= "string" then goto continue end
      if vehicles[identifier] then
        vehicles[identifier] = nil
        Player.Functions.RemoveItem(Config.KeysItem, 1, slot)
        local hasAnyKeys = false
        for _, _ in pairs(vehicles) do
          hasAnyKeys = true
          break
        end
        if hasAnyKeys then Player.Functions.AddItem(Config.KeysItem, 1, slot, json.encode(parsedItemInfo)) end
      end
    end
    ::continue::
  end
end)

RegisterNetEvent("giga-keys:server:RemoveEmptyKeys", function()
  local src = source
  local Player, keys = getAllKeysByPlayer(src)
  if type(Player) ~= "table" then return end
  if type(keys) ~= "table" or #keys < 1 then return end
  for _, keyData in ipairs(keys) do
    local slot = keyData.slot
    local keysItem = keyData.item
    local parsedItemInfo = keyData.parsedItemInfo
    if type(slot) ~= "number" then goto continue end
    if type(keysItem) ~= "table" or type(parsedItemInfo) ~= "table" then
      Player.Functions.RemoveItem(Config.KeysItem, 1, slot)
      goto continue
    end

    local vehicles = parsedItemInfo.vehicles
    local owner = parsedItemInfo.owner
    if type(vehicles) ~= "table" or type(owner) ~= "string" then
      Player.Functions.RemoveItem(Config.KeysItem, 1, slot)
      goto continue
    end

    local hasAnyKeys = false
    for _, _ in pairs(vehicles) do
      hasAnyKeys = true
      break
    end
    if not hasAnyKeys then
      Player.Functions.RemoveItem(Config.KeysItem, 1, slot)
    end
    ::continue::
  end
end)

RegisterNetEvent("giga-keys:server:RequestJobVehicles")
AddEventHandler("giga-keys:server:RequestJobVehicles", function()
  local debug = Debugger("event:server:RequestJobVehicles")
  debug("requested job vehicles...")
  local src = source
  local Player = QBCore.Functions.GetPlayer(src)
  if type(Player) ~= "table" or type(Player.PlayerData) ~= "table" then return debug("playerdata bad") end
  local job = Player.PlayerData.job
  debug({ "job", job = job, })
  if type(job) ~= "table" or type(job.name) ~= "string" then return debug("job bad") end
  if not job.onduty then return debug("not on duty") end

  local allVehicles = GetAllVehicles()
  debug("found " .. tostring(type(allVehicles) == "table" and #allVehicles or "nil") .. " vehicles")
  if type(allVehicles) == "number" then return end
  for _, vehicleEntity in ipairs(allVehicles) do
    local vehicleData = Entity(vehicleEntity).state.data
    local vehicleIdentifier = (vehicleData or {}).identifier
    if type(vehicleIdentifier) ~= "string" then
      debug("no vehicleIdentifier")
      goto continue
    end
    local vehicleJob = (vehicleData or {}).job
    if type(vehicleJob) ~= "string" then
      debug("no vehicleJob")
      goto continue
    end
    if vehicleJob ~= job.name then
      debug("vehicleJob ~= job.name")
      goto continue
    end
    giveVehicleKey(src, vehicleIdentifier)
    ::continue::
  end
end)

QBCore.Functions.CreateCallback("giga-keys:server:GetPlayerVehicleRole", function(source, cb, identifier)
  local src = source
  local role = getPlayerVehicleRole(src, identifier)
  if type(role) ~= "table" then return cb(nil) end
  return cb({
    slug = role.role_slug,
    access = role.role_access,
  })
end)

QBCore.Functions.CreateCallback("giga-keys:server:GetVehicleState", function(_, cb, identifier)
  if type(identifier) ~= "string" then return cb(nil) end
  local state = getVehicleState(identifier)
  if type(state) ~= "table" then return cb(nil) end
  local returner = {
    timestamp = (type(state.created) == "number" and state.created / 1000) or Util.Time.Epoch(),
    state = state.state,
  }
  return cb(returner)
end)

QBCore.Functions.CreateCallback("giga-keys:server:GetVehicleStates", function(_, cb, identifiers)
  local debug = Debugger("callback:GetVehicleStates")
  debug({ "identifiers", identifiers = identifiers, })
  if type(identifiers) ~= "table" or #identifiers < 1 then return cb({}) end
  local returner = {}
  local allVehicles = GetAllVehicles()
  debug({ "allVehicles", allVehicles = #allVehicles, })
  for _, identifier in ipairs(identifiers) do
    local state = getVehicleState(identifier)
    if type(allVehicles) == "table" then
      for _, entityId in ipairs(allVehicles) do
        if DoesEntityExist(entityId) then
          debug("entity exists")
          local vehicleData = Entity(entityId).state.data
          local vehicleIdentifier = (vehicleData or {}).identifier
          debug({ "vehicleIdentifier", vehicleIdentifier = vehicleIdentifier, })
          if type(vehicleIdentifier) == "string" and vehicleIdentifier == identifier then
            debug("found vehicle")
            local insertion = {
              job = vehicleData.job,
              temporary = vehicleData.temporary,
            }
            if type(state) == "table" then
              local now = Util.Time.Epoch()
              insertion.state = {
                timestamp = (type(state.created) == "number" and state.created / 1000) or now,
                slug = state.state,
              }
            end
            local hasAnyKey = false
            for _, _ in pairs(insertion) do
              hasAnyKey = true
              break
            end
            if hasAnyKey then returner[identifier] = insertion end

            debug({ identifier, returner = returner[identifier], })

            break
          end
        end
      end
    end
  end
  debug({ "returner", returner = returner, })
  return cb(returner)
end)

QBCore.Functions.CreateCallback("giga-keys:server:PlayerHasKeyForVehicle", function(source, cb, identifier)
  local src = source
  local hasKeys = playerHasKeyForVehicle(src, identifier)
  local role = getPlayerVehicleRole(src, identifier)
  local r = type(role) == "table" and {
    slug = role.role_slug,
    access = role.role_access,
  } or nil
  return cb(hasKeys, r)
end)

QBCore.Functions.CreateCallback("giga-keys:server:ToggleVehicleLock", function(source, cb, vehicleNetworkId, toState)
  local debug = Debugger("callback:ToggleVehicleLock")
  local src = source
  if not vehicleNetworkId then
    debug("could not figure out vehicleNetworkId")
    return cb(nil)
  end
  local identifier = getVehicleIdentifierFromNetworkId(vehicleNetworkId)
  if type(identifier) ~= "string" then
    debug("could not figure out identifier")
    return cb(nil)
  end
  if not playerHasKeyForVehicle(src, identifier) then
    debug("player does not have key for this vehicle")
    return cb(nil)
  end
  local vehicle = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not vehicle or not DoesEntityExist(vehicle) then
    debug("could not figure out vehicle from networkId")
    return cb(nil)
  end
  local locked = toggleVehicleLock(vehicle, toState)
  debug({ locked = locked, })
  TriggerClientEvent("giga-keys:client:ChangeDoorStatus", -1, vehicleNetworkId, toState)
  return cb(locked)
end)

QBCore.Functions.CreateCallback("giga-keys:server:GetVehicleSemaphore", function(source, cb, vehicleNetworkId)
  local debug = Debugger("callback:GetVehicleSemaphore")
  local src = source
  debug({ "getting semaphore", source = source, vehicleNetworkId = vehicleNetworkId, })
  if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then
    debug("bad vehicleNetworkId")
    return cb(false)
  end

  -- Check if there is a lock on this already and it isn't ours
  if SEMAPHORES[vehicleNetworkId] ~= nil and SEMAPHORES[vehicleNetworkId] ~= src then return cb(false) end
  -- Claim the lock
  SEMAPHORES[vehicleNetworkId] = src
  -- Double-check we have the lock
  if SEMAPHORES[vehicleNetworkId] ~= src then return cb(false) end
  -- Finally confirm we have the lock
  return cb(true)
end)

QBCore.Functions.CreateCallback("giga-keys:server:SetVehicleIdentifier", function(source, cb, args)
  local debug = Debugger("callback:SetVehicleIdentifier")
  local src = source
  local vehicleNetworkId = args.vehicleNetworkId
  debug({ src = src, vehicleNetworkId = vehicleNetworkId, args = args, })
  if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then
    debug("bad vehicleNetworkId")
    return cb(nil)
  end
  if SEMAPHORES[vehicleNetworkId] ~= src then
    debug({ semaphore = SEMAPHORES[vehicleNetworkId], })
    debug("player does not have a lock")
    return cb(nil)
  end
  local entity = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not entity or not DoesEntityExist(entity) then
    debug("no entity")
    return cb(nil)
  end
  local vehicleData = Entity(entity).state.data
  local existingIdentifier = (vehicleData or {}).identifier
  if type(existingIdentifier) == "string" then
    debug("already has identifier")
    local rowId = getVehicleIdFromIdentifier(existingIdentifier)
    return cb(existingIdentifier, (type(rowId) == "number" and rowId > 0) and rowId or false)
  end
  local identifier, isPersistent = handleSetVehicleIdentifier(src, args)
  debug({ identifier = identifier, isPersistent = isPersistent, })
  if args.job then
    TriggerClientEvent("giga-keys:client:JobVehicleProvisioned", -1, identifier, args.job)
  end
  return cb(identifier, isPersistent)
end)

QBCore.Functions.CreateCallback("giga-keys:server:GetMinimalPlayerData", function(source, cb, targetPlayer)
  local debug = Debugger("callback:GetMinimalPlayerData")
  local src = source
  debug({ targetPlayer = targetPlayer, })
  if not targetPlayer then return cb(nil) end
  local result = (QBCore.Functions.GetPlayer(targetPlayer) or {}).PlayerData
  debug({ result = result, })
  if type(result) ~= "table" then return cb(nil) end
  return cb({
    name = result.name,
    citizenid = result.citizenid,
  })
end)

if Config.AdminCommands.Enabled then
  QBCore.Commands.Add("getvehicleinfo", "", {}, false, function(source)
    local src = source
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)
    if not DoesEntityExist(vehicle) then return end
    local vehicleData = Entity(vehicle).state.data
    local networkId = NetworkGetNetworkIdFromEntity(vehicle) or nil
    QBCore.Debug({ vehicleData = vehicleData, networkId = networkId ~= nil and networkId or "nil", })
  end, "admin")
  QBCore.Commands.Add("getkeyinfo", "", {}, false, function(source)
    local src = source
    local _, _, _, parsedItemInfo = getKeysSlot(src)
    QBCore.Debug({ keyInfo = parsedItemInfo, })
  end, "admin")
end
