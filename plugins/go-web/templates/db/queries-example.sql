-- name: GetExample :one
SELECT * FROM examples WHERE id = $1 LIMIT 1;

-- name: ListExamples :many
SELECT * FROM examples ORDER BY created_at DESC LIMIT $1 OFFSET $2;

-- name: CreateExample :one
INSERT INTO examples (name, description) VALUES ($1, $2) RETURNING *;

-- name: UpdateExample :exec
UPDATE examples SET name = $1, description = $2, updated_at = NOW() WHERE id = $3;

-- name: DeleteExample :exec
DELETE FROM examples WHERE id = $1;
