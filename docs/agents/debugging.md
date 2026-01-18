# Debugging Production Issues

When encountering 500 errors or unexpected behavior in production:

## 1. Check the Logs

```bash
# View live logs
fly logs

# Check recent errors
grep -i error /var/log/phoenix/production.log | tail -50
```

## 2. Identify the Error Pattern

Look for:
- **500 errors**: Check the exact controller and function that failed
- **Pattern**: Is it happening on specific pages?
- **Error messages**: Look for Elixir stacktraces

## 3. Reproduce Locally

```bash
mix phx.server
# Navigate to the problematic page
# Check local logs for similar errors
```

## 4. Common Production Issues

| Issue | Cause |
|-------|-------|
| Missing assigns | Production compiles with `phoenix_gen_html` which exposes template errors |
| Environment-specific | Code only fails in production |
| Database issues | Missing migrations or data |
| Asset compilation | CSS/JS not properly compiled |

## 5. Common 500 Error Causes

- Accessing `@changeset` directly in template instead of `@form`
- Missing required assign in LiveView (e.g., `@page_title`, `@current_user`)
- Pattern match failures in `handle_params`
- Database connection issues
- Template syntax errors
- Missing CSS imports

## 6. Fix Workflow

```bash
# 1. Make fix locally
# 2. Run tests
mix test
# 3. Format
mix format
# 4. Check warnings
mix compile --warnings-as-errors
# 5. Commit and push
git add . && git commit -m "fix: description" && git push
# 6. Verify CI passes
# 7. Check logs
fly logs
```

## 7. Useful Commands

```bash
# Check production logs
fly logs

# SSH into production
fly ssh console

# Rollback if needed
fly deploy --strategy=rollback
```

## Remember

- Production is stricter than development
- `mix compile --warnings-as-errors` catches issues that work in dev
- Always check logs first — they contain the stacktrace
