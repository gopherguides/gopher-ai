package main

//go:generate echo "Generating SQLC files..."
//go:generate sqlc generate -f ../../sqlc/sqlc.yaml
//go:generate echo "SQLC files generated"

//go:generate echo "Generating templ files..."
//go:generate templ generate -path ../../templates
//go:generate echo "templ files generated"

//go:generate echo "Generating Tailwind CSS..."
//go:generate npx @tailwindcss/cli -i ../../static/css/input.css -o ../../static/css/output.css
//go:generate echo "Tailwind CSS generated"
