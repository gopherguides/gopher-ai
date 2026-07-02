FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git nodejs npm

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

# Copy package files (package-lock.json is optional)
COPY package.json package-lock.json* ./
RUN npm install

COPY . .

RUN go install github.com/a-h/templ/cmd/templ@latest && \
    go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest && \
    sqlc generate -f sqlc/sqlc.yaml && \
    templ generate && \
    npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --minify && \
    CGO_ENABLED=0 go build -o server ./cmd/server

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/server .
COPY --from=builder /app/static ./static
COPY --from=builder /app/internal/database/migrations ./internal/database/migrations

EXPOSE 3000

CMD ["./server"]
