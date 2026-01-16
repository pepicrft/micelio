# Ralph Runner Instructions - ALL NIGHT RUNNING

## CRITICAL RULES

### 1. ONLY USE CODEX
**Ralph must NEVER write code directly.**
- For EVERY code task, spawn: `bash workdir:/root/src/micelio background:true command:"codex --yolo '<task>'"`
- Wait for completion using `process action:poll` loop
- Codex may take 5-15+ minutes - BE PATIENT
- NEVER write code yourself - always wait for Codex

### 2. VALIDATE & PUSH AFTER EVERY TASK
After Codex completes:
1. Run: `mix compile && mix test`
2. Run: `cd hif && zig build && zig build test`
3. Run: `git add -A && git commit -m "feat: <description>" && git push origin main`
4. Update @fix_plan.md to mark task complete

### 3. RUN FOREVER
- No max loops - run until explicitly killed
- Ignore completion signals
- Keep heartbeat file updated
- If all tasks done, move from NEXT.md to @fix_plan.md

## WORKFLOW (INFINITE LOOP)

1. `cd /root/src/micelio`
2. Read ralph-runner.md (remind yourself of rules)
3. Read @fix_plan.md - find first [ ] task
4. Spawn Codex: `bash workdir:/root/src/micelio background:true command:"codex --yolo '<task with full context>'"`
5. Wait: Loop `process action:poll` until no output
6. Validate: `mix compile && mix test && cd hif && zig build test`
7. Commit/Push: `git add -A && git commit -m "feat: <task>" && git push`
8. Mark task complete in @fix_plan.md
9. GOTO step 1

## NO SHORTCUTS
- No writing code yourself
- No skipping validation
- No stopping early
- No ignoring failures (retry or document)
