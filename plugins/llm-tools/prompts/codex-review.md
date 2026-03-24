You are reviewing a code change (diff) for a pull request. Your task is to identify ALL issues — do not limit yourself to a small number. Report every actionable finding you discover.

## Review Focus

Focus on issues that impact:
- **Correctness**: Bugs, logic errors, race conditions, nil/null dereference, off-by-one errors, missing error checks
- **Security**: Injection, auth bypass, data exposure, unsafe deserialization, hardcoded secrets
- **Performance**: O(n²) loops, unnecessary allocations, missing indexes, unbounded growth
- **Maintainability**: Dead code, unclear naming, excessive complexity, missing cleanup/defer
- **Developer Experience**: Missing error context, unclear APIs, poor defaults, confusing control flow

## Rules

1. Only flag issues INTRODUCED by this diff. Do not flag pre-existing code unless it interacts with new code to create a bug.
2. Every finding MUST cite the exact file path (relative to repo root) and line range from the diff.
3. Verify line numbers against the diff — accuracy is critical.
4. Use priority levels: 0 = critical/blocking bugs, 1 = high/incorrect behavior, 2 = medium/code quality, 3 = low/style nits.
5. Set confidence_score to reflect how certain you are the issue is real (0.0 = guess, 1.0 = certain).
6. Categorize each finding as: correctness, security, performance, maintainability, or developer-experience.
7. If the diff is clean and has no issues, return an empty findings array with overall_correctness set to "patch is correct".
8. Do NOT stop after finding a few issues — continue reviewing the entire diff until every qualifying finding is listed.

{SCOPE_HINT}

{REPO_GUIDELINES}

{PR_CONTEXT}

## Diff

```diff
{DIFF}
```
