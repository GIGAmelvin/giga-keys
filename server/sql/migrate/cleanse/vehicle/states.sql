UPDATE
  `vehicle_states` `v`
  JOIN (
    SELECT
      `vehicle_id`,
      MAX(`id`) AS `id`
    FROM
      `vehicle_states`
    WHERE
      `active` = 1
    GROUP BY
      `vehicle_id`
  ) AS `subq` ON `v`.`vehicle_id` = `subq`.`vehicle_id`
SET
  `v`.`active` = 0
WHERE
  `v`.`id` < `subq`.`id`;
