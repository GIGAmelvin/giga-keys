STATE = {
  ["?"] = "?",
  ["out"] = "out",
  ["garage"] = "garage",
  ["impound"] = "impound",
}

ROLE = {
  ["?"] = "?",
  ["owner"] = "owner",
}

Config = {
  KeysItem = "keys",             -- Name of the item from qb-core shared data.
  ControlKey = "l",              -- The DEFAULT control key.
  SearchAreaRadius = 20.0,       -- How far away do our vehicle keys work?
  ClientPollingInterval = 10000, -- How often do we ask the server to sync our keys?
  Smash = {
    Enabled = false,             -- Can you smash a window to unlock a vehicle?
    Alert = {
      Enabled = false,           -- Can a police alert automatically occur?
      Probability = 0.8,         -- Probability 0.0 - 1.0 that smashing a window will alert the police.
      Delay = {
        Minimum = 10000,         -- Minimum delay in ms before a police alert will occur.
        Maximum = 35000,         -- Maximum delay in ms before a police will occur.
      },
    },
    Alarm = {
      Duration = 20000, -- How long does a car alarm last?
    },
  },
  Exempt = {
    Vehicles = {},
  },
  AdminCommands = {
    Enabled = true, -- Should getkeyinfo and getvehicleinfo be enabled?
  },
}
