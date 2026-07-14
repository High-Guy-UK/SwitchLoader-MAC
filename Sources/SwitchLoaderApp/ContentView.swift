import SwiftUI
import AppKit
import SwitchLoaderCore
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    @State private var selectedTab = AppTab.workflow
    @State private var selectedLibraryGame: LibraryGame?
    @State private var isShowingMetadataSettings = false
    @State private var metadataAPIKey = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch selectedTab {
            case .workflow:
                HStack(spacing: 0) {
                    workflow
                        .frame(width: 360)
                    Divider()
                    VStack(spacing: 0) {
                        fileList
                            .frame(height: 260)
                        Divider()
                        utilities
                            .frame(height: 128)
                    }
                }
            case .library:
                library
            case .rcm:
                rcmWorkflow
            case .log:
                fullLog
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .library {
                model.scanLibrary()
            } else if newTab == .rcm {
                model.refreshRCMConnection()
            }
        }
        .sheet(item: $selectedLibraryGame) { game in
            LibraryGameDetailSheet(game: game) {
                selectedLibraryGame = nil
            }
            .environmentObject(model)
            .frame(minWidth: 760, minHeight: 560)
        }
        .sheet(isPresented: $isShowingMetadataSettings) {
            MetadataSettingsSheet(apiKey: $metadataAPIKey) {
                model.saveTheGamesDBAPIKey(metadataAPIKey)
                isShowingMetadataSettings = false
            } onCancel: {
                isShowingMetadataSettings = false
            }
            .frame(width: 460)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text("SwitchLoader")
                    .font(.title3.bold())
                Text("USB install workflow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $selectedTab) {
                Label("Install", systemImage: "cable.connector").tag(AppTab.workflow)
                Label("Library", systemImage: "books.vertical").tag(AppTab.library)
                Label("RCM", systemImage: "bolt.horizontal").tag(AppTab.rcm)
                Label("Log", systemImage: "list.bullet.rectangle").tag(AppTab.log)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            .labelsHidden()

            Spacer()
            StatusBadge(status: model.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Install Over USB")
                .font(.headline)

            WorkflowStep(number: 1, title: "Choose install files", detail: "Add NSP, NSZ, XCI, XCZ, or split folders.")
            WorkflowStep(number: 2, title: "Set device waiting", detail: "Open Awoo, Tinfoil-compatible, or USB installer mode on the device.")
            WorkflowStep(number: 3, title: "Connect USB", detail: "Use a data-capable cable and keep the installer waiting.")
            WorkflowStep(number: 4, title: "Send from Mac", detail: model.currentInstruction)

            ProgressView(value: model.progress)

            HStack {
                Button {
                    chooseInstallFiles()
                } label: {
                    Label("Choose", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.startUSBInstall()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartUSBInstall)
            }

            Button {
                model.clearFiles()
            } label: {
                Label("Clear Queue", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.selectedFiles.isEmpty)
        }
        .padding(16)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Install Queue")
                    .font(.headline)
                Spacer()
                Text("\(model.selectedFiles.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)

            List {
                ForEach(model.selectedFiles, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(systemName: url.hasDirectoryPath ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(url.lastPathComponent)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .layoutPriority(1)

                        Text("-")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: model.removeFiles)
            }
        }
    }

    private var utilities: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Split / Merge")
                        .font(.headline)

                    Text(model.splitMergeOutputDirectory?.path ?? "Same folder as source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Button {
                    chooseOutputFolder()
                } label: {
                    Label("Output Folder", systemImage: "folder.badge.gearshape")
                }
            }

            HStack(spacing: 10) {
                Button {
                    model.splitSelectedFiles()
                } label: {
                    Label("Split", systemImage: "square.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.selectedFiles.isEmpty || model.status == .running)

                Button {
                    model.mergeSelectedFolders()
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.selectedFiles.isEmpty || model.status == .running)
            }
        }
        .padding(16)
    }

    private var library: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Library")
                    .font(.headline)

                Text(model.libraryDirectory?.path ?? "No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Button {
                        chooseLibraryFolder()
                    } label: {
                        Label("Folder", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        openLibraryFolder()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .frame(width: 28)
                    }
                    .disabled(model.libraryDirectory == nil)
                    .help("Open library folder")
                }

                Button {
                    model.scanLibrary()
                } label: {
                    Label(model.isScanningLibrary ? "Scanning" : "Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.libraryDirectory == nil || model.isScanningLibrary)

                Button {
                    metadataAPIKey = ""
                    isShowingMetadataSettings = true
                } label: {
                    Label(model.hasTheGamesDBAPIKey ? "TGDB Connected" : "TGDB Key", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.refreshLibraryMetadata()
                } label: {
                    Label(model.isFetchingMetadata ? "Fetching Art" : "Fetch Artwork", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.hasTheGamesDBAPIKey || model.libraryGames.isEmpty || model.isFetchingMetadata)

                Button {
                    model.addLibraryToQueue()
                    selectedTab = .workflow
                } label: {
                    Label("Add All to Queue", systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.libraryGames.isEmpty)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Install main games before updates or DLC.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text("Game detail buttons can queue all available files in the safest order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(model.libraryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.metadataMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Games")
                        .font(.headline)
                    Spacer()
                    Text("\(model.libraryGames.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(14)

                if model.libraryGames.isEmpty {
                    ContentUnavailableView("No Games", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(model.libraryGames) { game in
                                LibraryGameTile(game: game) {
                                    selectedLibraryGame = game
                                } addAll: {
                                    model.addGameToQueue(game)
                                    selectedTab = .workflow
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private var rcmWorkflow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Launch RCM Payload")
                        .font(.headline)

                    Spacer()

                    RCMConnectionBadge(isConnected: model.isRCMDeviceConnected)
                }

                WorkflowStep(number: 1, title: "Choose payload", detail: "Select a .bin payload such as hekate or fusee.")
                WorkflowStep(number: 2, title: "Set RCM mode", detail: "Power the device into RCM before connecting USB.")
                WorkflowStep(number: 3, title: "Connect USB", detail: "Use a data-capable cable and keep the device in RCM.")
                WorkflowStep(number: 4, title: "Push from Mac", detail: model.rcmInstruction)

                ProgressView(value: model.progress)

                HStack {
                    Button {
                        chooseRCMPayload()
                    } label: {
                        Label("Payload", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        model.pushRCMPayload()
                    } label: {
                        Label("Push", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPushRCMPayload)
                }

                if let selectedPayloadURL = model.selectedPayloadURL {
                    Button {
                        revealInFinder(selectedPayloadURL)
                    } label: {
                        Label("Show Payload", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .frame(width: 360)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Payload")
                        .font(.headline)
                    Spacer()
                    RCMConnectionBadge(isConnected: model.isRCMDeviceConnected)
                    Text(model.selectedPayloadURL == nil ? "0" : "1")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(14)

                if let selectedPayloadURL = model.selectedPayloadURL {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(selectedPayloadURL.lastPathComponent)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .layoutPriority(1)

                        Text("-")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(selectedPayloadURL.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(14)
                    .help(selectedPayloadURL.path)
                    .contextMenu {
                        Button {
                            revealInFinder(selectedPayloadURL)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }

                        Button {
                            copyPath(selectedPayloadURL)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                    }
                } else {
                    ContentUnavailableView("No Payload", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()
            }
        }
    }

    private var fullLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Text("\(model.logs.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)

            List(model.logs) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: entry.level.symbolName)
                        .foregroundStyle(entry.level.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.caption)
                        Text(entry.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chooseInstallFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose files to install"
        panel.prompt = "Choose"
        panel.message = "Select NSP, NSZ, XCI, XCZ files, or split folders."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose output folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            model.splitMergeOutputDirectory = panel.url
        }
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose library folder"
        panel.prompt = "Choose"
        panel.message = "Select the folder that contains your NSP, NSZ, XCI, or XCZ files."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            model.setLibraryDirectory(url)
        }
    }

    private func chooseRCMPayload() {
        let panel = NSOpenPanel()
        panel.title = "Choose RCM payload"
        panel.prompt = "Choose"
        panel.message = "Select a payload .bin file to push in RCM mode."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.directoryURL = model.rcmPayloadDirectory

        if panel.runModal() == .OK, let url = panel.url {
            model.setRCMPayload(url)
        }
    }

    private func openLibraryFolder() {
        guard let url = model.libraryDirectory else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}

private enum AppTab {
    case workflow
    case library
    case rcm
    case log
}

private struct WorkflowStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LibraryTypePill: View {
    let type: LibraryContentType

    var body: some View {
        Text(type.title)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(type.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(type.tint)
    }
}

private struct LibraryGameTile: View {
    let game: LibraryGame
    let open: () -> Void
    let addAll: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            banner

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                if let logoURL = game.metadata?.logoImageURL {
                    AsyncImage(url: logoURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                        } else {
                            Text(game.metadata?.matchedTitle ?? game.title)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: 170, maxHeight: 54, alignment: .leading)
                } else {
                    Text(game.metadata?.matchedTitle ?? game.title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if !game.mainGames.isEmpty {
                        LibraryTypePill(type: .mainGame)
                    }
                    if !game.updates.isEmpty {
                        LibraryTypePill(type: .update)
                    }
                    if !game.dlcs.isEmpty {
                        LibraryTypePill(type: .dlc)
                    }
                    if !game.others.isEmpty {
                        LibraryTypePill(type: .other)
                    }

                    Spacer()

                    Button(action: addAll) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                    .help("Queue in install order")
                }
            }
            .padding(12)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: open)
        .help(game.metadata?.summary ?? game.title)
    }

    @ViewBuilder
    private var banner: some View {
        if let url = game.heroImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackBanner
                }
            }
        } else {
            fallbackBanner
        }
    }

    private var fallbackBanner: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.34), Color.accentColor.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.22))
        }
    }
}

private struct LibraryGameDetailSheet: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    let game: LibraryGame
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.left")
                }
                Spacer()
                Button(action: close) {
                    Label("Close", systemImage: "xmark")
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero

                    HStack(alignment: .top, spacing: 18) {
                        cover

                        VStack(alignment: .leading, spacing: 10) {
                            Text(game.metadata?.matchedTitle ?? game.title)
                                .font(.largeTitle.bold())
                                .lineLimit(2)

                            metadataLine

                            if let summary = game.metadata?.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No remote details cached yet. Add a TGDB key and refresh artwork to enrich this game.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    warning

                    actionButtons

                    localFiles
                }
                .padding(18)
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = game.heroImageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.22))
                    }
                }
            } else {
                Rectangle().fill(Color.gray.opacity(0.22))
            }

            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            Text(game.metadata?.matchedTitle ?? game.title)
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(18)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.18))

            if let url = game.metadata?.coverImageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 132, height: 184)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var metadataLine: some View {
        let metadata = game.metadata
        let genres = metadata?.genres.prefix(3).joined(separator: ", ") ?? ""
        let release = metadata?.releaseDate ?? ""
        if !genres.isEmpty || !release.isEmpty {
            Text([release, genres].filter { !$0.isEmpty }.joined(separator: " • "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Install order matters")
                    .font(.headline)
                Text("Install the main game first, then updates, then DLC. The Add All button queues files in that order automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                model.addGameToQueue(game, contentType: .mainGame)
            } label: {
                Label("Add Main Game", systemImage: "plus.square")
                    .frame(maxWidth: .infinity)
            }
            .disabled(game.mainGames.isEmpty)

            Button {
                model.addGameToQueue(game, contentType: .update)
            } label: {
                Label("Add Updates", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .disabled(game.updates.isEmpty)

            Button {
                model.addGameToQueue(game, contentType: .dlc)
            } label: {
                Label("Add DLC", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .disabled(game.dlcs.isEmpty)

            Button {
                model.addGameToQueue(game)
            } label: {
                Label("Add All", systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var localFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local Files")
                .font(.headline)

            ForEach(game.installOrderedItems) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.url.hasDirectoryPath ? "folder" : "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    LibraryTypePill(type: item.contentType)
                    Text(item.url.lastPathComponent)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(item.url.path)
            }
        }
    }
}

private struct MetadataSettingsSheet: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TGDB Artwork")
                .font(.title2.bold())

            Text("Paste a TheGamesDB API key to fetch banner art, covers, summaries, and release details for games found in your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("TheGamesDB API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Clear Key") {
                    apiKey = ""
                    onSave()
                }
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct RCMConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        Label(isConnected ? "RCM Connected" : "Waiting for RCM", systemImage: isConnected ? "bolt.fill" : "bolt.slash")
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((isConnected ? Color.green : Color.gray).opacity(0.14), in: Capsule())
            .foregroundStyle(isConnected ? .green : .secondary)
    }
}

private struct StatusBadge: View {
    let status: TransferStatus

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var title: String {
        switch status {
        case .idle:
            "Idle"
        case .running:
            "Sending"
        case .completed:
            "Complete"
        case .failed:
            "Needs Attention"
        }
    }

    private var icon: String {
        switch status {
        case .idle:
            "circle"
        case .running:
            "cable.connector"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    private var background: Color {
        switch status {
        case .idle:
            Color.gray.opacity(0.14)
        case .running:
            Color.blue.opacity(0.14)
        case .completed:
            Color.green.opacity(0.14)
        case .failed:
            Color.red.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch status {
        case .idle:
            .secondary
        case .running:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

private extension LibraryContentType {
    var title: String {
        switch self {
        case .mainGame:
            "Main Game"
        case .update:
            "Update"
        case .dlc:
            "DLC"
        case .other:
            "Other"
        }
    }

    var tint: Color {
        switch self {
        case .mainGame:
            .green
        case .update:
            .orange
        case .dlc:
            .cyan
        case .other:
            .secondary
        }
    }
}

private extension TransferLogLevel {
    var symbolName: String {
        switch self {
        case .info:
            "info.circle"
        case .success:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .failure:
            "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .info:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}
