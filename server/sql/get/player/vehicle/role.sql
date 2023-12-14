SELECT
  `pvr`.`id`,
  `pvr`.`created`,
  `pvr`.`active`,
  `pvr`.`player_id`,
  `pvr`.`vehicle_id`,
  `pvr`.`role_id`,
  `vr`.`description` AS `role_description`,
  `vr`.`slug` AS `role_slug`,
  `vr`.`access` AS `role_access`,
  `vr`.`persist` AS `role_persist`
FROM
  `players_vehicles_roles` `pvr`
  JOIN `vehicle_roles` `vr` ON `vr`.`id` = `pvr`.`role_id`
WHERE
  ? = `pvr`.`player_id`
  AND ? = `pvr`.`vehicle_id`
  AND 1 = `pvr`.`active`
ORDER BY
  `pvr`.`id` DESC
LIMIT
  1;
