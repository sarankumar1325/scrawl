import { Store } from '../../server/store.ts';
const [directory, prefix] = process.argv.slice(2);
const store = new Store(directory, 'test');
await store.init();
for (let i = 0; i < 4; i++) {
  await store.update('shared', prefix, async scene => {
    await new Promise(resolve => setTimeout(resolve, 20));
    return { scene: { ...scene, elements: [...scene.elements, { id: `${prefix}-${i}`, type: 'rectangle', version: 1, versionNonce: 1, isDeleted: false, updated: Date.now() }] }, result: null };
  });
}
