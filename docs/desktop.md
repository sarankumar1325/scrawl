# Scrawl desktop (Tauri)

The Tauri desktop app reuses the same editor, local server, `.excalidraw` files and MCP endpoint as the web app. It bundles Node.js and production server dependencies, so end users do not need to install Node. The server listens on `127.0.0.1:3779` and stops when the app exits. Boards are stored under `Documents/Scrawl`, matching the default location of the existing macOS app. If you previously chose a different folder in the macOS app, copy your data into that folder before switching. Do not run both apps against the same folder at once.

## Building

Install Node.js 22 or newer, Rust, and the platform prerequisites described in the [Tauri documentation](https://v2.tauri.app/start/prerequisites/). On Windows this includes the Microsoft C++ build tools and WebView2; on macOS it includes Xcode command-line tools.

```sh
npm ci
npm run desktop:dev   # build and run locally
npm run desktop:build # create the installer/bundle for this machine
```

Build separately on each target OS and CPU architecture. The preparation step copies the Node executable used to run the build, so build using a Node binary for the target architecture. Release signing and macOS notarization must be configured separately before distribution.

## Desktop settings and server logs

Choose **Server → Settings and logs** in the native menu to set the board folder or server port and inspect the latest server log. Save your changes, then restart Scrawl to apply them. Changing the folder does not move or copy boards; copy your existing data separately before switching. If the port is already occupied, Scrawl shows a startup error instead of terminating the other process. Open the same settings menu to change it.

To connect an MCP client, open the app menu and choose **Connect an AI agent** for the URL and setup examples. The app must remain open while the client uses it. Server start/stop controls and the Swift wrapper's menu shortcuts are not yet included in the Tauri version.

For a packaged-runtime smoke test after preparation, run `npm run desktop:smoke`. It starts the staged server with a temporary, isolated data directory and checks the editor, board creation, and MCP tools.

Repeated builds reuse unchanged staged assets, production dependencies, and the Node runtime. Release builds strip Rust symbols. For an experimental smaller macOS build, run `SCRAWL_STRIP_NODE=1 npm run desktop:build`; this also strips and ad-hoc signs the bundled Node executable. Run `npm run desktop:smoke` with the staged runtime afterward. This option is macOS-only, and distribution signing/notarization of the modified nested executable still needs to be validated before shipping. Omit the variable to restore the original Node binary.

Desktop packaging also omits TypeScript declaration files and JavaScript source maps from the staged production dependencies. Runtime JavaScript, package metadata and license files remain included. The source maps and declarations in the development checkout are unaffected.
