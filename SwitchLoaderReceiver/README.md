# SwitchLoader Receiver

SwitchLoader Receiver is the Switch-side companion app for the SwitchLoader Mac app.

This first milestone is an nx.js prototype. It:

- Fetches a `manifest.json` published by the Mac app.
- Shows a clean queue UI on the Switch.
- Downloads the selected queue into `sdmc:/switch/SwitchLoaderReceiver/inbox/`.
- Tells the Mac server to stop when the transfer is complete.

It does not install titles yet. The native installer layer should be designed separately so the project stays focused on lawful personal dumps and homebrew.

## Mac Workflow

1. Open SwitchLoader on macOS.
2. Add files to the install queue.
3. Choose **Start Receiver Server**.
4. Copy the shown `http://.../manifest.json` address into `src/config.ts` for now.
5. Build and launch the receiver on the Switch.

## Build

Install Node.js, then from this folder:

```sh
npm install
npm run build
npm run nro
```

The nx.js templates use `nxjs-nro` for `.nro` packaging. A slim build expects the shared nx.js runtime on the SD card; use a fat build later if you want a self-contained `.nro`.

## Next Milestones

- Add on-device URL entry with the Switch keyboard.
- Add multi-file selection and cancel/resume controls.
- Add USB receiver support.
- Add a native C++/libnx installer bridge after the file receiver is stable.
