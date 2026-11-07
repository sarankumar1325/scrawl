const invoke = window.__TAURI__.core.invoke;
const form = document.querySelector('#settings-form');
const directory = document.querySelector('#directory');
const port = document.querySelector('#port');
const endpoint = document.querySelector('#endpoint');
const status = document.querySelector('#status');
const log = document.querySelector('#log');

function showEndpoint() {
  endpoint.textContent = `http://localhost:${port.value || '3779'}/mcp`;
}
port.addEventListener('input', showEndpoint);
async function refreshLog() {
  try { log.textContent = (await invoke('desktop_log')) || 'No server output yet.'; }
  catch (error) { log.textContent = `Could not load the log: ${error}`; }
}
document.querySelector('#refresh-log').addEventListener('click', refreshLog);
document.querySelector('#restart').addEventListener('click', async event => {
  if (!window.confirm('Save the current board and restart Scrawl now?')) return;
  const button = event.currentTarget;
  button.disabled = true;
  status.textContent = 'Saving the current board before restarting…';
  try { await invoke('restart_desktop'); }
  catch (error) { status.textContent = `Could not restart Scrawl: ${error}`; }
  finally { button.disabled = false; }
});
form.addEventListener('submit', async event => {
  event.preventDefault();
  try {
    await invoke('save_desktop_settings', { settings: { port: Number(port.value), data_directory: directory.value.trim() } });
    status.textContent = 'Settings saved. Quit and reopen Scrawl to apply them.';
  } catch (error) { status.textContent = `Could not save settings: ${error}`; }
});
(async () => {
  try {
    const settings = await invoke('desktop_settings');
    directory.value = settings.data_directory;
    port.value = settings.port;
    showEndpoint();
  } catch (error) { status.textContent = `Could not load settings: ${error}. Enter a folder and port to replace them.`; }
  await refreshLog();
})();
