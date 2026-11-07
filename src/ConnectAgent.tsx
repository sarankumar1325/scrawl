import { useEffect, useRef, useState } from "react";

/** Connection details are derived from this app's origin, so they work on custom ports too. */
export function ConnectAgent({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [copied, setCopied] = useState(false);
  const endpoint = `${window.location.origin}/mcp`;
  const command = `claude mcp add --transport http scrawl ${endpoint}`;
  const config = JSON.stringify({ mcpServers: { scrawl: { url: endpoint } } }, null, 2);

  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(endpoint);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };

  return (
    <dialog ref={dialog} className="connect-agent" aria-labelledby="connect-agent-title" onClose={onClose}>
      <div className="connect-agent-header">
        <h2 id="connect-agent-title">Connect an AI agent</h2>
        <button type="button" onClick={onClose} aria-label="Close connection instructions">×</button>
      </div>
      <p>Connect an MCP client to let your agent read and draw on your boards while Scrawl is running.</p>
      <label htmlFor="mcp-url">MCP server URL</label>
      <div className="connect-agent-url">
        <input id="mcp-url" value={endpoint} readOnly onFocus={(event) => event.currentTarget.select()} />
        <button type="button" onClick={() => void copy()}>{copied ? "Copied" : "Copy URL"}</button>
      </div>
      <p className="connect-agent-note" role="status">{copied ? "URL copied to clipboard." : "If copying is unavailable, select the URL and copy it manually."}</p>
      <h3>Claude Code</h3>
      <pre><code>{command}</code></pre>
      <h3>Other MCP clients</h3>
      <p>Add this configuration to a client that supports MCP servers:</p>
      <pre><code>{config}</code></pre>
      <p className="connect-agent-note">For a local desktop app, the client must run on this computer. Connected clients can read and edit your boards.</p>
    </dialog>
  );
}
