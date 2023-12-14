CREATE TABLE IF NOT EXISTS `players_vehicles_roles` (
  `id` INT(11) PRIMARY KEY NOT NULL AUTO_INCREMENT,
  `created` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` BOOL NOT NULL DEFAULT 1,
  `player_id` INT(11) NOT NULL COMMENT 'Who has this access level?' REFERENCES `players` (`id`),
  `vehicle_id` INT(11) NOT NULL COMMENT 'Which vehicle do they have access to?' REFERENCES `player_vehicles` (`id`),
  `role_id` INT(11) NOT NULL COMMENT 'What level of access do they have?' REFERENCES `vehicle_roles` (`id`)
) COMMENT = 'Access levels for vehicles.' ENGINE = InnoDB DEFAULT CHARSET = utf8 COLLATE = utf8_general_ci;
