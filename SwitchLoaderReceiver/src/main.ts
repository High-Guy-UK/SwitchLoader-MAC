import { inboxDirectory, manifestURL } from "./config";

type ReceiverManifest = {
  protocolVersion: number;
  generatedAt: string;
  host: string;
  port: number;
  files: ReceiverManifestFile[];
};

type ReceiverManifestFile = {
  name: string;
  encodedName: string;
  size: number;
  kind: "regular" | "split";
  url: string;
};

type AppState = {
  mode: "loading" | "ready" | "downloading" | "done" | "error";
  manifest?: ReceiverManifest;
  activeFile?: string;
  message: string;
  progress: number;
  downloadedBytes: number;
  totalBytes: number;
};

const ctx = screen.getContext("2d");
const state: AppState = {
  mode: "loading",
  message: "Connecting to SwitchLoader on your Mac.",
  progress: 0,
  downloadedBytes: 0,
  totalBytes: 0
};

let lastA = false;
let lastX = false;
let isBusy = false;

void loadManifest();
requestAnimationFrame(draw);
setInterval(pollInput, 80);

async function loadManifest() {
  state.mode = "loading";
  state.message = `Loading ${manifestURL}`;
  state.progress = 0;
  state.downloadedBytes = 0;
  state.totalBytes = 0;

  try {
    const response = await fetch(manifestURL, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Manifest request failed: ${response.status}`);
    }

    const manifest = (await response.json()) as ReceiverManifest;
    if (manifest.protocolVersion !== 1) {
      throw new Error(`Unsupported protocol version ${manifest.protocolVersion}`);
    }

    state.manifest = manifest;
    state.mode = "ready";
    state.message = manifest.files.length === 0
      ? "The Mac queue is empty."
      : "Press A to receive the queue.";
    state.totalBytes = manifest.files.reduce((sum, file) => sum + file.size, 0);
  } catch (error) {
    state.mode = "error";
    state.message = error instanceof Error ? error.message : "Could not load receiver manifest.";
  }
}

async function receiveQueue() {
  if (isBusy || !state.manifest || state.manifest.files.length === 0) {
    return;
  }

  isBusy = true;
  state.mode = "downloading";
  state.message = "Preparing SD card inbox.";
  state.progress = 0;
  state.downloadedBytes = 0;
  state.totalBytes = state.manifest.files.reduce((sum, file) => sum + file.size, 0);

  try {
    Switch.mkdirSync(inboxDirectory);

    for (const file of state.manifest.files) {
      state.activeFile = file.name;
      state.message = `Receiving ${file.name}`;
      await downloadFile(file);
    }

    state.mode = "done";
    state.progress = 1;
    state.message = `Saved ${state.manifest.files.length} file${state.manifest.files.length === 1 ? "" : "s"} to the inbox.`;
    await stopMacServer();
  } catch (error) {
    state.mode = "error";
    state.message = error instanceof Error ? error.message : "Transfer failed.";
  } finally {
    state.activeFile = undefined;
    isBusy = false;
  }
}

async function downloadFile(file: ReceiverManifestFile) {
  const response = await fetch(file.url);
  if (!response.ok || !response.body) {
    throw new Error(`Download failed for ${file.name}: ${response.status}`);
  }

  const outputPath = `${inboxDirectory}/${safeFileName(file.name)}`;
  const writer = Switch.file(outputPath).writable.getWriter();
  const reader = response.body.getReader();

  try {
    while (true) {
      const result = await reader.read();
      if (result.done) {
        break;
      }

      await writer.write(result.value);
      state.downloadedBytes += result.value.byteLength;
      state.progress = state.totalBytes === 0 ? 0 : state.downloadedBytes / state.totalBytes;
    }
  } finally {
    await writer.close();
  }
}

async function stopMacServer() {
  if (!state.manifest) {
    return;
  }

  const url = `http://${state.manifest.host}:${state.manifest.port}/__switchloader/drop`;
  try {
    await fetch(url, { method: "DROP" });
  } catch {
    // The transfer is already complete; shutdown notification is best effort.
  }
}

function pollInput() {
  const pad = navigator.getGamepads?.()[0];
  const a = Boolean(pad?.buttons[0]?.pressed);
  const x = Boolean(pad?.buttons[2]?.pressed);

  if (a && !lastA && state.mode === "ready") {
    void receiveQueue();
  }

  if (x && !lastX && (state.mode === "ready" || state.mode === "error" || state.mode === "done")) {
    void loadManifest();
  }

  lastA = a;
  lastX = x;
}

function draw() {
  const width = screen.width || 1280;
  const height = screen.height || 720;

  ctx.fillStyle = "#101418";
  ctx.fillRect(0, 0, width, height);

  drawHeader(width);
  drawPanel(56, 116, width - 112, 458);
  drawQueue(88, 158, width - 176);
  drawProgress(width, height);
  drawFooter(width, height);

  requestAnimationFrame(draw);
}

function drawHeader(width: number) {
  ctx.fillStyle = "#f4f7fb";
  ctx.font = "700 38px sans-serif";
  ctx.fillText("SwitchLoader Receiver", 56, 66);

  ctx.fillStyle = "#8ea0b6";
  ctx.font = "20px sans-serif";
  ctx.fillText(statusLabel(), width - 286, 64);
}

function drawPanel(x: number, y: number, width: number, height: number) {
  ctx.fillStyle = "#171d23";
  roundedRect(x, y, width, height, 8);
  ctx.fill();

  ctx.strokeStyle = "#2b3540";
  ctx.lineWidth = 2;
  roundedRect(x, y, width, height, 8);
  ctx.stroke();
}

function drawQueue(x: number, y: number, width: number) {
  ctx.fillStyle = "#cbd6e2";
  ctx.font = "700 24px sans-serif";
  ctx.fillText("Queue", x, y);

  const files = state.manifest?.files ?? [];
  ctx.fillStyle = "#7f91a6";
  ctx.font = "18px sans-serif";
  ctx.fillText(`${files.length} file${files.length === 1 ? "" : "s"} from ${state.manifest?.host ?? "Mac"}`, x, y + 34);

  const rows = files.slice(0, 6);
  rows.forEach((file, index) => {
    const rowY = y + 76 + index * 52;
    const isActive = state.activeFile === file.name;

    ctx.fillStyle = isActive ? "#263444" : "#1d252d";
    roundedRect(x, rowY - 28, width, 42, 6);
    ctx.fill();

    ctx.fillStyle = "#f4f7fb";
    ctx.font = "20px sans-serif";
    ctx.fillText(truncateMiddle(file.name, 58), x + 16, rowY);

    ctx.fillStyle = "#91a6bb";
    ctx.font = "18px sans-serif";
    ctx.textAlign = "right";
    ctx.fillText(formatBytes(file.size), x + width - 16, rowY);
    ctx.textAlign = "left";
  });

  if (files.length > rows.length) {
    ctx.fillStyle = "#7f91a6";
    ctx.font = "18px sans-serif";
    ctx.fillText(`+ ${files.length - rows.length} more`, x + 16, y + 76 + rows.length * 52);
  }

  ctx.fillStyle = state.mode === "error" ? "#ff8b8b" : "#cbd6e2";
  ctx.font = "20px sans-serif";
  wrapText(state.message, x, y + 402, width, 28);
}

function drawProgress(width: number, height: number) {
  const x = 88;
  const y = height - 112;
  const barWidth = width - 176;
  const barHeight = 16;

  ctx.fillStyle = "#26313b";
  roundedRect(x, y, barWidth, barHeight, 8);
  ctx.fill();

  ctx.fillStyle = "#3ec7a8";
  roundedRect(x, y, Math.max(8, barWidth * state.progress), barHeight, 8);
  ctx.fill();

  ctx.fillStyle = "#8ea0b6";
  ctx.font = "18px sans-serif";
  ctx.fillText(`${formatBytes(state.downloadedBytes)} / ${formatBytes(state.totalBytes)}`, x, y + 42);
}

function drawFooter(width: number, height: number) {
  ctx.fillStyle = "#8ea0b6";
  ctx.font = "18px sans-serif";
  ctx.fillText("A Receive", 56, height - 32);
  ctx.fillText("X Reload", 184, height - 32);

  ctx.textAlign = "right";
  ctx.fillText(inboxDirectory, width - 56, height - 32);
  ctx.textAlign = "left";
}

function roundedRect(x: number, y: number, width: number, height: number, radius: number) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
}

function statusLabel() {
  switch (state.mode) {
    case "loading":
      return "Connecting";
    case "ready":
      return "Ready";
    case "downloading":
      return "Receiving";
    case "done":
      return "Complete";
    case "error":
      return "Needs Attention";
  }
}

function safeFileName(name: string) {
  return name.replace(/[/:?#[\]@!$&'()*+,;=]/g, "_");
}

function truncateMiddle(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }

  const side = Math.floor((maxLength - 3) / 2);
  return `${value.slice(0, side)}...${value.slice(value.length - side)}`;
}

function formatBytes(value: number) {
  if (value < 1024) {
    return `${value} B`;
  }

  const units = ["KB", "MB", "GB", "TB"];
  let amount = value / 1024;
  let index = 0;
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024;
    index += 1;
  }
  return `${amount.toFixed(amount >= 100 ? 0 : 1)} ${units[index]}`;
}

function wrapText(text: string, x: number, y: number, maxWidth: number, lineHeight: number) {
  const words = text.split(" ");
  let line = "";

  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (ctx.measureText(next).width > maxWidth && line) {
      ctx.fillText(line, x, y);
      line = word;
      y += lineHeight;
    } else {
      line = next;
    }
  }

  if (line) {
    ctx.fillText(line, x, y);
  }
}
