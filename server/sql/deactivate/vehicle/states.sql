UPDATE
  `vehicle_states`
SET
  `active` = 0
WHERE
  ? = `vehicle_id`
  AND `active` = 1;
