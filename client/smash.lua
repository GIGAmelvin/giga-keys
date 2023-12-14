-- xx - Disabled for now. Need to iron out details and balance around this
-- and it's not worth doing immediately.

if Config.Smash.Enabled then
  local Util = exports["giga-util"]:GetUtils()

  local SMASHED_VEHICLES = {}

  local function Debugger(identifier)
    return Util.Debugger(GetCurrentResourceName() .. ":client:" .. identifier)
  end

  -- Consider any vehicle with a busted driver-side window
  -- to be unlocked
  Citizen.CreateThread(function()
    while true do
      Citizen.Wait(200)
      local ped = GetPlayerPed(-1)
      local pos = GetEntityCoords(ped, false)
      local vehicle = GetClosestVehicle(pos.x, pos.y, pos.z, 5.0, 0, 71)
      local isDriverDoorLocked, isDriverWindowBroken
      if not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then goto continue end
      isDriverDoorLocked = GetVehicleDoorLockStatus(vehicle) == 2 or GetVehicleDoorLockStatus(vehicle) == 4
      if not isDriverDoorLocked then goto continue end

      isDriverWindowBroken = IsVehicleWindowIntact(vehicle, 0) == false
      if not isDriverWindowBroken then goto continue end

      SetVehicleDoorsLocked(vehicle, 1)

      ::continue::
    end
  end)

  -- This function must be debounced because one hit can cause multiple damage events.
  local HandleVehicleDamage = Util.Function.Debounce(function(name, args)
    local debug = Debugger("HandleVehicleDamage")
    local vehicle = args[1]
    local culprit = args[2]
    debug({ victim = vehicle, culprit = culprit, })
    if not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return debug("not victim or not vehicle") end
    if not DoesEntityExist(culprit) or not IsEntityAPed(culprit) then return debug("not culprit or not ped") end

    -- Only self-report window smashes
    if culprit ~= PlayerPedId() then return debug("culprit ped is not self") end

    local vehicleNetworkId = GetVehicleNetworkId(vehicle)
    if type(vehicleNetworkId) ~= "number" or vehicleNetworkId < 1 then return debug("vehicle not networked") end

    if SMASHED_VEHICLES[vehicleNetworkId] == true then return debug("vehicle already smashed") end

    local windowBroken = false
    for i = 0, 3 do
      if not IsVehicleWindowIntact(vehicle, i) then
        windowBroken = true
        break
      end
    end
    if not windowBroken then return end

    SMASHED_VEHICLES[vehicleNetworkId] = true
    debug("firing event")

    if GetVehicleDoorLockStatus(vehicle) ~= 0 then
      debug("triggering car alarm")
      SetVehicleAlarm(vehicle, true)
      Citizen.CreateThread(function()
        Citizen.Wait(Config.Smash.Alarm.Duration)
        debug("ending car alarm")
        if not vehicle or not DoesEntityExist(vehicle) then return end
        if not IsEntityAVehicle(vehicle) then return end
        local timeLeft = GetVehicleAlarmTimeLeft(vehicle)
        if type(timeLeft) ~= "number" or timeLeft < 1 then return end
        return SetVehicleAlarm(vehicle, false)
      end)
    end

    local shouldAlert = Config.Smash.Alert.Enabled and Util.Chance.Boolean(Config.Smash.Alert.Probability) or false
    debug({ shouldAlert = shouldAlert, })
    if not shouldAlert then return end
    local reportDelay = Util.Chance.Range(Config.Smash.Alert.Delay.Minimum, Config.Smash.Alert.Delay.Maximum)
    debug({ reportDelay = reportDelay, })

    Citizen.CreateThread(function()
      Citizen.Wait(reportDelay)
      if not shouldAlert then return debug("not reporting crime") end
      debug("reporting crime...")
      exports["ps-dispatch"]:VehicleTheft(vehicle) -- xx - make this a custom event
    end)
  end, 1000)

  AddEventHandler("gameEventTriggered", function(name, args)
    if name ~= "CEventNetworkEntityDamage" then return end
    return HandleVehicleDamage(name, args)
  end)
end
