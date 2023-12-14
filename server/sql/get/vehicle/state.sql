SELECT
  `created`,
  `state`
FROM
  `vehicle_states`
WHERE
  ? = `vehicle_id`
  AND `active` = 1
ORDER BY
  `id` DESC
LIMIT
  1;
