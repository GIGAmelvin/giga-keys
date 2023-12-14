SELECT
  `id`
FROM
  `vehicle_roles`
WHERE
  'owner' = `slug`
LIMIT
  1;
