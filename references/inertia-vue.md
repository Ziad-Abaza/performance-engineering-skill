# Inertia.js & Vue 3 Performance Guide

## 1. Version Preconditions & Feature Matrix

Before recommending or writing Inertia code, check `composer.json` (`inertiajs/inertia-laravel`) and `package.json` (`@inertiajs/vue3`):

| Capability / API | Inertia v1.x | Inertia v2.x | Inertia v3.x | Recommended Action |
| :--- | :--- | :--- | :--- | :--- |
| **Deferred Props** | ❌ Not supported | ✅ `Inertia::defer($fn, $group)` | ✅ `Inertia::defer($fn, $group)` | Use to eliminate initial TTFB blocking |
| **Vue `<Deferred>` Component** | ❌ Not supported | ✅ `<Deferred data="...">` | ✅ `<Deferred data="...">` | Wrap deferred props with fallback skeleton |
| **Lazy Props** | ✅ `Inertia::lazy($fn)` | ⚠️ Deprecated | ❌ Removed | Replace with `Inertia::optional($fn)` |
| **Optional Props** | ❌ Not supported | ⚠️ Introduced | ✅ `Inertia::optional($fn)` | Use for on-demand tab/modal partial loads |
| **Merge Props / Infinite Scroll** | ❌ Not supported | ✅ `Inertia::merge()` | ✅ `Inertia::merge()` | Append pages without re-sending old items |
| **Prefetching & Polling** | ❌ Custom / manual | ✅ `router.prefetch`, `usePoll` | ✅ Enhanced | Prefetch on hover; poll without page reloads |

> [!CAUTION]
> **Inertia v3 Breaking Change**: `Inertia::lazy()` is removed in Inertia v3. If `inertiajs/inertia-laravel` is `^3.0` or higher, you **must** use `Inertia::optional()`. Using `Inertia::lazy()` will cause a runtime exception (`Call to undefined method Inertia\Inertia::lazy()`).

---

## 2. Inertia.js Server-to-Client Optimization

### 2.1 Deferred Props (Inertia v2+)
Offload non-critical data (charts, activity logs, heavy metrics) from the initial page load to eliminate Time-To-First-Byte (TTFB) blocking:

```php
use Inertia\Inertia;

public function show(WorkOrder $workOrder)
{
    return Inertia::render('WorkOrders/Show', [
        // Critical props: sent immediately in initial HTML/JSON
        'workOrder' => $workOrder->only(['id', 'number', 'status', 'customer_name']),
        'items' => $workOrder->items()->paginate(20),

        // Deferred prop: fetched automatically in parallel after initial paint
        'metrics' => Inertia::defer(fn () => $this->calculateOrderMetrics($workOrder)),

        // Deferred prop with group: pass group as SECOND argument (group is a string parameter, not a chainable setter)
        // Groups allow batching related deferred props together in single roundtrips
        'auditLogs' => Inertia::defer(fn () => $workOrder->auditLogs()->take(50)->get(), 'secondary'),
    ]);
}
```

> [!WARNING]
> **API Syntax Note**: `Inertia::defer(callable $callback, string $group = 'default', bool $rescue = false)` accepts the group name as its **second argument**. Do NOT chain `->group('secondary')` because `DeferProp::group()` is an internal getter method returning a string, not a fluent modifier. inertia-laravel v3.1+ adds the `rescue` flag — when `true`, a failing deferred callback resolves gracefully instead of erroring the follow-up request.

---

### 2.2 Optional Props vs. Deferred Props (`Inertia::optional()`)
Understanding when to use `optional()` vs `defer()`:

- **`Inertia::defer()`**: The prop is **automatically fetched by the browser immediately after initial page paint**. Ideal for data visible on page load that shouldn't block the initial server response (e.g. analytics charts, recent activity).
- **`Inertia::optional()` (replaces `Inertia::lazy()` in v3)**: The prop is **NOT fetched automatically**. It is evaluated *only* when the frontend explicitly requests it via partial reload (`only: ['tabDetails']`). Ideal for closed tabs, off-canvas drawers, or heavy modal datasets.

```php
// Inertia v3+ pattern for on-demand lazy tab data:
'detailedHistory' => Inertia::optional(fn () => $workOrder->history()->get()),
```

---

### 2.3 Shared Props Hygiene (`HandleInertiaRequests.php`)
Shared props are evaluated on **every single request**, including partial reloads, modal updates, and background polling.
- **Rule**: Never run database queries directly in `share()` without caching or user-specific memoization.
- **Rule**: Keep the auth object minimal (`id`, `name`, `email`, `role_ids`). Do not dump the entire User model with all permissions, roles, and relations into shared props.

```php
// BAD: Queries database on EVERY Inertia request, even partial reloads
'tenant_settings' => TenantSetting::first(),

// GOOD: Memoized or cached per session/tenant
'tenant_settings' => fn () => Cache::remember("tenant_settings_{$tenantId}", 3600, fn () => ...),
```

