import { randomUUID } from 'node:crypto';

export type RecordedEvent<T> = { id: string; sequence: number; event: T };

/** Bounded, process-local history for EventSource reconnects. */
export class EventHistory<T> {
  private readonly epoch: string;
  private sequence = 0;
  private readonly entries: RecordedEvent<T>[] = [];

  constructor(private readonly limit = 1024, epoch: string = randomUUID()) {
    this.epoch = epoch;
  }

  get latestId(): string { return `${this.epoch}:${this.sequence}`; }

  record(event: T): RecordedEvent<T> {
    const item = { id: `${this.epoch}:${++this.sequence}`, sequence: this.sequence, event };
    this.entries.push(item);
    if (this.entries.length > this.limit) this.entries.shift();
    return item;
  }

  since(id: string | undefined): { replayed: boolean; events: RecordedEvent<T>[] } {
    if (!id) return { replayed: false, events: [] };
    const prefix = `${this.epoch}:`;
    if (!id.startsWith(prefix) || !/^\d+$/.test(id.slice(prefix.length))) return { replayed: false, events: [] };
    const seq = Number(id.slice(prefix.length));
    const oldest = this.entries[0]?.sequence ?? this.sequence + 1;
    if (!Number.isSafeInteger(seq) || seq > this.sequence || seq < oldest - 1) return { replayed: false, events: [] };
    return { replayed: true, events: this.entries.filter(entry => entry.sequence > seq) };
  }
}
