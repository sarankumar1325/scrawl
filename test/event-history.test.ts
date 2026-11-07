import { describe, expect, it } from 'vitest';
import { EventHistory } from '../server/event-history';

describe('event replay', () => {
  it('replays missed events in order from an initial checkpoint', () => {
    const history = new EventHistory<string>(3, 'server');
    const checkpoint = history.latestId;
    history.record('moved');
    history.record('deleted');
    expect(history.since(checkpoint)).toMatchObject({ replayed: true, events: [{ event: 'moved' }, { event: 'deleted' }] });
    expect(history.since(history.latestId)).toEqual({ replayed: true, events: [] });
  });
  it('reports a gap when history is too old, malformed, or from another server', () => {
    const history = new EventHistory<string>(1, 'server');
    history.record('a'); history.record('b');
    for (const id of ['server:0', 'server:-1', 'server:99', 'other:1', 'server:abc']) {
      expect(history.since(id)).toEqual({ replayed: false, events: [] });
    }
    expect(history.since('server:1').events.map(x => x.event)).toEqual(['b']);
  });
});
