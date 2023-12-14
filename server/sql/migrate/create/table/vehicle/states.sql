CREATE TABLE IF NOT EXISTS `vehicle_states` (
  `id` INT(11) PRIMARY KEY NOT NULL AUTO_INCREMENT,
  `created` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` BOOL NOT NULL DEFAULT 1,
  `state` ENUM('?', 'out', 'garage', 'impound') NOT NULL DEFAULT '?',
  `vehicle_id` INT(11) REFERENCES `player_vehicles` (`id`)
) COMMENT = 'Historical states that a vehicle has been in.' ENGINE = InnoDB DEFAULT CHARSET = utf8 COLLATE = utf8_general_ci;
