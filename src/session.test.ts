import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ExcalidrawImperativeAPI } from '@excalidraw/excalidraw/types';
import { ApiError, api, type StoredScene } from '../src/api';

vi.mock('@excalidraw/excalidraw', () => ({
  CaptureUpdateAction: { NEVER: 'never' },
  getCommonBounds: () => [0, 0, 0, 0],
  hashElementsVersion: (elements: { version: number }[]) => elements.reduce((sum, el) => sum + el.version, 0),
  reconcileElements: (_local: unknown, incoming: unknown) => incoming,
  restore: (scene: StoredScene) => scene,
  restoreElements: (elements: unknown) => elements,
  serializeAsJSON: (_elements: unknown, appState: unknown) => JSON.stringify({ appState }),
}));
import { BoardSession, type SaveStatus } from '../src/session';

const scene = (): StoredScene => ({ type: 'excalidraw', elements: [], appState: {}, files: {} });
function setup() {
  let elements: { id: string; version: number; versionNonce: number; type: string; isDeleted: boolean }[] = [];
  const statuses: SaveStatus[] = [];
  const session = new BoardSession('Board', { etag: 'old', scene: scene() }, status => statuses.push(status));
  session.initialData({}, 0);
  const editor = {
    getSceneElementsIncludingDeleted: () => elements,
    getAppState: () => ({}),
    getFiles: () => ({}),
    addFiles: () => {},
    updateScene: () => {},
  } as unknown as ExcalidrawImperativeAPI;
  session.attach(editor);
  return { session, statuses, edit(version = 1) { elements = [{ id: 'a', version, versionNonce: 1, type: 'rectangle', isDeleted: false }]; } };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe('board save transitions', () => {
  it('keeps an offline board dirty and refuses to flush until it can save', async () => {
    const { session, edit } = setup();
    const save = vi.spyOn(api, 'save').mockRejectedValueOnce(new TypeError('offline')).mockResolvedValue({ etag: 'new', merged: null });
    edit();
    await expect(session.flush()).rejects.toThrow(/changes are still open/);
    expect(session.status).toBe('offline');
    expect(session.hasPendingChanges()).toBe(true);
    await expect(session.flush()).resolves.toBeUndefined();
    expect(session.status).toBe('saved');
    expect(session.hasPendingChanges()).toBe(false);
    expect(save).toHaveBeenCalledTimes(2);
  });

  it('does not report saved while edits made during a request remain pending', async () => {
    const { session, statuses, edit } = setup();
    let finish!: (value: { etag: string; merged: null }) => void;
    const save = vi.spyOn(api, 'save').mockImplementationOnce(() => new Promise(resolve => { finish = resolve; })).mockResolvedValue({ etag: 'second', merged: null });
    edit(1);
    const pending = session.flush();
    await vi.waitFor(() => expect(save).toHaveBeenCalledTimes(1));
    edit(2);
    finish({ etag: 'first', merged: null });
    await pending;
    expect(save).toHaveBeenCalledTimes(2);
    expect(statuses).toEqual(['saving', 'unsaved', 'saving', 'saved']);
  });

  it('preserves dirty state if the board has disappeared', async () => {
    const { session, edit } = setup();
    vi.spyOn(api, 'save').mockRejectedValue(new ApiError(404, 'missing'));
    edit();
    await expect(session.flush()).rejects.toThrow(/no longer exists/);
    expect(session.status).toBe('gone');
    expect(session.hasPendingChanges()).toBe(true);
  });
});
