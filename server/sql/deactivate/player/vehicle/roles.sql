UPDATE
  `players_vehicles_roles`
SET
  `active` = 0
WHERE
  ? = `player_id`
  AND ? = `vehicle_id`
  AND ? != `id`;
