SQL = {
  get = {
    all = {
      vehicles = LoadResourceFile("giga-keys", "server/sql/get/all/vehicles.sql"),
    },
    vehicle = {
      identifier = {
        from = {
          id = LoadResourceFile("giga-keys", "server/sql/get/vehicle/identifier/from/id.sql"),
        },
      },
      id = {
        from = {
          identifier = LoadResourceFile("giga-keys", "server/sql/get/vehicle/id/from/identifier.sql"),
        },
      },
      role = {
        id = {
          from = {
            slug = LoadResourceFile("giga-keys", "server/sql/get/vehicle/role/id/from/slug.sql"),
          },
        },
      },
      state = LoadResourceFile("giga-keys", "server/sql/get/vehicle/state.sql"),
    },
    player = {
      vehicle = {
        role = LoadResourceFile("giga-keys", "server/sql/get/player/vehicle/role.sql"),
      },
      id = {
        from = {
          citizenid = LoadResourceFile("giga-keys", "server/sql/get/player/id/from/citizenid.sql"),
        },
      },
    },
  },
  create = {
    player = {
      vehicle = {
        role = LoadResourceFile("giga-keys", "server/sql/create/player/vehicle/role.sql"),
      },
    },
    vehicle = {
      state = LoadResourceFile("giga-keys", "server/sql/create/vehicle/state.sql"),
    },
  },
  deactivate = {
    player = {
      vehicle = {
        roles = LoadResourceFile("giga-keys", "server/sql/deactivate/player/vehicle/roles.sql"),
      },
    },
    vehicle = {
      states = LoadResourceFile("giga-keys", "server/sql/deactivate/vehicle/states.sql"),
    },
  },
  update = {
    vehicle = {
      garage = LoadResourceFile("giga-keys", "server/sql/update/vehicle/garage.sql"),
    },
  },
  migrate = {
    condition = {
      column = {
        player = {
          vehicles = {
            identifier = LoadResourceFile("giga-keys",
              "server/sql/migrate/condition/column/player/vehicles/identifier.sql"),
          },
        },
      },
      row = {
        vehicle = {
          role = {
            owner = LoadResourceFile("giga-keys", "server/sql/migrate/condition/row/vehicle/role/owner.sql"),
          },
        },
      },
    },
    create = {
      column = {
        player = {
          vehicles = {
            identifier = LoadResourceFile("giga-keys", "server/sql/migrate/create/column/player/vehicles/identifier.sql"),
          },
        },
      },
      row = {
        vehicle = {
          role = {
            owner = LoadResourceFile("giga-keys", "server/sql/migrate/create/row/vehicle/role/owner.sql"),
          },
        },
      },
      table = {
        vehicle = {
          roles = LoadResourceFile("giga-keys", "server/sql/migrate/create/table/vehicle/roles.sql"),
          states = LoadResourceFile("giga-keys", "server/sql/migrate/create/table/vehicle/states.sql"),
        },
        players = {
          vehicles = {
            roles = LoadResourceFile("giga-keys", "server/sql/migrate/create/table/players/vehicles/roles.sql"),
          },
        },
      },
    },
    cleanse = {
      vehicle = {
        states = LoadResourceFile("giga-keys", "server/sql/migrate/cleanse/vehicle/states.sql"),
      },
    },
  },
}

MySQL.ready(function()
  exports["giga-migrate"]:Migrate({
    SQL.migrate.create.table.vehicle.roles,
    SQL.migrate.create.table.vehicle.states,
    SQL.migrate.create.table.players.vehicles.roles,
    {
      queryType = "update",
      queries = { SQL.migrate.cleanse.vehicle.states, },
    },
    {
      conditions = {
        SQL.migrate.condition.row.vehicle.role.owner,
      },
      queries = {
        SQL.migrate.create.row.vehicle.role.owner,
      },
    },
    {
      conditions = {
        SQL.migrate.condition.column.player.vehicles.identifier,
      },
      queries = {
        SQL.migrate.create.column.player.vehicles.identifier,
      },
    },
  })

  -- Get all vehicles that are not in garages and return them to a garage.
  local outStates = MySQL.query.await("SELECT * FROM `vehicle_states` WHERE `state` = 'out' AND `active` = 1;")
  if type(outStates) ~= "table" or #outStates < 1 then return end
  for _, state in ipairs(outStates) do
    if type(state.vehicle_id) ~= "number" then goto continue end

    MySQL.transaction.await({
      [1] = { query = SQL.deactivate.vehicle.states, values = { state.vehicle_id, }, },
      [2] = { query = SQL.create.vehicle.state, values = { "garage", state.vehicle_id, }, },
    })

    ::continue::
  end
end)
