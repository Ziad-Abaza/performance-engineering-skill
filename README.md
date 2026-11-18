# performance-engineering

A systematic, evidence-driven **performance engineering skill** for AI coding agents.
It gives agents a disciplined diagnose → optimize → verify workflow for web
applications — with deep, version-aware reference material for **Laravel, Inertia.js
(v1/v2/v3), Vue 3, SQL, queues, caching, and concurrency**.

The skill enforces measurement before and after every change, forbids trading
correctness/security for speed, and ships executable stack-detection and
anti-pattern scanner scripts so findings are grounded in the real project, not
guesswork.

---

## Contents

```
performance-engineering/
├── SKILL.md                          # Entry point: operational rules + 6-phase workflow
├── references/
│   ├── laravel-eloquent.md           # N+1, aggregates, hydration, indexing, EXPLAIN
│   ├── inertia-vue.md                # v1/v2/v3 feature matrix, defer/optional, <Deferred>, Vue reactivity
│   ├── queues-media.md               # Queue topology, retry_after rule, job payloads, media pipelines
│   ├── caching-concurrency.md        # Driver capability matrix, tenant isolation, locks, stampedes
│   ├── performance-budgets.md        # Default SLA thresholds (TTFB, query count, memory, payload, DOM)
│   └── antipatterns-checklist.md     # Review checklist: smell → detection heuristic → fix
├── scripts/
│   ├── stack-detector.ps1 / .sh      # Detects framework versions, DB/cache drivers, modular layout
│   └── detect-antipatterns.ps1 / .sh # Static scanner for common performance anti-patterns
└── templates/
    └── audit-report-template.md      # Before/after verification report format
```

**Progressive loading by design:** the agent reads `SKILL.md`, then loads only the
reference file matching the active bottleneck — no wasted context.

---

## Installation

Install into any of the standard agent skill locations. Pick **one** depending on
whether you want the skill available globally (all projects) or vendored into a
single project.

### Option A — Git clone (recommended)

```bash
# Global (all projects, cross-runtime)
git clone https://github.com/Ziad-Abaza/performance-engineering-skill.git /tmp/performance-engineering
mkdir -p ~/.agents/skills
cp -r /tmp/performance-engineering ~/.agents/skills/performance-engineering

# Project-scoped
mkdir -p .agents/skills
cp -r /tmp/performance-engineering .agents/skills/performance-engineering
```

### Option B — Download ZIP (no git)

```bash
curl -L https://github.com/Ziad-Abaza/performance-engineering-skill/archive/refs/heads/main.zip -o pe.zip
unzip pe.zip
mkdir -p ~/.agents/skills
mv performance-engineering-skill-main ~/.agents/skills/performance-engineering
```

### Option C — Vendor into a project via git subtree

```bash
git subtree add --prefix .agents/skills/performance-engineering https://github.com/Ziad-Abaza/performance-engineering-skill.git main --squash
```

### Windows (PowerShell)

```powershell
git clone https://github.com/Ziad-Abaza/performance-engineering-skill.git "$env:TEMP\performance-engineering"
New-Item -ItemType Directory -Force "$env:USERPROFILE\.agents\skills" | Out-Null
Copy-Item -Recurse "$env:TEMP\performance-engineering" "$env:USERPROFILE\.agents\skills\"
```

### Skill directory locations by runtime

| Runtime | Global path | Project path |
| :--- | :--- | :--- |
| Claude Code | `~/.claude/skills/` | `<project>/.claude/skills/` |
| Devin / Windsurf | `~/.agents/skills/` | `<project>/.agents/skills/` or `<project>/.devin/skills/` |
| Codex / Copilot CLI / Gemini CLI | `~/.agents/skills/` | `<project>/.agents/skills/` |
| Cursor | — | `<project>/.cursor/skills/` |

> The skill folder must contain `SKILL.md` at its root — do not nest it inside an
> extra directory level (e.g. `skills/performance-engineering/performance-engineering/SKILL.md` will not be discovered).

---

## Verifying the installation

1. Restart the agent session (skills are discovered at session start).
2. Confirm the skill appears in the agent's skill list, or ask:

   > "Audit this page for performance issues."

   A correct install triggers the skill automatically for prompts about slow
   pages, N+1 queries, memory usage, queue latency, or bundle size.

3. (Optional) Smoke-test the bundled scripts:

   ```bash
   bash scripts/stack-detector.sh /path/to/project
   bash scripts/detect-antipatterns.sh /path/to/project
   ```

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\stack-detector.ps1 -TargetDir C:\path\to\project
   powershell -ExecutionPolicy Bypass -File scripts\detect-antipatterns.ps1 -TargetDir C:\path\to\project
   ```

---

## What the agent does with it

When triggered, the agent will:

1. **Discover** the stack (runs `stack-detector` or reads `composer.json` /
   `package.json` / `.env`: framework versions, DB driver, cache driver,
   modular vs. standard layout).
2. **Measure** a baseline (TTFB, query count, DB time, memory, payload).
3. **Prioritize** findings by impact vs. risk.
4. **Implement** surgical fixes using the domain reference (eager loading,
   aggregates, indexes, deferred/optional props, queue topology, cache isolation).
5. **Verify** against `performance-budgets.md` and the existing test suite.
6. **Report** using the audit template — separating *verified* improvements from
   *unverified/structural* ones.

### Requirements

- PowerShell 5+ (`.ps1` scripts) **or** a POSIX shell with `grep`/`find`/`tr`
  (`.sh` scripts — GNU and BSD compatible).
- No runtime dependencies otherwise — the skill is documentation + scripts.

---

## License

MIT — see [LICENSE](LICENSE).

---

**Author:** [Ziad Abaza](https://github.com/Ziad-Abaza) · zeyad.h.abaza@gmail.com
**Repository:** https://github.com/Ziad-Abaza/performance-engineering-skill
