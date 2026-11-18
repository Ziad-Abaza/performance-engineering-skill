# Background Queues & Media Processing Performance Guide

## 1. Workload Separation & Queue Architecture

### 1.1 Never Mix Latency-Sensitive and CPU-Heavy Workloads
Placing image resizing or PDF generation into the `default` queue blocks high-priority operations (e.g., password reset emails, invoice dispatch, order webhooks).

**Recommended Queue Topology**:
- `high`: Fast, latency-critical operations (SLA < 5s).
- `default`: General asynchronous operations (SLA < 30s).
- `media`: Heavy Image/Video conversions (SLA < 5m).
- `reports`: PDF generation, bulk exports, spreadsheet processing.

**Worker Configuration (Supervisor / Forge / Docker)**:
```ini
; High priority worker: processes high queue first, then default
command=php artisan queue:work --queue=high,default --tries=3 --timeout=60

; Dedicated media processing worker: isolated so it cannot starve web transactions
command=php artisan queue:work --queue=media,reports --timeout=300 --memory=512
```

---

## 2. Queue Configuration & Reliability Guarantees

### 2.1 The `timeout` vs. `retry_after` Golden Rule
A common production disaster occurs when a job takes longer than `retry_after`:
- If `retry_after` is `90` seconds, but your PDF job `timeout` is `120` seconds, the queue runner will mark the job as timed-out after 90 seconds and **dispatch it to a second worker** while the first worker is still writing to disk!
- **Rule**: `retry_after` in `config/queue.php` MUST always be greater than any job's `$timeout` setting:
  $$\text{retry\_after} \ge \text{job timeout} + 30\text{ seconds}$$

### 2.2 Minimal Job Payloads & Model Serialization Hygiene
By default, Laravel jobs use the `SerializesModels` trait. This trait serializes the model identifier (class name and primary key) rather than the raw database table columns. However, passing full Eloquent instances into queued jobs carries important performance and reliability traps:

1. **Loaded Relationships Overhead**: If a model instance has multiple large relationship collections loaded in memory when passed to `dispatch()`, `SerializesModels` attempts to serialize relationship identifiers or un-persisted child models, causing payload bloat and redundant re-queries during hydration.
2. **Missing `SerializesModels` Trap**: If a developer forgets the `SerializesModels` trait on an event or job, PHP's native serializer writes the entire in-memory object graph (including connection pools and attribute caches) into Redis/database, causing massive payload bloat.
3. **Re-hydration Query Cost**: Every model in a job triggers a `find()` query upon worker wake-up. If a batch of 500 jobs is processed, 500 redundant single-record queries hit the database.
4. **Deleted Records (`ModelNotFoundException`)**: If the database record is deleted before the worker executes the job, the worker will throw `ModelNotFoundException` and enter failed jobs unless `$deleteWhenMissingModels = true` is configured.

**Recommended Pattern**: Pass primitive scalar IDs (`int $workOrderId`), or configure `$deleteWhenMissingModels`:

```php
// PATTERN A: Explicit scalar IDs (Lightest, decoupled, safest)
class GenerateInvoiceJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable;

    public function __construct(public int $workOrderId) {}

    public function handle(): void
    {
        $workOrder = WorkOrder::find($this->workOrderId);
        if (! $workOrder) {
            return; // Order was deleted while waiting in queue; exit gracefully
        }
        // Process invoice...
    }
}

// PATTERN B: If using Model instances with SerializesModels, guard against missing models:
class NotifyCustomerJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    // Discard job silently if the customer record was deleted before the worker runs
    public bool $deleteWhenMissingModels = true;

    public function __construct(public Customer $customer)
    {
        // Ensure relationships are not serialized into queue payload
        $this->customer = $customer->withoutRelations();
    }
}
```

### 2.3 Job Idempotency & Unique Jobs
Prevent duplicate processing from concurrent user clicks or queue retries using `ShouldBeUnique`:

```php
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;

class ProcessWorkOrderMedia implements ShouldQueue, ShouldBeUnique
{
    // Unique lock duration in seconds
    public int $uniqueFor = 300;

    public function __construct(public int $workOrderId) {}

    // Unique key ensures only one job runs per work order
    public function uniqueId(): string
    {
        return (string) $this->workOrderId;
    }
}
```

---

## 3. Media Processing (Spatie MediaLibrary / Intervention)

### 3.1 Asynchronous Conversions
Never process images synchronously inside the web request cycle.

```php
// In Model's registerMediaConversions():
public function registerMediaConversions(?Media $media = null): void
{
    $this->addMediaConversion('thumb')
        ->width(300)
        ->height(300)
        ->format('webp')
        ->quality(80)
        ->nonOptimized() // Speeds up if optimizing separately
        ->performOnCollections('attachments')
        ->queued(); // CRITICAL: Run in background queue
}
```

### 3.2 Responsive Images & Modern Formats
- Always generate **WebP** or **AVIF** variants alongside standard formats. WebP typically yields a 30-50% reduction in transfer payload compared to JPEG/PNG.
- Generate responsive image variants with width steps: `320w`, `640w`, `1024w`.

### 3.3 Preventing Memory Leaks during Bulk Conversions
Image processing tools (GD / Imagick) leak memory if looped over hundreds of files in a single process.
- Configure workers with `--max-jobs=100` or `--memory=512` so the worker restarts automatically after processing a batch, releasing operating system memory.
