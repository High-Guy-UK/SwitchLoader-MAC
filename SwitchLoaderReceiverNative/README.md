# SwitchLoader Receiver Native

Native libnx backend for the SwitchLoader Homebrew install workflow.

This target receives generated SwitchLoader Homebrew folders over USB and writes
their files directly into the matching SD card paths.

1. Open SwitchLoader Receiver on the Switch.
2. Connect USB.
3. In the Mac app, generate a Homebrew folder.
4. Press **Install to Switch** from the Homebrew tab.

Generated paths such as `switch/App/App.nro`, `atmosphere/...`,
`bootloader/...`, `config/...`, and `themes/...` are recreated under `sdmc:/`.
Unexpected paths are kept under `sdmc:/switch/SwitchLoaderReceiver/Homebrew Assets/`.

Commercial title installation is intentionally not handled by this receiver; use
the Mac app's Awoo/Tinfoil workflow with your existing installer for that path.

## Build

Requires devkitPro with libnx:

```sh
make
```

Output:

```text
SwitchLoaderReceiverNative.nro
```

Copy it to:

```text
sdmc:/switch/SwitchLoaderReceiver/SwitchLoaderReceiver.nro
```
