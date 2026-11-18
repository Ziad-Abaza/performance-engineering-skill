# Laravel & Eloquent Performance Engineering Guide

## 1. Stack Detection & Compatibility
Before applying optimizations, verify the Laravel version in `composer.json`:
- `Model::preventLazyLoading()`: Laravel 8.43+
- `withExists()`: Laravel 8.x+
- `withSum()`, `withAvg()`, `withMin()`, `withMax()`: Laravel 8.x+
- `lazy()` / `lazyById()`: Laravel 8.x+
- `DB::transaction()` with deadlock retries: Available across all modern versions.

---

## 2. Preventing & Eliminating N+1 Queries

### 2.1 Enforce Lazy Loading Prevention in Development
Never enable lazy loading exceptions in production environments. Configure in `AppServiceProvider.php`:

```php
public function boot(): void
{
    // Prevent N+1 lazy loading outside production (throws LazyLoadingViolationException)
    Model::preventLazyLoading(! app()->isProduction());

    // In production: Log violations to monitoring tools without crashing user requests
    if (app()->isProduction()) {
        Model::handleLazyLoadingViolationUsing(function (Model $model, string $relation) {
            logger()->warning("N+1 Lazy loading detected on model [".get_class($model)."] relation [{$relation}]");
        });
    }
}
```

### 2.2 Constrained Eager Loading
When loading relationships, select **only** the required fields. 
> [!IMPORTANT]
> **Primary & Foreign Key Rule**: Always include the primary key (`id`) and the foreign key connecting the relationship in the column list, otherwise Eloquent cannot bind parent and child models, resulting in `null` relation properties!

```php
// BAD: Loads full models with all columns for every relationship
$workOrders = WorkOrder::with('items')->get();

// GOOD: Constrained columns + subquery filters
$workOrders = WorkOrder::query()
    ->select(['id', 'number', 'status', 'customer_id', 'created_at'])
    ->with([
        'customer:id,name,email',
        'items' => function ($query) {
            $query->select(['id', 'work_order_id', 'description', 'status', 'unit_price'])
                  ->where('is_active', true);
        }
    ])
    ->paginate(20);
```

### 2.3 Database Aggregates (`withCount`, `withExists`, `withSum`, `withAvg`)
Never hydrate entire relation collections into PHP memory simply to calculate counts, sums, or verify record existence. This is a severe anti-pattern that spikes CPU and memory.

```php
// SEVERE ANTI-PATTERN: Hydrating hundreds of child models into memory
$orders = Order::all();
foreach ($orders as $order) {
    $itemCount = $order->items->count();            // Hydrates all items!
    $totalAmount = $order->items->sum('price');     // Calculates in PHP array!
    $avgRating = $order->reviews->avg('rating');    // Hydrates reviews!
}

// EQUALLY BAD: Executing queries inside a loop (N+1 query problem)
foreach ($orders as $order) {
    $totalAmount = $order->items()->sum('price');   // Executes 1 separate query per order!
}

// PROPER PATTERN: Single query with database-level subqueries
$orders = Order::query()
    ->select(['id', 'order_number', 'customer_id', 'created_at'])
    ->withCount('items')                                                    // -> items_count
    ->withCount(['items as pending_items_count' => fn ($q) => $q->where('status', 'pending')])
    ->withExists('deliverables')                                            // -> deliverables_exists (boolean)
    ->withSum('items', 'price')                                             // -> items_sum_price
    ->withSum(['items as paid_items_total' => fn ($q) => $q->where('is_paid', true)], 'price')
    ->withAvg('reviews', 'rating')                                          // -> reviews_avg_rating
    ->paginate(20);

// In Blade, Vue, or API Resources, access as clean virtual attributes:
$itemCount = $order->items_count;
$pendingItems = $order->pending_items_count;
$hasDeliverables = $order->deliverables_exists;
$total = $order->items_sum_price ?? 0;
```

---

## 3. High-Volume Processing & Bulk Writes

### 3.1 Bulk Inserts & Upserts vs. Loops
Avoid calling `create()`, `update()`, or `save()` inside PHP loops (`foreach`).

```php
// BAD: 1,000 separate INSERT queries inside a loop
foreach ($items as $item) {
    WorkOrderItem::create($item);
}

// GOOD: Single bulk upsert query
// Requirements: A unique index/constraint must exist on the matching columns (e.g. ['work_order_id', 'item_code'])
WorkOrderItem::upsert(
    $itemsData, // array of arrays
    uniqueBy: ['work_order_id', 'item_code'],
    update: ['description', 'quantity', 'unit_price', 'updated_at']
);
```

