# Performance Budgets & SLA Thresholds

Standard default quantitative budgets for web application engineering. Use these numbers during Phase 2 (Baseline) and Phase 5 (Verification) to assess whether an execution path meets performance targets.

---

## 1. Backend & API Budgets (Per HTTP Request)

| Metric | Ideal (Target) | Warning Threshold | Critical Failure | Remediation Priority |
| :--- | :--- | :--- | :--- | :--- |
| **Total Response Time (TTFB)** | $< 150\text{ ms}$ | $150\text{ ms} - 500\text{ ms}$ | $> 500\text{ ms}$ | P1: Profile DB & serialization |
| **Database Query Count** | $\le 10\text{ queries}$ | $11 - 25\text{ queries}$ | $> 25\text{ queries}$ | P0: Check for N+1 / lazy loads |
| **Single Query Duration** | $< 10\text{ ms}$ | $10\text{ ms} - 30\text{ ms}$ | $> 50\text{ ms}$ | P1: Run `EXPLAIN ANALYZE` / Index |
| **Total Database Time** | $< 50\text{ ms}$ | $50\text{ ms} - 150\text{ ms}$ | $> 150\text{ ms}$ | P1: Indexing & Eager loading |
| **Peak Memory Consumption** | $< 16\text{ MB}$ | $16\text{ MB} - 32\text{ MB}$ | $> 64\text{ MB}$ | P1: Chunking, remove hydration |
| **JSON Response Payload Size** | $< 100\text{ KB}$ | $100\text{ KB} - 500\text{ KB}$ | $> 1\text{ MB}$ | P0: Paginate & select columns |

---

## 2. Background Queue & Worker Budgets

| Metric | Ideal (Target) | Warning Threshold | Critical Failure | Remediation Priority |
| :--- | :--- | :--- | :--- | :--- |
| **Queue Wait Time (Latency)** | $< 5\text{ s}$ | $5\text{ s} - 30\text{ s}$ | $> 60\text{ s}$ | P1: Scale workers or separate queues |
| **Job Execution Time (Default)** | $< 2\text{ s}$ | $2\text{ s} - 10\text{ s}$ | $> 30\text{ s}$ | P2: Move to dedicated queue pool |
| **Media Conversion Job Time** | $< 15\text{ s}$ | $15\text{ s} - 60\text{ s}$ | $> 120\text{ s}$ | P2: Tune image quality / formats |
| **Queue Worker Memory Peak** | $< 128\text{ MB}$ | $128\text{ MB} - 256\text{ MB}$ | $> 512\text{ MB}$ | P1: Set `--max-jobs` worker recycling |

---

## 3. Frontend & Client-Side Budgets (Inertia & Vue)

| Metric | Ideal (Target) | Warning Threshold | Critical Failure | Remediation Priority |
| :--- | :--- | :--- | :--- | :--- |
| **Initial JS Bundle (Gzipped)** | $< 200\text{ KB}$ | $200\text{ KB} - 400\text{ KB}$ | $> 500\text{ KB}$ | P1: Code splitting & dynamic import |
| **Render / Mount Time** | $< 50\text{ ms}$ | $50\text{ ms} - 150\text{ ms}$ | $> 250\text{ ms}$ | P1: `shallowRef` / Virtualization |
| **DOM Nodes Rendered** | $< 800\text{ nodes}$ | $800 - 1,500\text{ nodes}$ | $> 2,000\text{ nodes}$ | P1: Paginate or Virtual Scroll |
| **Input Filter Debounce** | $250 - 350\text{ ms}$ | $< 100\text{ ms}$ | No debounce | P1: Add lodash debounce |
