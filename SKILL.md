---
name: performance-engineering
description: >-
  Use when analyzing slow page loads, high database query counts (N+1), memory leaks, bloated bundles,
  queue latency, API response times, or performing systematic performance engineering, bottleneck profiling,
  and optimization across web applications, modular monoliths, and APIs (Laravel, Inertia.js, Vue 3, SQL).
---

# Performance Engineering & Optimization

A disciplined, evidence-driven framework for diagnosing, optimizing, and verifying application performance without compromising functional correctness, data integrity, security, or maintainability.

---

## 1. Non-Negotiable Operational Principles

1. **Evidence First**: Never optimize based on assumptions, aesthetic preferences, or theoretical gains. Measure before and after.
2. **Strict Change Boundaries**:
   - Never weaken validation, authorization, multi-tenant scoping, or business integrity for speed.
   - Never disable features or bypass data consistency checks without explicit approval.
   - Keep interventions minimal and surgical. Avoid broad, speculative refactoring.
3. **Cross-Stack & Modular Awareness**:
   - Honor the host architecture (Standard MVC, Modular Monoliths like `nwidart/laravel-modules`, Domain-Driven directories, or microservices).
   - Adapt diagnostics to the active database (PostgreSQL, MySQL, SQLite) and cache backend (Redis, Memcached, File, Database).
4. **Progressive Reference Loading**:
   Do NOT read all reference files at once. Read only the specific domain reference matching your current bottleneck:

| Domain / Bottleneck Area | Reference Document to Read |
| :--- | :--- |
| Database, Queries, Eloquent, Indexes, Hydration, Aggregates | [laravel-eloquent.md](./references/laravel-eloquent.md) |
| Inertia.js (v1/v2/v3), Vue 3, Reactivity, Deferred Props, Bundle Size | [inertia-vue.md](./references/inertia-vue.md) |
| Background Queues, Workers, Serialization, Media Conversions | [queues-media.md](./references/queues-media.md) |
| Caching Strategy, Atomic Locks, Cache Drivers, Concurrency | [caching-concurrency.md](./references/caching-concurrency.md) |
| Performance SLA & Default Threshold Budgets | [performance-budgets.md](./references/performance-budgets.md) |
| Comprehensive Anti-Patterns Checklist | [antipatterns-checklist.md](./references/antipatterns-checklist.md) |

---

## 2. The 6-Phase Optimization Workflow

Follow this closed-loop cycle for every optimization task. Scale the depth to the task:
- **Fast Track (Single query/index fix)**: Phases 2, 4, 5 with lightweight verification.
- **Full Track (Page latency, queue backlog, comprehensive audit)**: Phases 1 through 6.

### Phase 1: Stack & Architecture Discovery
1. Detect stack, versions, architecture, and database driver before proposing solutions:
   - Run stack detection script (`scripts/stack-detector.ps1` on Windows or `scripts/stack-detector.sh` on Linux/macOS) or inspect `composer.json` and `package.json`.
   - Verify architecture style: standard Laravel layout vs Modular Monolith (`Modules/`, `packages/`, `src/Domain/`).
   - Check cache driver (`redis`, `memcached` vs `file`, `database`) to ensure tag and atomic lock support.
   - Check database driver (`pgsql`, `mysql`, `sqlite`) for safe indexing strategies (`CONCURRENTLY` requiring `$withinTransaction = false` vs `ALGORITHM=INPLACE`).
   - Verify framework capabilities (e.g., Inertia v3 `optional()` vs v2 `defer()` vs v1 `lazy()`, Laravel 10/11 features like `once()`).
2. Check existing profiling infrastructure: Laravel Telescope, Clockwork, Debugbar, Pulse, or APM tools.

### Phase 2: Diagnosis & Baseline Measurement
1. Reproduce the bottleneck in a local or staging environment.
2. Record concrete baseline metrics before touching code:
   - Total Wall-Clock Latency (TTFB / p95 response time).
   - Database Query Count & Total DB Time.
   - Memory Usage (peak allocated memory).
   - Payload Transfer Size (network response bytes).
3. Identify root cause using `EXPLAIN / EXPLAIN ANALYZE`, query logs, or component profilers. Run anti-pattern scanner (`scripts/detect-antipatterns.ps1` or `scripts/detect-antipatterns.sh`).

### Phase 3: Prioritization & Risk Assessment
- Rank findings by **Impact vs. Complexity**:
   - High Impact / Low Risk: N+1 eager loading, aggregate queries (`withSum`/`withCount`), missing composite index, removing unused model hydration.
   - Medium Impact / Medium Risk: Caching with strict key isolation/tags, deferred props, partial reloads.
   - High Risk: Raw queries replacing ORM, queue architecture changes, schema alterations on large production tables.

### Phase 4: Surgical Implementation
- Implement the smallest effective intervention.
- Apply stack-specific best practices from the relevant `references/` file.
- Preserve all existing interfaces, route contracts, API resources, and tenant scopes.

### Phase 5: Verification & Regression Testing
1. Run existing test suite to ensure no business logic or authorization broke.
2. Re-measure the exact same execution path under identical conditions.
3. Compare Before vs. After metrics against [performance-budgets.md](./references/performance-budgets.md).
4. Verify edge cases (empty states, max page size, concurrent writes).

### Phase 6: Reporting
- Document findings using [audit-report-template.md](./templates/audit-report-template.md).
- Clearly separate:
  - **Verified Improvements** (backed by before/after numbers).
  - **Unverified / Structural Improvements** (implemented without benchmarking environment).
  - **Deferred Optimizations** (high complexity or requiring infrastructure changes).
