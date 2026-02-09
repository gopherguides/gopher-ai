.PHONY: test lint audit coverage review

## Run tests
test:
	go test -race -count=1 ./...

## Run golangci-lint
lint:
	golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 ./...

## Full code quality audit (go vet + staticcheck + golangci-lint + API)
audit:
	@bash ../../.github/skills/scripts/audit.sh .

## Coverage report with gap analysis
coverage:
	@bash ../../.github/skills/scripts/coverage-report.sh

## Review changes against main
review:
	@echo "Generating PR review..."
	@DIFF=$$(git diff main...HEAD); \
	if [ -n "$$GOPHER_GUIDES_API_KEY" ] && [ -n "$$DIFF" ]; then \
		curl -s -X POST \
			-H "Authorization: Bearer $$GOPHER_GUIDES_API_KEY" \
			-H "Content-Type: application/json" \
			-d "{\"diff\": $$(echo "$$DIFF" | jq -Rs .)}" \
			https://gopherguides.com/api/gopher-ai/review | jq .; \
	else \
		echo "Set GOPHER_GUIDES_API_KEY or make changes vs main first"; \
	fi
