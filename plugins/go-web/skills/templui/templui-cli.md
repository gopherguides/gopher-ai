# templUI CLI Tool

**Install CLI:**
```bash
go install github.com/templui/templui/cmd/templui@latest
```

**Key Commands:**
```bash
templui init                    # Initialize project, creates .templui.json
templui add button card         # Add specific components
templui add "*"                 # Add ALL components
templui add -f dropdown         # Force update existing component
templui list                    # List available components
templui new my-app              # Create new project
templui upgrade                 # Update CLI to latest version
```

**ALWAYS use the CLI to add/update components** - it fetches the complete component including Script() templates that may be missing if copied manually.
