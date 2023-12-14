local Util = exports["giga-util"]:GetUtils()
local QBCore = exports["qb-core"]:GetCoreObject()
RegisterNetEvent("QBCore:Client:UpdateObject", function()
  QBCore = exports["qb-core"]:GetCoreObject()
end)

local animDict = "anim@mp_player_intmenu@key_fob@"
local anim = "fob_click_fp"

local MISSION_VEHICLES = {}
local PlayerData = {}

function Debugger(identifier)
  return Util.Debugger(GetCurrentResourceName() .. ":client:" .. identifier)
end

local function getVehiclesInArea(coords, maxDistance)
  return Util.Entity.Enumerate.Within.Distance(QBCore.Functions.GetVehicles(), false, coords, maxDistance)
end

local function entityIsAVehicle(vehicle)
  if type(vehicle) ~= "number" or vehicle < 1 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return false end
  return true
end

local function isEntityNetworkPairValid(entity, networkId)
  -- Check the entity to begin with
  if not entityIsAVehicle(entity) then return false end
  -- Check if it's networked
  if not NetworkGetEntityIsNetworked(entity) then return false end
  -- Check if the network ID is valid
  if not NetworkDoesEntityExistWithNetworkId(networkId) then return false end
  -- Reverse check if the network ID matches the entity, because network IDs are reused
  local entityNetworkId = NetworkGetNetworkIdFromEntity(entity)
  if type(entityNetworkId) ~= "number" or entityNetworkId < 1 then return false end
  if entityNetworkId ~= networkId then return false end
  return true
end

local function doesMissionVehicleExist(vehicle)
  if not entityIsAVehicle(vehicle) then return false end
  for _, data in ipairs(MISSION_VEHICLES) do
    if data.vehicle == vehicle then
      if not isEntityNetworkPairValid(vehicle, data.networkId) then
        return false
      end
      return true
    end
  end
  return false
end

