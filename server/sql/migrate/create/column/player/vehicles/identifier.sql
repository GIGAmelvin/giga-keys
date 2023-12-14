ALTER TABLE
  `player_vehicles`
ADD
  COLUMN `identifier` CHAR(36) UNIQUE NOT NULL DEFAULT UUID()
AFTER
  `id`;
