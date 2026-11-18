# Caching Strategy & Concurrency Control Guide

## 1. Safe Caching Architecture & Driver Prerequisites

### 1.1 Cache Driver Capabilities & Constraints
Before designing a cache or concurrency solution, check the active cache driver in `.env` (`CACHE_STORE` or `CACHE_DRIVER`):

| Cache Feature | Redis | Memcached | Database | File / Array |
| :--- | :--- | :--- | :--- | :--- |
| **`Cache::tags()`** | ✅ Supported | ✅ Supported | ❌ Throws `BadMethodCallException` | ❌ Not supported (`array` supports in-memory only) |
| **`Cache::lock()`** | ✅ Atomic, distributed | ✅ Atomic, distributed | ✅ Supported via `cache_locks` table | ⚠️ `FileStore` implements `LockProvider` (works via `flock`) but is **single-server only** — not shared across nodes/pods. `array` works in-process only |
| **Distributed Expiry** | ✅ Native TTL | ✅ Native TTL | ✅ Purged via query | ⚠️ Disk read/write overhead |

> [!CAUTION]
> **Driver Safety Rule**: Never use `Cache::tags()` without verifying that the application is running on Redis or Memcached. In local/testing environments running on `file` or `database`, `Cache::tags()` will immediately crash with a runtime exception.

---

### 1.2 Multi-Tenant Cache Isolation (Security Critical)
In multi-tenant applications, failing to isolate cache keys creates severe data breach vulnerabilities where Tenant B views cached data belonging to Tenant A.

**Mandatory Key Composition**:
$$\text{cache\_key} = \text{tenant\_id} : \text{model/domain} : \text{entity\_id} : \text{context/locale}$$

```php
// BAD: Leaks cross-tenant data
$data = Cache::remember("work_order_{$id}", 3600, fn() => WorkOrder::find($id));

// GOOD: Strictly isolated by tenant and permissions
$cacheKey = sprintf('t:%d:wo:%d:lang:%s', auth()->user()->tenant_id, $id, app()->getLocale());
$data = Cache::remember($cacheKey, 3600, fn() => WorkOrder::find($id));
```

---

### 1.3 Cache Invalidation: Tags vs. Key Versioning
- Never introduce caching without defining its exact invalidation event.
- Prefer event-driven invalidation using Eloquent Observers or Model Events.

#### Approach A: Tagged Invalidation (Redis / Memcached Only)
```php
// In Model:
protected static function booted(): void
{
    static::saved(fn ($model) => Cache::tags(["tenant_{$model->tenant_id}", 'work_orders'])->flush());
    static::deleted(fn ($model) => Cache::tags(["tenant_{$model->tenant_id}", 'work_orders'])->flush());
}
```

#### Approach B: Driver-Agnostic Key Versioning (Safe for File, Database & Redis)
When cache tags are unavailable (e.g. running on `database` or `file` driver), invalidate groups of related keys by introducing a version counter into the key:

```php
// 1. Fetch the tenant-scoped version counter (defaults to 1)
$version = Cache::get("t:{$tenantId}:wo:version", 1);
$cacheKey = "v{$version}:t:{$tenantId}:wo:{$id}";

$data = Cache::remember($cacheKey, 3600, fn () => WorkOrder::find($id));

// 2. Invalidate all work order cache for this tenant instantaneously by bumping the version:
public static function invalidateTenantWorkOrders(int $tenantId): void
{
    // Cache::increment returns false when the key doesn't exist — seed it first
    Cache::add("t:{$tenantId}:wo:version", 1, now()->addDays(30));
    Cache::increment("t:{$tenantId}:wo:version");
}
```

---

### 1.4 Cache Stampede Prevention
When a high-traffic cache key expires, dozens of concurrent requests simultaneously hit the database to re-generate it, causing CPU and connection pool spikes.

```php
// Prevent stampede using atomic lock around cache regeneration (requires Redis, Memcached, or DB locks)
$value = Cache::get($cacheKey);

if ($value === null) {
    // Acquire a 10-second lock
    $lock = Cache::lock("lock:{$cacheKey}", 10);

    if ($lock->get()) {
        try {
            $value = $expensiveComputation();
            Cache::put($cacheKey, $value, now()->addHour());
        } finally {
            $lock->release();
        }
    } else {
        // Another worker is already regenerating; wait up to 3 seconds for result
        $lock->block(3);
        $value = Cache::get($cacheKey);
    }
}
```

---

### 1.5 Request-Scoped Memoization
For operations repeated multiple times in a single HTTP request (e.g., resolving the current authenticated user's permissions or active workspace settings):
- In Laravel 11+: Use the global `once()` helper:
  ```php
  function getActiveWorkspace(): Workspace
  {
      return once(fn () => auth()->user()->workspaces()->firstOrFail());
  }
  ```

---

## 2. Concurrency & Race Condition Elimination

### 2.1 Atomic Database Updates vs. In-Memory Calculations
Never load a model into memory to calculate stock, counters, or balances if concurrent requests can modify it.

```php
// DANGEROUS: Race condition between two concurrent requests
$product = Product::find($id);
$product->stock = $product->stock - $quantity; // Concurrent write overwrites
$product->save();

// SAFE: Single atomic database decrement operation
Product::where('id', $id)
    ->where('stock', '>=', $quantity) // Guard against negative inventory
    ->decrement('stock', $quantity);
```

### 2.2 Pessimistic Locking (`lockForUpdate`)
For transactional flows requiring multiple queries based on current state (e.g. checkout, credit deductions):

```php
DB::transaction(function () use ($workOrderId, $amount) {
    // Locks row until transaction commits; concurrent requests wait
    $account = Account::where('work_order_id', $workOrderId)->lockForUpdate()->first();

    if ($account->balance < $amount) {
        throw new InsufficientFundsException();
    }

    $account->balance -= $amount;
    $account->save();
});
```

### 2.3 Distributed Atomic Locks
Use atomic locks for operations spanning external APIs or distributed workers:

```php
Cache::lock("invoice_generation_{$orderId}", 10)->block(5, function () {
    // Only one worker can execute invoice generation at a time
    (new InvoiceService())->generate($orderId);
});
```
