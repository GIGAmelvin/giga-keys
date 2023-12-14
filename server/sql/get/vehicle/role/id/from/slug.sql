SELECT
  `id`
FROM
  `vehicle_roles`
WHERE
  ? = `slug`
LIMIT
  1;
