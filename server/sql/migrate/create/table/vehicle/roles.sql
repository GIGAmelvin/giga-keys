CREATE TABLE IF NOT EXISTS `vehicle_roles` (
  `id` INT(11) PRIMARY KEY NOT NULL AUTO_INCREMENT,
  `created` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` BOOL NOT NULL DEFAULT 1,
  `persist` BOOL NOT NULL DEFAULT 1 COMMENT 'Should this vehicle role cause access to persist until the role is revoked?',
  `description` VARCHAR(64) NOT NULL DEFAULT '?' COMMENT 'Some user-and-display-friendly description of this role.',
  `slug` VARCHAR(64) NOT NULL DEFAULT '?' COMMENT 'An internal lowercased and hyphenated name.',
  `access` ENUM('?', 'own', 'duplicate', 'rent', 'use') NOT NULL DEFAULT '?' COMMENT 'What level of access does this role provide?'
) COMMENT = 'Access levels for vehicles.' ENGINE = InnoDB DEFAULT CHARSET = utf8 COLLATE = utf8_general_ci;
