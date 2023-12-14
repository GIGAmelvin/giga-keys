author "GIGAmelvin <gigamelvin@proton.me>"
version "1.0.0"

fx_version "bodacious"
games { "gta5", }
lua54 "yes"

dependencies {
  "giga-migrate",
  "giga-util",
}

server_scripts {
  "@oxmysql/lib/MySQL.lua",
  "server/database.lua",
  "server/main.lua",
}

client_scripts {
  "client/main.lua",
  "client/smash.lua",
}

shared_scripts {
  "config.lua",
}

exports {
  "GetVehicleIdentifier",
  "SetVehicleIdentifier",
  "AddKey",
}