---

### 2.4 Partial Reloads & Filter Throttling
When searching or filtering a table, avoid reloading the entire page layout and unrelated props:

```javascript
import { router } from '@inertiajs/vue3'
import { debounce } from 'lodash-es'

// Prevent stale responses and avoid over-fetching
const updateSearch = debounce((query) => {
  router.get(
    route('work-orders.index'),
    { search: query },
    {
      only: ['workOrders'],       // Reloads ONLY the table dataset
      preserveState: true,
      preserveScroll: true,
      replace: true               // Prevents polluting browser history
    }
  )
}, 300)
```

---

## 3. Vue 3 Frontend Efficiency & `<Deferred>` Component

### 3.1 Handling Deferred Props with `<Deferred>` & Skeletons
When using deferred props, avoid blank flickering by rendering a skeleton or placeholder state using the `<Deferred>` component:

```vue
<template>
  <div class="space-y-6">
    <!-- Immediate critical content -->
    <h1 class="text-2xl font-bold">{{ workOrder.number }}</h1>

    <!-- Deferred Prop with Fallback Skeleton -->
    <Deferred data="metrics">
      <template #fallback>
        <div class="grid grid-cols-3 gap-4 animate-pulse">
          <div v-for="i in 3" :key="i" class="h-24 bg-gray-200 rounded-lg" />
        </div>
      </template>

      <!-- Rendered once deferred prop arrives -->
      <MetricsOverview :data="metrics" />
    </Deferred>

    <!-- Grouped Deferred Prop -->
    <Deferred data="auditLogs">
      <template #fallback>
        <div class="h-40 bg-gray-100 rounded-lg animate-pulse flex items-center justify-center text-gray-400">
          Loading audit trail...
        </div>
      </template>

      <AuditLogList :logs="auditLogs" />
    </Deferred>
  </div>
</template>

<script setup>
import { Deferred } from '@inertiajs/vue3'

defineProps({
  workOrder: Object,
  metrics: Object,
  auditLogs: Array,
})
</script>
```

---

### 3.2 Bypassing Deep Reactivity (`shallowRef` & `markRaw`)
When rendering large datasets (data tables, GIS coordinates, read-only item lists), Vue's default `ref()` recursively wraps every nested object and array in a reactive `Proxy`. For a 500-item table with 20 columns, this creates tens of thousands of proxies, spiking CPU and memory.

```javascript
import { shallowRef, markRaw } from 'vue'

// BAD: Deep reactive conversion of 1,000 items
const tableData = ref([])

// GOOD: Shallow ref tracks array assignment only; child objects are not proxied
const tableData = shallowRef([])

// For complex read-only objects (e.g. chart configs, schema definitions):
const chartOptions = markRaw({ ...heavyConfiguration })
```

---

### 3.3 Asynchronous Component Splitting (`defineAsyncComponent`)
Large components that are conditionally shown (modals, slide-overs, report builders, complex tabs) should be lazy-loaded on demand:

```javascript
import { defineAsyncComponent } from 'vue'

// Lazy-loaded chunk only fetched when tab is activated
const DeliverablesTab = defineAsyncComponent(() =>
  import('@/Pages/WorkOrders/Tabs/DeliverablesTab.vue')
)
```

---

### 3.4 Virtual Scrolling for Large Collections
If a list contains more than 100-200 DOM rows (e.g., item pickers, log viewers, audit trails):
- Do NOT render unbounded `v-for` elements.
- Use virtual scrolling (e.g., `@tanstack/vue-virtual` or `vue-virtual-scroller`) so only visible elements are rendered in the DOM.

---

### 3.5 Selective Reactivity & `v-memo`
Use `v-memo` conditionally to skip re-rendering rows in large tables unless specific attributes change:

```vue
<template>
  <tr 
    v-for="item in items" 
    :key="item.id" 
    v-memo="[item.id, item.status, item.is_selected]"
  >
    <td>{{ item.description }}</td>
    <td>
      <!-- Use deterministic status lookup rather than complex inline methods -->
      <Badge :variant="statusVariantMap[item.status]" />
    </td>
  </tr>
</template>

<script setup>
// Fast direct dictionary lookup instead of repeated method execution
const statusVariantMap = {
  pending: 'warning',
  approved: 'success',
  rejected: 'danger',
  in_progress: 'info',
}
</script>
```

> [!TIP]
> **Debugging TypeError: `$setup.methodName is not a function`**:
> When templates throw `TypeError: $setup.fn is not a function` during render:
> 1. Verify if the variable is an object mapping (e.g., `statusVariantMap`) being incorrectly called as a function: `statusVariantMap(status)` vs `statusVariantMap[status]`.
> 2. Ensure methods imported from composables or helper files are actually exported and included in the `<script setup>` scope.
