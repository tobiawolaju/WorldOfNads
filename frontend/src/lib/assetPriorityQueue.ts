import { getDeviceProfile } from "./deviceProfile";
import { isLowEndDevice } from "./gameQuality";
import { resolveSkinImageUrl } from "./skinMapping";

export enum AssetPriority {
  CRITICAL = 0, // Current equipped skin, 3D character, active backdrop
  HIGH = 1,     // Active tab visible cards, immediate hover target
  LOW = 2,      // Inactive tab previews, next-up items
  IDLE = 3      // Background cache warming
}

export interface QueueItem {
  id: string;
  url: string;
  priority: AssetPriority;
  group?: string;
  abortController: AbortController;
  resolve: () => void;
  reject: (err: unknown) => void;
}

class AssetPriorityQueue {
  private queue: QueueItem[] = [];
  private activeCount: number = 0;
  private loadedUrls = new Set<string>();
  private activeItems = new Map<string, QueueItem>();

  /**
   * Maximum concurrent requests allowed.
   * Capped low on low-end devices / 3G connections to prevent starving critical UI interactions.
   */
  private getMaxConcurrency(): number {
    if (typeof window === "undefined") return 4;
    const profile = getDeviceProfile();
    const isLow = profile.tier === "low" || isLowEndDevice();
    const nav = navigator as unknown as { connection?: { effectiveType?: string; saveData?: boolean } };
    const slowNet = nav.connection?.saveData || nav.connection?.effectiveType === "3g" || nav.connection?.effectiveType === "2g";

    if (isLow || slowNet) {
      return 2;
    }
    return 5;
  }

  /**
   * Enqueues an asset URL for prioritized background caching.
   * If the asset is already loaded, returns immediately.
   */
  public enqueue(
    url: string,
    priority: AssetPriority = AssetPriority.LOW,
    group?: string
  ): Promise<void> {
    if (!url || typeof window === "undefined" || !("fetch" in window)) {
      return Promise.resolve();
    }

    if (this.loadedUrls.has(url)) {
      return Promise.resolve();
    }

    // If already in queue, bump priority if new priority is higher (lower numeric value)
    const existing = this.queue.find((item) => item.url === url);
    if (existing) {
      if (priority < existing.priority) {
        existing.priority = priority;
        this.sortQueue();
      }
      return Promise.resolve();
    }

    return new Promise<void>((resolve, reject) => {
      const controller = new AbortController();
      const item: QueueItem = {
        id: `${url}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
        url,
        priority,
        group,
        abortController: controller,
        resolve,
        reject
      };

      this.queue.push(item);
      this.sortQueue();
      this.processNext();
    });
  }

  /**
   * Cancels all pending and in-flight asset downloads for a specific group (e.g. "tab-store").
   */
  public cancelGroup(group: string): void {
    if (!group) return;

    // 1. Remove pending from queue
    const remaining: QueueItem[] = [];
    for (const item of this.queue) {
      if (item.group === group) {
        item.abortController.abort();
        item.resolve();
      } else {
        remaining.push(item);
      }
    }
    this.queue = remaining;

    // 2. Abort in-flight items for this group
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

  /**
   * Prioritizes the queue: CRITICAL (0) first, then HIGH (1), LOW (2), IDLE (3).
   */
  private sortQueue(): void {
    this.queue.sort((a, b) => a.priority - b.priority);
  }

  /**
   * Processes the next item in the priority queue if concurrency allows.
   */
  private processNext(): void {
    const maxConcurrency = this.getMaxConcurrency();

    while (this.activeCount < maxConcurrency && this.queue.length > 0) {
      const item = this.queue.shift();
      if (!item) break;

      if (this.loadedUrls.has(item.url)) {
        item.resolve();
        continue;
      }

      this.activeCount++;
      this.activeItems.set(item.id, item);
      this.fetchAsset(item);
    }
  }

  /**
   * Streams the asset into the browser's HTTP disk cache without holding it in JS memory.
   */
  private async fetchAsset(item: QueueItem): Promise<void> {
    try {
      const fetchPriority = item.priority === AssetPriority.CRITICAL ? "high" : item.priority === AssetPriority.HIGH ? "auto" : "low";

      const res = await fetch(item.url, {
        cache: "default",
        signal: item.abortController.signal,
        // @ts-expect-error - fetchPriority is supported in modern browsers
        priority: fetchPriority
      });

      if (res.ok) {
        if (res.body && typeof res.body.getReader === "function") {
          const reader = res.body.getReader();
          try {
            while (true) {
              const { done } = await reader.read();
              if (done) break;
            }
          } finally {
            reader.releaseLock();
          }
        } else {
          await res.blob();
        }
        this.loadedUrls.add(item.url);
      }
      item.resolve();
    } catch {
      // Abort or network failure
      item.resolve();
    } finally {
      this.activeItems.delete(item.id);
      this.activeCount = Math.max(0, this.activeCount - 1);
      this.processNext();
    }
  }
}

export const assetQueue = new AssetPriorityQueue();

/**
 * Preload high-priority skin preview asset (e.g. when selected in store or equipped).
 */
export function preloadSkinAsset(skinId: string, priority: AssetPriority = AssetPriority.HIGH): void {
  const url = resolveSkinImageUrl(skinId);
  if (url) {
    void assetQueue.enqueue(url, priority, `skin-${skinId}`);
  }
}

/**
 * Preload inactive tab thumbnails in idle time or on tab hover.
 */
export function preloadTabThumbnail(url: string, priority: AssetPriority = AssetPriority.LOW, tabName?: string): void {
  if (url) {
    void assetQueue.enqueue(url, priority, tabName ? `tab-${tabName}` : undefined);
  }
}

/**
 * Cancels background fetches for a tab when switching away.
 */
export function cancelTabPrefetch(tabName: string): void {
  assetQueue.cancelGroup(`tab-${tabName}`);
}
