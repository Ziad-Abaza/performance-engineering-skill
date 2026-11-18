# Performance Anti-Patterns & Code Smells Checklist

Use this checklist during code review or discovery to quickly detect anti-patterns.

---

## 1. Database & Eloquent Smells

| Smell | Detection Heuristic / Code Example | Corrective Pattern |
| :--- | :--- | :--- |
| **N+1 in Blade / Vue loop** | Iterating a collection and accessing a relationship attribute `$order->customer->name` without eager loading. | Add `with('customer')` in controller query. |
| **DB Queries in Loops** | `foreach ($ids as $id) { Model::find($id); }` | Replace with `Model::whereIn('id', $ids)->get()`. |
| **Unbounded SELECT \*** | `User::all()` or `DB::table('logs')->get()` without `take()`, `paginate()`, or `select()`. | Add strict pagination `paginate(25)` and select only required columns. |
| **Count / Exists via Collection** | `$model->relation->count()` or `count($model->relation)`. | Use `$model->relation()->count()` or `withCount('relation')`. |
| **Hidden N+1 in Model `$appends`** | Accessing relationships inside accessor functions listed in `$appends`. | Remove from `$appends`; calculate via query subqueries. |
| **Offset Shift during Chunking** | Updating records inside `chunk($n, function($items) { ... })`. | Use `chunkById($n, ...)` to preserve index determinism. |
| **Unindexed Foreign Keys** | Columns named `*_id` in migrations without `$table->index()` or foreign key constraint. | Add composite or individual indexes for queried columns. |

---

## 2. Inertia.js & Vue 3 Smells

| Smell | Detection Heuristic / Code Example | Corrective Pattern |
| :--- | :--- | :--- |
| **Heavy Shared Props** | Running heavy queries in `HandleInertiaRequests::share()`. | Move to page-specific props or wrap in `Inertia::defer()`. |
| **Deep Reactive Tables** | `const rows = ref(largeDataset)` with 500+ items. | Use `const rows = shallowRef(largeDataset)`. |
| **Unbounded DOM lists** | Rendering `v-for="item in 1000Items"` without pagination or virtual scrolling. | Implement virtual scrolling (`@tanstack/vue-virtual`). |
| **Inline Function Execution in Templates** | Calling functions repeatedly in template loops: `:variant="formatStatus(item)"`. | Pre-compute or use a plain dictionary mapping: `statusMap[item.status]`. |
| **Deep Object Watchers** | `watch(filterState, ..., { deep: true })` causing multiple triggers. | Watch specific primitives or debounce the handler. |

---

## 3. Background Processing & Resource Smells

| Smell | Detection Heuristic / Code Example | Corrective Pattern |
| :--- | :--- | :--- |
| **Monolithic Queue** | Resizing videos, generating PDFs, and sending OTP emails all on `default`. | Isolate into `high`, `default`, `media`, and `reports`. |
| **Serializing Eloquent Models in Jobs** | Passing whole `$model` objects into `__construct(Model $model)` of a queued job. | Pass the model ID: `__construct(int $id)` and re-fetch in worker. |
| **Timeout > Retry After** | `$timeout = 120` in Job while `retry_after = 90` in `config/queue.php`. | Ensure `retry_after` is always at least 30s larger than job `$timeout`. |
| **Synchronous Media Conversions** | Converting uploaded images during HTTP POST request. | Use `$this->addMediaConversion(...)->queued()`. |
| **Unbounded Cache Growth** | `Cache::forever("user_data_{$id}", ...)` without TTL or eviction strategy. | Always define TTL (`now()->addHours(6)`) and cache keys. |
