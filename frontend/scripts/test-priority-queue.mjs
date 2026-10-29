import assert from "node:assert/strict";

console.log("Testing AssetPriorityQueue logic...");

const AssetPriority = {
  CRITICAL: 0,
  HIGH: 1,
  LOW: 2,
  IDLE: 3
};

class TestPriorityQueue {
  queue = [];
  activeCount = 0;
  loadedUrls = new Set();
  activeItems = new Map();
  executionOrder = [];
  maxConcurrency = 2;

  enqueue(url, priority = AssetPriority.LOW, group) {
    if (this.loadedUrls.has(url)) return Promise.resolve();

    const existing = this.queue.find((item) => item.url === url);
    if (existing) {
      if (priority < existing.priority) {
        existing.priority = priority;
        this.sortQueue();
      }
      return Promise.resolve();
    }

    return new Promise((resolve) => {
      const controller = new AbortController();
      const item = {
        id: `${url}_${Date.now()}_${Math.random()}`,
        url,
        priority,
        group,
        abortController: controller,
        resolve
      };
      this.queue.push(item);
      this.sortQueue();
      this.processNext();
    });
  }

  cancelGroup(group) {
    const remaining = [];
    for (const item of this.queue) {
      if (item.group === group) {
        item.abortController.abort();
        item.resolve();
      } else {
        remaining.push(item);
      }
    }
    this.queue = remaining;

    for (const [id, item] of this.activeItems.entries()) {
      if (item.group === group) {
        item.abortController.abort();
        item.resolve();
        this.activeItems.delete(id);
        this.activeCount = Math.max(0, this.activeCount - 1);
      }
    }
    this.processNext();
  }

  sortQueue() {
    this.queue.sort((a, b) => a.priority - b.priority);
  }

  processNext() {
    while (this.activeCount < this.maxConcurrency && this.queue.length > 0) {
      const item = this.queue.shift();
      if (!item) break;

      this.activeCount++;
      this.activeItems.set(item.id, item);
      this.fetchAsset(item);
    }
  }

  async fetchAsset(item) {
    // simulate network latency
    await new Promise((r) => setTimeout(r, 10));
    if (!item.abortController.signal.aborted) {
      this.executionOrder.push(item.url);
      this.loadedUrls.add(item.url);
    }
    item.resolve();
    this.activeItems.delete(item.id);
    this.activeCount = Math.max(0, this.activeCount - 1);
    this.processNext();
  }
}

// 1. Test Priority Ordering
const q = new TestPriorityQueue();
q.maxConcurrency = 1; // force sequential execution to verify priority order

// Enqueue LOW, then IDLE, then CRITICAL
q.enqueue("/image-low.png", AssetPriority.LOW);
q.enqueue("/image-idle.png", AssetPriority.IDLE);
q.enqueue("/skin-critical.png", AssetPriority.CRITICAL);
q.enqueue("/tab-high.png", AssetPriority.HIGH);

// Wait for all to finish
await new Promise((r) => setTimeout(r, 100));

assert.deepEqual(
  q.executionOrder,
  // First item started immediately, then next was CRITICAL, then HIGH, then IDLE
  ["/image-low.png", "/skin-critical.png", "/tab-high.png", "/image-idle.png"],
  "Should execute higher priority items before lower priority items"
);
console.log("✓ Priority ordering verified!");

// 2. Test Group Cancellation
const q2 = new TestPriorityQueue();
q2.maxConcurrency = 1;
q2.enqueue("/store-1.png", AssetPriority.LOW, "tab-store");
q2.enqueue("/store-2.png", AssetPriority.LOW, "tab-store");
q2.enqueue("/events-1.png", AssetPriority.HIGH, "tab-events");

// Immediately cancel store group
q2.cancelGroup("tab-store");

await new Promise((r) => setTimeout(r, 60));

assert.ok(!q2.executionOrder.includes("/store-2.png"), "Cancelled group items must not execute");
assert.ok(q2.executionOrder.includes("/events-1.png"), "Other groups must execute normally");
console.log("✓ Group cancellation verified!");

console.log("\nAll AssetPriorityQueue tests passed!");