> [!WARNING]
> `upsert()` and `insert()` bypass Eloquent model lifecycle events (`creating`, `created`, `updating`, etc.), mutators, and automatic timestamp updates (unless explicitly supplied in the dataset). Verify that no business logic depends on model events before switching.

### 3.2 `chunkById()` vs `chunk()` vs `lazyById()`
When processing large tables (migrations, bulk notifications, exports):

- **Never use `chunk()` if you are updating records** within the loop! Updating changes the query offset, causing records to be skipped or processed twice.
- **Use `chunkById()`** for batch-wise memory efficiency when an auto-incrementing ID is present.
- **Use `lazyById()`** when streaming records one by one via generators.

```php
// Efficient, deterministic processing without memory blowup
WorkOrder::where('status', 'draft')
    ->where('created_at', '<', now()->subDays(30))
    ->chunkById(500, function ($orders) {
        foreach ($orders as $order) {
            $order->markAsArchived();
        }
    });
```

---

## 4. Model Hydration & Serialization Overhead

### 4.1 Hidden N+1 in Appended Attributes (`$appends`)
Check models for `$appends`. If an appended attribute accesses a relationship, it executes a query for **every single serialized record** during JSON response serialization (API resources or Inertia responses).

```php
// DANGEROUS PATTERN in Model:
protected $appends = ['total_cost'];

public function getTotalCostAttribute()
{
    // Executes a query per record if 'items' is not eager-loaded!
    return $this->items->sum('cost');
}
```
**Remedy**:
1. Remove attribute from `$appends`.
2. Compute the value using database subqueries (`withSum()`, `withCount()`) or compute in a dedicated API Resource that checks `whenLoaded('items')`.

### 4.2 Lightweight Database Extraction
If records are only read and never updated:
- Use `select()` and `pluck()` for single-column arrays.
- Use `DB::table(...)` instead of Eloquent when hydrating tens of thousands of complex models is unnecessary.

---

## 5. Indexing Strategy & Safe Migrations

### 5.1 Composite Index Rule (Equality-Range-Sort)
Composite indexes must follow the predicate pattern:
1. First: Columns tested with equality (`WHERE tenant_id = 5 AND status = 'active'`)
2. Second: Columns used for sorting (`ORDER BY created_at DESC`)
3. Third: Columns tested with ranges (`WHERE amount > 100`)

```php
// Optimal index for: WHERE tenant_id = ? AND status = ? ORDER BY created_at DESC
$table->index(['tenant_id', 'status', 'created_at'], 'wo_tenant_status_created_idx');
```

### 5.2 Safe Online Indexing in Production & Migration Transactions

Adding indexes on large tables in production can lock write operations and cause service outages.

#### PostgreSQL: Concurrent Index Creation
PostgreSQL allows zero-downtime index creation via `CREATE INDEX CONCURRENTLY`.
> [!CAUTION]
> **PostgreSQL Migration Requirement**: In PostgreSQL, `CREATE INDEX CONCURRENTLY` **cannot run inside a transaction block**. Because Laravel automatically wraps migrations in database transactions on PostgreSQL, the migration will throw:
> `SQLSTATE[25001]: Active sql transaction: 7 ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`
> You **must** set `public bool $withinTransaction = false;` on the migration class!

```php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    // CRITICAL FOR POSTGRESQL: Disables automatic transaction wrapping
    public bool $withinTransaction = false;

    public function up(): void
    {
        DB::statement('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_wo_tenant_status ON work_orders (tenant_id, status);');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX CONCURRENTLY IF EXISTS idx_wo_tenant_status;');
    }
};
```

#### MySQL / MariaDB: Online DDL
On MySQL 5.7+ / 8.0+, specify online DDL algorithm to avoid read/write table locks:

```php
public function up(): void
{
    DB::statement('ALTER TABLE work_orders ADD INDEX idx_wo_tenant_status (tenant_id, status), ALGORITHM=INPLACE, LOCK=NONE;');
}
```

---

## 6. Query Plan Verification (`EXPLAIN`)
Always inspect query execution before declaring an index effective:
```sql
EXPLAIN ANALYZE
SELECT id, number, status 
FROM work_orders 
WHERE tenant_id = 1 AND status = 'in_progress' 
ORDER BY created_at DESC 
LIMIT 20;
```
Check for:
- `ALL` or `Seq Scan` (Full table scan -> missing index or low cardinality).
- `Using filesort` or `Sort (external merge)` (Sort not covered by index).
- `rows` examined vs `rows` returned (Large discrepancy = poor index selectivity).