-- Take network ownership of a vehicle and stick it in our MISSION_VEHICLES table.
local function ensureMissionVehicle(vehicle, networkId)
  -- local debug = Debugger("ensureMissionVehicle")
  local debug = function() end
  debug({ "ensureMissionVehicle", vehicle = vehicle, networkId = networkId, })
  if not entityIsAVehicle(vehicle) then
    debug("vehicle not number, does not exist, or is not a vehicle")
    return
  end
  if not isEntityNetworkPairValid(vehicle, networkId) then
    return debug("network pair is invalid")
  end
  if doesMissionVehicleExist(vehicle) then
    debug("mission vehicle already exists")
    return
  end
  SetEntityAsMissionEntity(vehicle, true, true)
  -- SetNetworkIdCanMigrate(networkId, false)
  SetNetworkIdAlwaysExistsForPlayer(networkId, PlayerId(), true)
  debug("vehicle " .. tostring(vehicle))
  MISSION_VEHICLES[#MISSION_VEHICLES+1] = { vehicle = vehicle, networkId = networkId, lastSeen = Util.Time.Epoch(), }
end

local function _getVehicleNetworkId(vehicle)
  local debug = Debugger("GetVehicleNetworkId")
  debug({ vehicle = vehicle, })
  if not entityIsAVehicle(vehicle) then return debug("entity is not a vehicle") end

  -- Make sure that we have a valid networkID / entity handle pair
  local networkId
  if not NetworkGetEntityIsNetworked(vehicle) then
    local start = Util.Time.Epoch()
    NetworkRegisterEntityAsNetworked(vehicle)
    while type(networkId) ~= "number" or networkId < 1 and Util.Time.Epoch() - start < 2000 do
      Citizen.Wait(10)
      _, networkId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
    end
  else
    _, networkId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
  end
  if type(networkId) ~= "number" or networkId < 1 then return debug("network id is invalid") end
  if not isEntityNetworkPairValid(vehicle, networkId) then return debug("network pair is invalid") end

  ensureMissionVehicle(vehicle, networkId)
  return networkId
end

GetVehicleNetworkId = Util.Function.Memoize(_getVehicleNetworkId, 5000) -- TTL 5s so we don't recalculate this all the time

local function isVehicleABike(vehicle)
  if not entityIsAVehicle(vehicle) then return false end
  local vehicleClass = GetVehicleClass(vehicle)
  local vehicleModel = GetEntityModel(vehicle)
  return vehicleClass == 8 or vehicleClass == 13 or vehicleModel == `BLAZER`
end

local function IsVehicleExempt(vehicle)
  if not entityIsAVehicle(vehicle) then return false end
  local vehicleModel = GetEntityModel(vehicle)
  for _, hash in ipairs(Config.Exempt.Vehicles) do
    if vehicleModel == hash then return true end
  end
  return false
end

local function getVehicleIdentifier(vehicle)
  local debug = Debugger("GetVehicleIdentifier")
  debug({ "vehicle", vehicle = vehicle, })
  if not entityIsAVehicle(vehicle) then return debug("invalid vehicle") end
  local vehicleData = Entity(vehicle).state.data
  debug({ "vehicleData", vehicleData = vehicleData, })
  local existingIdentifier = (vehicleData or {}).identifier
  debug({ "existingIdentifier", existingIdentifier = existingIdentifier, })
  if type(existingIdentifier) ~= "string" then
    debug("identifier is bad")
    return nil
  end
  return existingIdentifier
end

local function setVehicleIdentifier(vehicle, args)
  local debug = Debugger("SetVehicleIdentifier")
  local maxWait = 2000
  args = type(args) == "table" and args or {}
  debug({ "params", player = PlayerId(), args = args, vehicle = vehicle, })
  if not entityIsAVehicle(vehicle) then return debug("vehicle invalid") end
  local identifier = getVehicleIdentifier(vehicle)
  if type(identifier) == "string" then
    debug("has an identifier already " .. tostring(identifier))
    if args.key then
      debug("adding key...")
      TriggerServerEvent("giga-keys:server:AddKey", identifier)
    end
    return identifier
  end

  local vehicleNetworkId = GetVehicleNetworkId(vehicle)
  if not isEntityNetworkPairValid(vehicle, vehicleNetworkId) then return debug("network pair is invalid") end

  debug({ "vehicleNetworkId", vehicleNetworkId = vehicleNetworkId, })
  if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then return debug("vehicle is not networked") end

  local lock = QBCore.Functions.AwaitCallback("giga-keys:server:GetVehicleSemaphore", vehicleNetworkId)
  debug({ "lock", lock = lock, })

  -- If we don't have a lock, try waiting for the vehicle to be provisioned
  if not lock then
    debug("could not get lock")
    local start = Util.Time.Epoch()
    while type(identifier) ~= "string" and Util.Time.Epoch() - start < maxWait do
      Citizen.Wait(50)
      local vehicleData = Entity(vehicle).state.data
      identifier = (vehicleData or {}).identifier
      if type(identifier) == "string" then break end
    end

    if identifier then
      debug("eventually got identifier")
      if args.key then
        debug("adding key...")
        TriggerServerEvent("giga-keys:server:AddKey", identifier)
      end
      return identifier
    else
      debug("never got an identifier")
      return nil
    end
  end

  ensureMissionVehicle(vehicle, vehicleNetworkId)

  local gigaParams = { vehicleNetworkId = vehicleNetworkId, key = false, }
  for k, v in pairs(args) do
    gigaParams[k] = v
  end
  debug({ gigaParams = gigaParams, })
  -- Get the identifier and whether the vehicle is persistent or temporary
  local identifier, isPersistent = QBCore.Functions.AwaitCallback("giga-keys:server:SetVehicleIdentifier", gigaParams)
  debug({ identifier = identifier, isPersistent = isPersistent, })
  Entity(vehicle).state:set("data", { identifier = identifier, temporary = not isPersistent, job = args.job, }, true)

  return identifier, isPersistent
end

local function addKey(vehicle)
  local debug = Debugger("AddKey")
  if not entityIsAVehicle(vehicle) then return debug("no vehicle") end
  local identifier = getVehicleIdentifier(vehicle)
  debug({ "identifier", identifier = identifier, })
  if type(identifier) ~= "string" then
    debug("identifier is bad")
    return
  end

  local vehicleNetworkId = GetVehicleNetworkId(vehicle)
  if not isEntityNetworkPairValid(vehicle, vehicleNetworkId) then
    debug("network pair is invalid")
    return
  end
  ensureMissionVehicle(vehicle, vehicleNetworkId)

  debug("granting key")
  -- Finally give the actual key
  TriggerServerEvent("giga-keys:server:AddKey", identifier)
  return identifier
end

local function _hasKey(vehicle)
  local debug = Debugger("HasKey")
  if not entityIsAVehicle(vehicle) then
    debug("entity is not a vehicle")
    return false
  end
  local existingIdentifier = getVehicleIdentifier(vehicle)
  debug({ "existingIdentifier", existingIdentifier = existingIdentifier, })
  if type(existingIdentifier) ~= "string" then return false end
  local PlayerData = QBCore.Functions.GetPlayerData()
  debug("got playerdata")
  local items = PlayerData.items
  debug({ "items", items = items, })
  for _, item in pairs(items) do
    debug("slot " .. tostring(_))
    if type(item) == "table" and item.name == "keys" then
      local decoded = Util.String.JSON.Try.Decode(item.info)
      debug({ decoded = decoded, })
      if type(decoded) == "table" and type(decoded.vehicles) == "table" then
        debug("decoded is a table and decoded.vehicles is a table...")
        for identifier, timestamp in pairs(decoded.vehicles) do
          debug("iterating... " .. tostring(identifier))
          if identifier == existingIdentifier then
            debug("identifier == existingIdentifier...")
            local vehicleData = Entity(vehicle).state.data
            if type(vehicleData.job) == "string" then
              debug("is job vehicle")
              return true
            end
            if type(vehicleData.temporary) == "boolean" then
              debug("is temporary vehicle")
              return true
            end
            local role = QBCore.Functions.AwaitCallback("giga-keys:server:GetPlayerVehicleRole", identifier)
            debug({ "role?", role = role, })
            if role.access == "own" or role.access == "duplicate" then
              debug("has owner role")
              return true, role
            end
            local state = QBCore.Functions.AwaitCallback("giga-keys:server:GetVehicleState", identifier)
            debug({ "state?", state = state, })
            if type(state) ~= "table" or type(state.timestamp) ~= "number" then
              debug("state is poop")
              return true, role
            end
            if state.timestamp < timestamp then
              debug("state timestamp is less than ours")
              return true, role
            end
            debug("fallback")
            return false, role
          end
        end
      end
    end
  end
  return false
end
local HasKey = Util.Function.Memoize(_hasKey, 5000) -- TTL 5s so we don't constantly make calls

local function synchronizeKeys()
  local debug = Debugger("SynchronizeKeys")
  PlayerData = QBCore.Functions.GetPlayerData()
  if type(PlayerData) ~= "table" then
    return debug("PlayerData is not a table")
  end
  local items = PlayerData.items
  if type(items) ~= "table" or #items < 1 then return debug("items is invalid") end
  local keys = {}
  local identifiers = {}
  local keysItemsToRemove = {}
  for slot, item in pairs(items) do
    if type(item) == "table" and item.name == "keys" then
      local decoded = Util.String.JSON.Try.Decode(item.info)
      debug({ decoded = decoded, })
      if type(decoded) == "table" and type(decoded.vehicles) == "table" then
        for identifier, timestamp in pairs(decoded.vehicles) do
          keys[identifier] = timestamp
          identifiers[#identifiers+1] = identifier
        end
        local hasAnyKeys = false
        for _, _ in pairs(decoded.vehicles) do
          hasAnyKeys = true
          break
        end
        if not hasAnyKeys then
          keysItemsToRemove[#keysItemsToRemove+1] = slot
        end
      end
    end
  end
  debug({ keys = keys, })
  local states = QBCore.Functions.AwaitCallback("giga-keys:server:GetVehicleStates", identifiers)
  local keysToRemove = {}
  for identifier, timestamp in pairs(keys) do
    local state = (states[identifier] or {}).state
    local job = (states[identifier] or {}).job
    local temporary = (states[identifier] or {}).temporary
    debug({ "statesData", identifier = identifier, state = state, job = job, temporary = temporary, })
    if not state or type(state) ~= "table" or type(state.timestamp) ~= "number" then
      if job then
        local playerJob = (PlayerData or {}).job or {}
        if not playerJob.name or job ~= playerJob.name or not playerJob.onduty then
          keysToRemove[#keysToRemove+1] = identifier
        end
        goto continue
      end
      if temporary then goto continue end
      keysToRemove[#keysToRemove+1] = identifier
      goto continue
    end
    if state.state == STATE.out and state.timestamp < timestamp then
      debug("it's out and state timestamp is less than ours, so keep the key")
      goto continue
    end
    keysToRemove[#keysToRemove+1] = identifier
    ::continue::
  end
  debug({ "toRemove", keysToRemove = keysToRemove, })
  if #keysToRemove > 0 then
    TriggerServerEvent("giga-keys:server:RemoveKeys", keysToRemove)
  end
  if #keysItemsToRemove > 0 then
    TriggerServerEvent("giga-keys:server:RemoveEmptyKeys")
  end
end

local function _toggleVehicleLock()
  local debug = Debugger("ToggleVehicleLock")
  local ped = PlayerPedId()
  -- Handle the case where we're in a vehicle
  if IsPedInAnyVehicle(ped, false) then
    local vehicle = GetVehiclePedIsIn(ped, false)
    if isVehicleABike(vehicle) then
      return QBCore.Functions.Notify(
        "Bikes cannot be locked", "error")
    end
    local networkId = GetVehicleNetworkId(vehicle)
    if type(networkId) ~= "number" or networkId < 1 then
      return QBCore.Functions.Notify(
        "You do not have keys to this vehicle", "error")
    end
    if IsVehicleSeatFree(vehicle, -1) or GetPedInVehicleSeat(vehicle, -1) ~= ped then
      return QBCore.Functions.Notify("You are not in the driver's seat", "error")
    end
    local lock = GetVehicleDoorLockStatus(vehicle)
    local toState = lock < 2 and 2 or 0
    QBCore.Functions.AwaitCallback("giga-keys:server:ToggleVehicleLock", networkId, toState)
    return QBCore.Functions.Notify("Vehicle " .. ((toState == 2 and "locked.") or "unlocked."), "success")
  end

  debug("not in vehicle")
  -- Now start looking around
  local coords = GetEntityCoords(GetPlayerPed(-1))
  local hasAlreadyLocked = false
  local vehicles = getVehiclesInArea(coords, Config.SearchAreaRadius)
  if #vehicles == 0 then
    debug("cars == 0")
    return QBCore.Functions.Notify("No vehicles are close enough", "error")
  end

  -- Sorting cars by distance
  local sortedVehicles = {}
  for _, vehicle in ipairs(vehicles) do
    local networkId, vehicleCoords, distance
    if not entityIsAVehicle(vehicle) then
      debug("entity is not a vehicle")
      goto continue
    end

    networkId = GetVehicleNetworkId(vehicle)
    debug({ "networkId", networkId = networkId, })
    if type(networkId) ~= "number" or networkId < 1 then goto continue end

    vehicleCoords = GetEntityCoords(vehicle)
    distance = #(vehicleCoords - coords)
    debug({ "distance", distance = distance, })
    -- distance = Vdist(coords.x, coords.y, coords.z, carCoords.x, carCoords.y, carCoords.z)
    if isVehicleABike(vehicle) then
      debug("is a bike")
      goto continue
    end
    table.insert(sortedVehicles, { vehicle = vehicle, networkId = networkId, distance = distance, })
    ::continue::
  end
  table.sort(sortedVehicles, function(a, b) return a.distance < b.distance end)

  debug({ "sortedVehicles", sortedVehicles = sortedVehicles, })

  for _, vehicleData in ipairs(sortedVehicles) do
    debug({ "vehicleData", vehicleData = vehicleData, })
    local vehicle, hasKey, vehicleNetworkId, lock, toState
    if hasAlreadyLocked then
      debug("hasAlreadyLocked")
      goto continue
    end
    vehicle = (vehicleData or {}).vehicle
    debug("about to check HasKey...")
    hasKey = HasKey(vehicle)
    debug("do we have a key?")
    debug({ hasKey = hasKey, })
    vehicleNetworkId = (vehicleData or {}).networkId
    debug({ "networkId?", vehicleNetworkId = vehicleNetworkId, })
    if not isEntityNetworkPairValid(vehicle, vehicleNetworkId) then
      debug("vehicleNetworkId is invalid")
      goto continue
    end

    lock = GetVehicleDoorLockStatus(vehicle)
    toState = lock < 2 and 2 or 0
    if not hasKey then goto continue end
    QBCore.Functions.AwaitCallback("giga-keys:server:ToggleVehicleLock", vehicleNetworkId, toState)
    QBCore.Functions.Notify("Vehicle " .. ((toState == 2 and "locked.") or "unlocked."), "success")
    QBCore.Functions.RequestAnimDict(animDict)
    TaskPlayAnim(PlayerPedId(), animDict, anim, 8.0, 8.0, -1, 48, 1, false, false, false)
    hasAlreadyLocked = true
    break
    ::continue::
  end
  if not hasAlreadyLocked then return QBCore.Functions.Notify("No vehicles close enough", "error") end
end
local ToggleVehicleLock = Util.Function.Throttle(_toggleVehicleLock, 1000)

RegisterNetEvent("giga-keys:client:ChangeDoorStatus", function(vehicleNetworkId, toState)
  if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then return end
  if not NetworkDoesEntityExistWithNetworkId(vehicleNetworkId) then return end
  local vehicle = NetworkGetEntityFromNetworkId(vehicleNetworkId)
  if not isEntityNetworkPairValid(vehicle, vehicleNetworkId) then return end
  if toState == 2 then
    -- TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 5, "lock", 0.05)
    Citizen.Wait(100)
    SetVehicleLights(vehicle, 2)
    Citizen.Wait(200)
    SetVehicleLights(vehicle, 1)
    Citizen.Wait(200)
    SetVehicleLights(vehicle, 2)
    Citizen.Wait(200)
    SetVehicleLights(vehicle, 1)
    Citizen.Wait(200)
    SetVehicleLights(vehicle, 2)
    Citizen.Wait(200)
    SetVehicleLights(vehicle, 0)
  else
    -- TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 5, "lock", 0.05)
    SetVehicleLights(vehicle, 2)
    Citizen.Wait(100)
    SetVehicleLights(vehicle, 1)
    Citizen.Wait(100)
    SetVehicleLights(vehicle, 2)
    Citizen.Wait(100)
    SetVehicleLights(vehicle, 0)
  end
end)

AddEventHandler("giga-keys:client:GiveKeys", function(args)
  local identifier = args.identifier
  local playerId = args.player
  TriggerServerEvent("giga-keys:server:GiveVehicleKey", identifier, playerId)
end)

AddEventHandler("giga-keys:client:OpenGiveKeysMenu", function()
  local ped = PlayerPedId()
  if not ped or not DoesEntityExist(ped) then return end
  if not IsPedInAnyVehicle(ped, false) then return QBCore.Functions.Notify("You are not in a vehicle", "error") end
  local vehicle = GetVehiclePedIsIn(ped, false)
  if not vehicle or not DoesEntityExist(vehicle) then return QBCore.Functions.Notify("You are not in a vehicle", "error") end

  Citizen.CreateThread(function()
    local hasKeys, role = HasKey(vehicle)
    if not hasKeys then
      return QBCore.Functions.Notify("You do not have keys to this vehicle", "error")
    end
    if not role or (role.access ~= "own" and role.access ~= "duplicate") then
      return QBCore.Functions.Notify(
        "You cannot give keys to this vehicle", "error")
    end
    local identifier = getVehicleIdentifier(vehicle)
    if type(identifier) ~= "string" then
      return QBCore.Functions.Notify(
        "You cannot give keys to this vehicle", "error")
    end
    local menuParams = {
      {
        header = "Give Keys",
        icon = "fas fa-key",
        isMenuHeader = true,
      },
    }
    local allPlayers = QBCore.Functions.GetPlayers()
    local nearbyPlayers = Util.Entity.Enumerate.Within.Distance(allPlayers, true, nil, 1000.0)
    if type(nearbyPlayers) ~= "table" or #nearbyPlayers < 1 then
      return QBCore.Functions.Notify("Nobody is close enough to you",
        "error")
    end

    for _, player in ipairs(nearbyPlayers) do
      local otherPlayerData
      if player == 1 then goto continue end
      otherPlayerData = QBCore.Functions.AwaitCallback("giga-keys:server:GetMinimalPlayerData", player)
      if type(otherPlayerData) ~= "table" then
        goto continue
      end
      menuParams[#menuParams+1] = {
        header = otherPlayerData.name .. " [" .. tonumber(player) .. "]",
        txt = "Give keys to this player",
        params = {
          event = "giga-keys:client:GiveKeys",
          args = {
            player = player,
            identifier = identifier,
          },
        },
      }

      ::continue::
    end

    exports["qb-menu"]:openMenu(menuParams)
  end)
end)

RegisterKeyMapping("toggleVehicleLock", "Toggle vehicle lock", "keyboard", "l")
RegisterCommand("toggleVehicleLock", ToggleVehicleLock)

RegisterNetEvent("QBCore:Client:OnJobUpdate")
AddEventHandler("QBCore:Client:OnJobUpdate", function(jobData)
  local debug = Debugger("OnJobUpdate")
  debug({ "jobUpdate", jobData = jobData, })
  if jobData.onduty and not PlayerData.job.onduty then
    debug("came on duty")
    PlayerData = QBCore.Functions.GetPlayerData()
    TriggerServerEvent("giga-keys:server:RequestJobVehicles")
  else
    debug("went off duty")
    PlayerData = QBCore.Functions.GetPlayerData()
    synchronizeKeys()
  end
end)

RegisterNetEvent("QBCore:Client:SetPlayerData")
AddEventHandler("QBCore:Client:SetPlayerData", function(playerData)
  local debug = Debugger("SetPlayerData")
  debug({ "playerData SET", })
  if ((playerData or {}).job or {}).onduty and not PlayerData.job.onduty then
    debug("came on duty")
    PlayerData = QBCore.Functions.GetPlayerData()
    TriggerServerEvent("giga-keys:server:RequestJobVehicles")
  else
    debug("went off duty")
    PlayerData = QBCore.Functions.GetPlayerData()
    synchronizeKeys()
  end
end)

for _, eventName in ipairs({
  "QBCore:Client:OnPlayerLoaded",
  "QBCore:Client:OnGangUpdate",
}) do
  RegisterNetEvent(eventName)
  AddEventHandler(eventName, function(data)
    local debug = Debugger(eventName)
    debug({ eventName, data = data, })
    PlayerData = QBCore.Functions.GetPlayerData()
    synchronizeKeys()
  end)
end

RegisterNetEvent("QBCore:Client:SetDuty")
AddEventHandler("QBCore:Client:SetDuty", function(duty)
  local debug = Debugger("SetDuty")
  debug({ "duty", duty = duty, })
  if duty and not ((PlayerData or {}).job or {}).onduty then
    PlayerData = QBCore.Functions.GetPlayerData()
    TriggerServerEvent("giga-keys:server:RequestJobVehicles")
  else
    PlayerData = QBCore.Functions.GetPlayerData()
    synchronizeKeys()
  end
end)

AddEventHandler("QBCore:Client:OnPlayerUnload", function()
  PlayerData = {}
end)

AddEventHandler("onResourceStart", function()
  synchronizeKeys()
  SetPedConfigFlag(PlayerPedId(), 429, true)
end)

RegisterNetEvent("giga-keys:client:VehicleStored", function(identifier)
  local debug = Debugger("VehicleStored")
  debug({ identifier = identifier, })
  if type(identifier) ~= "string" then return end
  local PlayerData = QBCore.Functions.GetPlayerData()
  local items = PlayerData.items
  for _, item in pairs(items) do
    if type(item) == "table" and item.name == "keys" then
      local decoded = Util.String.JSON.Try.Decode(item.info)
      if type(decoded) == "table" and type(decoded.vehicles) == "table" then
        if decoded.vehicles[identifier] then
          -- No need to remove one at a time, let's just check them all
          TriggerServerEvent("giga-keys:server:RemoveKeys", { identifier, })
        end
      end
    end
  end
end)

RegisterNetEvent("giga-keys:client:JobVehicleProvisioned", function(identifier, job)
  local debug = Debugger("JobVehicleProvisioned")
  debug({ identifier = identifier, job = job, })
  local playerJob = (((PlayerData or {}).job) or {})
  if type(playerJob.name) ~= "string" or playerJob.name ~= job then return end
  if not playerJob.onduty then return end
  TriggerServerEvent("giga-keys:server:AddKey", identifier)
end)

-- If we're in a vehicle that is off, make us unable
-- to start it if we don't have keys.
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(100)
    local hasKeys, vehicleNetworkId, vehicle
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
      goto continue
    end
    vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not vehicle or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
      goto continue
    end
    if IsVehicleExempt(vehicle) then
      goto continue
    end
    if IsVehicleSeatFree(vehicle, -1) then
      goto continue
    end
    if GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
      goto continue
    end
    if GetIsVehicleEngineRunning(vehicle) then
      goto continue
    end
    vehicleNetworkId = GetVehicleNetworkId(vehicle, 100)
    if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then
      goto continue
    end
    hasKeys = HasKey(vehicle)
    if not hasKeys then
      SetPedConfigFlag(PlayerPedId(), 429, true)
      goto continue
    end
    SetPedConfigFlag(PlayerPedId(), 429, false)
    ::continue::
  end
end)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    local ped = PlayerPedId()
    local vehicle, driver
    if not IsPedInAnyVehicle(ped, false) then goto continue end
    vehicle = GetVehiclePedIsIn(ped, false)
    if not entityIsAVehicle(vehicle) then goto continue end
    if IsVehicleSeatFree(vehicle, -1) then goto continue end
    driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= ped then goto continue end
    if GetIsVehicleEngineRunning(vehicle) then goto continue end
    if IsControlJustPressed(0, 32) then
      ExecuteCommand("engine")
    end
    ::continue::
  end
end)

-- Prevent NPC vehicle states from circumventing our break-in mechanics.
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(100)
    local ped = PlayerPedId()

    local isInAVehicle = IsPedInAnyVehicle(ped, false)
    local coords, vehicles
    if isInAVehicle then goto continue end

    coords = GetEntityCoords(ped)
    vehicles = getVehiclesInArea(coords, 50.0)
    if type(vehicles) ~= "table" or #vehicles < 1 then goto continue end
    for _, vehicle in ipairs(vehicles) do
      local doorState, isABike, occupant
      if not vehicle or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then goto continue end
      if IsVehicleExempt(vehicle) then goto continue end

      doorState = GetVehicleDoorLockStatus(vehicle)

      -- Motorcycles and bikes cannot be locked.
      isABike = isVehicleABike(vehicle)
      if isABike then
        if doorState == 0 then goto continue end
        SetVehicleDoorsLocked(vehicle, 0)
        if not GetIsVehicleEngineRunning(vehicle) then
          SetVehicleNeedsToBeHotwired(vehicle, false)
          SetVehicleEngineOn(vehicle, false, true, true)
        end
        goto continue
      end

      if doorState == 2 then goto continue end

      occupant = GetPedInVehicleSeat(vehicle, -1)
      if occupant and DoesEntityExist(occupant) and IsEntityAPed(occupant) then
        -- Don't mess with vehicles occupied by other players.
        if IsPedAPlayer(occupant) then goto continue end

        -- Defaults for doorState 5 or 7 allow it to be hotwired.
        SetVehicleNeedsToBeHotwired(vehicle, false)
        -- And make sure they don't auto-start.
        SetVehicleEngineOn(vehicle, GetIsVehicleEngineRunning(vehicle), true, true)
        -- NPC-occupied vehicles are always locked.
        SetVehicleDoorsLocked(vehicle, 3)
      end

      if doorState < 2 then goto continue end

      -- Prevent this vehicle from being hotwireable.
      if not GetIsVehicleEngineRunning(vehicle) then
        SetVehicleNeedsToBeHotwired(vehicle, false)
        SetVehicleEngineOn(vehicle, false, true, true)
      end

      SetVehicleDoorsLocked(vehicle, 3)
    end

    ::continue::
  end
end)

-- We set vehicles as mission entities when we make them into networked
-- entities. This prevents them from getting garbage-collected and despawning.
-- Doing this for too many entities for too long is cumbersome, so we need
-- to have our own garbage collection logic that calls `SetEntityAsNoLongerNeeded`
-- The gist of it is that if it has been >1500 units away for more than ten
-- minutes, we'll mark it as unneeded.
Citizen.CreateThread(function()
  local debug = Debugger("GarbageCollection")
  while true do
    local sleep = 10000
    if #MISSION_VEHICLES < 1 then
      debug("no mission vehicles, waiting 30s.")
      sleep = 30000
      goto continue
    end
    for i, data in ipairs(MISSION_VEHICLES) do
      local vehicle = data.vehicle
      local networkId = data.networkId
      local lastSeen = data.lastSeen
      local ped, coordsA, coordsB, distance, now, timeDiff
      debug({ vehicle = vehicle, lastSeen = lastSeen, })
      if not entityIsAVehicle(vehicle) then
        debug("not vehicle, does not exist, or is not a vehicle")
        table.remove(MISSION_VEHICLES, i)
        synchronizeKeys()
        goto skip
      end
      if not NetworkGetEntityIsNetworked(vehicle) then
        debug("not networked")
        SetEntityAsNoLongerNeeded(vehicle)
        table.remove(MISSION_VEHICLES, i)
        synchronizeKeys()
        goto skip
      end
      if not isEntityNetworkPairValid(vehicle, networkId) then
        debug("network pair is invalid")
        SetEntityAsNoLongerNeeded(vehicle)
        table.remove(MISSION_VEHICLES, i)
        synchronizeKeys()
        goto skip
      end
      now = Util.Time.Epoch()

      ped = PlayerPedId()
      coordsA = GetEntityCoords(ped)
      coordsB = GetEntityCoords(vehicle)
      distance = #(coordsB - coordsA)
      debug({ now = now, distance = distance, })
      if distance <= 1500.0 then
        debug("lastSeen = " .. tostring(now))
        MISSION_VEHICLES[i].lastSeen = now
        goto skip
      end
      timeDiff = now - lastSeen

      debug("timeDiff " .. tostring(timeDiff))
      if timeDiff > 60000 then
        debug("has been more than ten minutes")
        SetEntityAsNoLongerNeeded(vehicle)
        table.remove(MISSION_VEHICLES, i)
        synchronizeKeys()
      end
      ::skip::
    end
    ::continue::
    Citizen.Wait(sleep)
  end
end)

exports("GetVehicleIdentifier", getVehicleIdentifier)
exports("SetVehicleIdentifier", setVehicleIdentifier)
exports("AddKey", addKey)
