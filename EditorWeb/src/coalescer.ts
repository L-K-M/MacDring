/**
 * Change coalescing for the editor -> host `changed` stream.
 *
 * Pure and timer-injected so the debounce/flush contract is unit-testable
 * without a DOM or a real editor. `EditorSession` owns one instance.
 *
 * Invariants:
 * - `note()` marks the session dirty; `flush()` clears it.
 * - At most one `changed` payload is pending; later notes replace earlier ones.
 * - `flush()` on a clean session emits nothing.
 */
export class ChangeCoalescer {
  private pending: string | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly delayMs: number,
    private readonly emit: (markdown: string) => void,
    private readonly schedule: typeof setTimeout = setTimeout,
    private readonly cancel: typeof clearTimeout = clearTimeout,
  ) {}

  get isDirty(): boolean {
    return this.pending !== null;
  }

  /** Content to persist if a flush happened now; null when clean. */
  get pendingMarkdown(): string | null {
    return this.pending;
  }

  note(markdown: string): void {
    this.pending = markdown;
    if (this.timer) this.cancel(this.timer);
    this.timer = this.schedule(() => this.flush(), this.delayMs);
  }

  flush(): void {
    if (this.timer) {
      this.cancel(this.timer);
      this.timer = null;
    }
    if (this.pending === null) return;
    const markdown = this.pending;
    this.pending = null;
    this.emit(markdown);
  }

  /** Drops any pending change without emitting (host replaced the document). */
  reset(): void {
    if (this.timer) {
      this.cancel(this.timer);
      this.timer = null;
    }
    this.pending = null;
  }
}
