# SwitchLoader Receiver JS Prototype

This folder contains the nx.js UI prototype for the Switch-side companion app.

The installable USB backend currently lives in:

```text
../SwitchLoaderReceiverNative
```

Use the native receiver for the Homebrew install workflow:

1. Open receiver on the Switch.
2. Connect USB.
3. Generate a Homebrew folder in the Mac app.
4. Press **Install to Switch** in the Homebrew tab.

The JS app remains useful as the visual front-end direction. The next integration step is to have the native backend expose transfer state to the UI layer, or to port the UI styling into a native renderer.

## Prototype Build

Install Node.js, then from this folder:

```sh
npm install
npm run build
npm run nro
```

## Next Milestones

- Replace the IP-entry/network prototype with a native-backend-driven UI.
- Add cancel/resume controls and richer progress display.
- Keep this prototype aligned with the native Homebrew receiver UI.
