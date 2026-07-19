import SwiftUI
import AppKit
import SwitchLoaderCore
import UniformTypeIdentifiers

private struct ManualMetadataMatchRequest: Identifiable {
    let game: LibraryGame
    let provider: MetadataProviderKind

    var id: String {
        "\(game.id)-\(provider.rawValue)"
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    @State private var selectedTab = AppTab.workflow
    @State private var selectedLibraryIndex = 0
    @State private var selectedLibraryGame: LibraryGame?
    @State private var manualMatchRequest: ManualMetadataMatchRequest?
    @State private var isShowingMetadataSettings = false
    @State private var metadataAPIKey = ""
    @State private var screenScraperCredentials = ScreenScraperCredentials(
        devUsername: "",
        debugPassword: "",
        softwareName: "SwitchLoader",
        memberUsername: "",
        memberPassword: ""
    )
    @State private var isShowingCustomHomebrewSheet = false
    @State private var customHomebrewURL = ""
    @State private var customHomebrewError = ""

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
            case .homebrew:
                homebrew
            case .rcm:
                rcmWorkflow
            case .log:
                fullLog
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .library {
                model.scanLibrary()
            } else if newTab == .homebrew {
                model.refreshHomebrewArchiveStatus()
            } else if newTab == .rcm {
                model.refreshRCMConnection()
            }
        }
        .sheet(item: $selectedLibraryGame) { game in
            LibraryGameDetailSheet(game: game) {
                selectedLibraryGame = nil
            }
            .environmentObject(model)
            .frame(minWidth: 960, minHeight: 720)
        }
        .sheet(item: $manualMatchRequest) { request in
            ManualMetadataMatchSheet(game: request.game, provider: request.provider)
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
        }
        .sheet(isPresented: $isShowingMetadataSettings) {
            MetadataSettingsSheet(
                apiKey: $metadataAPIKey,
                screenScraperCredentials: $screenScraperCredentials
            ) {
                model.saveTheGamesDBAPIKey(metadataAPIKey)
                model.saveScreenScraperCredentials(screenScraperCredentials)
                isShowingMetadataSettings = false
            } onCancel: {
                isShowingMetadataSettings = false
            }
            .environmentObject(model)
            .frame(width: 520)
        }
        .sheet(isPresented: $isShowingCustomHomebrewSheet) {
            CustomHomebrewSheet(
                repositoryURL: $customHomebrewURL,
                errorMessage: customHomebrewError
            ) {
                do {
                    try model.addCustomHomebrewRepository(customHomebrewURL)
                    customHomebrewURL = ""
                    customHomebrewError = ""
                    isShowingCustomHomebrewSheet = false
                } catch {
                    customHomebrewError = error.localizedDescription
                }
            } onCancel: {
                customHomebrewError = ""
                isShowingCustomHomebrewSheet = false
            }
            .frame(width: 520)
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
                Label("Homebrew", systemImage: "shippingbox").tag(AppTab.homebrew)
                Label("RCM", systemImage: "bolt.horizontal").tag(AppTab.rcm)
                Label("Log", systemImage: "list.bullet.rectangle").tag(AppTab.log)
            }
            .pickerStyle(.segmented)
            .frame(width: 470)
            .labelsHidden()

            if selectedTab == .library, !model.libraryGames.isEmpty {
                libraryJumpPicker
            }

            Spacer()
            StatusBadge(status: model.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var libraryJumpPicker: some View {
        Picker("Jump to game", selection: Binding(
            get: {
                min(selectedLibraryIndex, max(model.libraryGames.count - 1, 0))
            },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedLibraryIndex = newValue
                }
            }
        )) {
            ForEach(Array(model.libraryGames.enumerated()), id: \.element.id) { index, game in
                Text(game.metadata?.matchedTitle ?? game.title)
                    .lineLimit(1)
                    .tag(index)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 280)
        .labelsHidden()
        .help("Jump to a game in the library")
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
                    Label("Awoo/Tinfoil", systemImage: "paperplane.fill")
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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Awoo / Tinfoil")
                    .font(.subheadline.bold())

                Text("Use this tab with an existing USB installer. SwitchLoader Receiver is now for Homebrew folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    metadataAPIKey = model.loadTheGamesDBAPIKeyForEditing()
                    screenScraperCredentials = model.loadScreenScraperSettingsForEditing()
                    isShowingMetadataSettings = true
                } label: {
                    Label(model.hasAnyMetadataProvider ? "Metadata Connected" : "Metadata", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.refreshLibraryMetadata()
                } label: {
                    Label(model.isFetchingMetadata ? "Fetching New Art" : "Fetch New Art", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.hasAnyMetadataProvider || model.libraryGames.isEmpty || model.isFetchingMetadata)

                if model.isFetchingMetadata {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            ProgressView(value: model.metadataProgress)
                                .controlSize(.small)
                            Text("\(Int((model.metadataProgress * 100).rounded()))%")
                                .font(.caption2.bold())
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }

                        Text(model.metadataStatusDetail.isEmpty ? model.metadataMessage : model.metadataStatusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }

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
                if model.libraryGames.isEmpty {
                    ContentUnavailableView("No Games", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let index = min(selectedLibraryIndex, model.libraryGames.count - 1)
                    let game = model.libraryGames[index]

                    LibraryFeaturedGamePanel(
                        game: game,
                        index: index,
                        count: model.libraryGames.count,
                        previous: { showPreviousLibraryGame() },
                        next: { showNextLibraryGame() },
                        open: { selectedLibraryGame = game },
                        addAll: {
                            model.addGameToQueue(game)
                            selectedTab = .workflow
                        },
                        addMain: { model.addGameToQueue(game, contentType: .mainGame) },
                        addUpdates: { model.addGameToQueue(game, contentType: .update) },
                        addDLC: { model.addGameToQueue(game, contentType: .dlc) },
                        manualMatch: { provider in
                            manualMatchRequest = ManualMetadataMatchRequest(game: game, provider: provider)
                        }
                    )
                    .id(game.id)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: model.libraryGames.count) { _, count in
                        if count == 0 {
                            selectedLibraryIndex = 0
                        } else if selectedLibraryIndex >= count {
                            selectedLibraryIndex = count - 1
                        }
                    }
                }
            }
        }
    }

    private func showPreviousLibraryGame() {
        guard !model.libraryGames.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedLibraryIndex = (selectedLibraryIndex - 1 + model.libraryGames.count) % model.libraryGames.count
        }
    }

    private func showNextLibraryGame() {
        guard !model.libraryGames.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedLibraryIndex = (selectedLibraryIndex + 1) % model.libraryGames.count
        }
    }

    private var homebrew: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Homebrew")
                    .font(.headline)

                Text(model.homebrewArchiveDirectory?.path ?? "No HomebrewApps archive selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Button {
                        chooseHomebrewArchiveFolder()
                    } label: {
                        Label("Archive", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        openHomebrewArchiveFolder()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .frame(width: 28)
                    }
                    .disabled(model.homebrewArchiveDirectory == nil)
                    .help("Open archive folder")
                }

                Button {
                    isShowingCustomHomebrewSheet = true
                } label: {
                    Label("Add GitHub", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.refreshHomebrewArchiveStatus()
                } label: {
                    Label("Refresh Ready", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.homebrewArchiveDirectory == nil)

                Button {
                    model.downloadSelectedHomebrew()
                } label: {
                    Label("Download Selected", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.homebrewArchiveDirectory == nil || model.selectedHomebrewEntryIDs.isEmpty)

                Button {
                    chooseHomebrewGenerateFolder()
                } label: {
                    Label(model.isGeneratingHomebrewFolder ? "Generating" : "Generate Folder", systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isGeneratingHomebrewFolder || model.selectedHomebrewEntryIDs.isEmpty)

                if let generatedHomebrewFolderURL = model.generatedHomebrewFolderURL {
                    Button {
                        revealInFinder(generatedHomebrewFolderURL)
                    } label: {
                        Label("Show Generated", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        model.sendGeneratedHomebrewFolderToReceiver()
                    } label: {
                        Label("Install to Switch", systemImage: "cable.connector")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSendGeneratedHomebrewFolderToReceiver)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Only download homebrew you trust.", systemImage: "checkmark.shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text("SwitchLoader pulls release assets from each GitHub repo and assembles selected apps into a ready folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(model.homebrewMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Homebrew Library")
                        .font(.headline)
                    Spacer()
                    Text("\(model.downloadedHomebrewEntryIDs.count)/\(model.homebrewCatalog.count) ready")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(14)

                List {
                    ForEach(model.homebrewCatalog) { entry in
                        HomebrewCatalogRow(
                            entry: entry,
                            isSelected: model.selectedHomebrewEntryIDs.contains(entry.id),
                            isDownloaded: model.downloadedHomebrewEntryIDs.contains(entry.id),
                            isDownloading: model.downloadingHomebrewEntryIDs.contains(entry.id)
                        ) { isSelected in
                            model.setHomebrewSelection(entry, isSelected: isSelected)
                        } download: {
                            model.downloadHomebrew(entry)
                        } remove: {
                            model.removeCustomHomebrewEntry(entry)
                        }
                    }
                }
                .listStyle(.inset)
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

    private func chooseHomebrewArchiveFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose or create HomebrewApps archive"
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder SwitchLoader should use to store downloaded homebrew apps."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = model.homebrewArchiveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            model.setHomebrewArchiveDirectory(url)
        }
    }

    private func chooseHomebrewGenerateFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to generate the Homebrew folder"
        panel.prompt = "Generate Here"
        panel.message = "SwitchLoader will create a new ready-to-copy Homebrew folder inside this location."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = model.generatedHomebrewFolderURL?.deletingLastPathComponent() ?? model.homebrewArchiveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            model.generateHomebrewFolder(in: url)
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

    private func openHomebrewArchiveFolder() {
        guard let url = model.homebrewArchiveDirectory else { return }
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
    case homebrew
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
    var compact = false

    var body: some View {
        Text(compact ? type.shortTitle : type.title)
            .font(.caption2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 3)
            .frame(minWidth: compact ? 31 : nil)
            .background(type.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(type.tint)
            .help(type.title)
    }
}

private struct LibraryFeaturedGamePanel: View {
    let game: LibraryGame
    let index: Int
    let count: Int
    let previous: () -> Void
    let next: () -> Void
    let open: () -> Void
    let addAll: () -> Void
    let addMain: () -> Void
    let addUpdates: () -> Void
    let addDLC: () -> Void
    let manualMatch: (MetadataProviderKind) -> Void
    @State private var activeTrailer: YouTubeTrailer?

    private var displayTitle: String {
        game.metadata?.matchedTitle ?? game.title
    }

    private var summary: String {
        let text = game.metadata?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "No synopsis is cached yet. Fetch artwork/details or use Manual Match to fill in the library panel." : text
    }

    private var badgeValues: [String] {
        let metadata = game.metadata
        return [
            metadata?.platformName ?? "Nintendo Switch",
            metadata?.releaseDate,
            metadata?.genres.prefix(2).joined(separator: ", "),
            metadata?.rating
        ].compactMap { value in
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topTrailing) {
                backdrop(size: size)

                LinearGradient(
                    colors: [
                        .black.opacity(0.64),
                        .black.opacity(0.36),
                        .black.opacity(0.16)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.18), .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                content(size: size)
                    .frame(width: size.width, height: size.height, alignment: .leading)

                navigation
                    .padding(.top, 22)
                    .padding(.horizontal, 24)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .sheet(item: $activeTrailer) { trailer in
            TrailerPlayerSheet(trailer: trailer)
        }
    }

    private func content(size: CGSize) -> some View {
        let isCompact = size.width < 960 || size.height < 700
        let hasSideDetails = size.width >= 1160 && !isCompact
        let posterWidth = isCompact ? 150.0 : 218.0

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
                HStack(alignment: .top, spacing: isCompact ? 18 : 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        poster
                            .frame(width: posterWidth, height: posterWidth * 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.18))
                            }
                            .shadow(color: .black.opacity(0.48), radius: 24, y: 12)

                        if !isCompact {
                            localFileSummary
                                .frame(width: posterWidth)
                        }
                    }

                    VStack(alignment: .leading, spacing: isCompact ? 11 : 15) {
                        titleArtwork
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .top, spacing: 14) {
                            Text(displayTitle)
                                .font(.system(size: isCompact ? 28 : 38, weight: .heavy, design: .rounded))
                                .lineLimit(2)
                                .minimumScaleFactor(0.58)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                trailerButton
                                gamesDatabaseLink
                            }
                        }

                        badgeRow
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()

                        Text(summary)
                            .font(isCompact ? .caption : .callout)
                            .lineSpacing(4)
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(isCompact ? 4 : 7)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        typeRow
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()

                        actionRow
                            .padding(.top, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()

                        detailGrid(columns: hasSideDetails ? 3 : 2)
                            .padding(.top, isCompact ? 0 : 4)

                        if isCompact {
                            localPreview
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if hasSideDetails {
                        VStack(alignment: .leading, spacing: 12) {
                            creditsPanel
                            localPreview
                            trailerLink
                        }
                        .frame(width: 280, alignment: .topLeading)
                    }
                }

                if !isCompact {
                    mediaStrip
                }
            }
            .padding(.top, isCompact ? 58 : 76)
            .padding(.horizontal, isCompact ? 24 : 36)
            .padding(.bottom, isCompact ? 20 : 28)
            .frame(maxWidth: .infinity, minHeight: size.height, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Text("\(index + 1) / \(count)")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.34), in: Capsule())

            HStack(spacing: 8) {
                Button(action: previous) {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(.black.opacity(0.42), in: Circle())
                .help("Previous game")

                Button(action: next) {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(.black.opacity(0.42), in: Circle())
                .help("Next game")
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            ForEach(badgeValues.prefix(4), id: \.self) { value in
                Text(value)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    private var typeRow: some View {
        HStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        if let url = game.heroImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    fallbackBackdrop
                        .frame(width: size.width, height: size.height)
                }
            }
        } else {
            fallbackBackdrop
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = game.posterImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackPoster
                }
            }
        } else {
            fallbackPoster
        }
    }

    private var fallbackBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.07),
                    Color(red: 0.15, green: 0.18, blue: 0.20),
                    Color(red: 0.03, green: 0.03, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 190))
                .foregroundStyle(.white.opacity(0.05))
                .offset(x: 280, y: -70)
        }
    }

    private var fallbackPoster: some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.36), Color.accentColor.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.20))
            Text(game.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .padding(18)
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primaryActions
            }

            HStack(spacing: 8) {
                Button(action: addAll) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Add all files")

                Button(action: open) {
                    Image(systemName: "info.circle")
                }
                .help("Details")

                sourceMatchButtons(compact: true)

                addPartMenu
                    .labelStyle(.iconOnly)
                    .help("Add part")
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var primaryActions: some View {
        Button(action: addAll) {
            Label("Add All", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)

        Button(action: open) {
            Label("Details", systemImage: "info.circle")
        }

        sourceMatchButtons(compact: false)

        addPartMenu
    }

    private func sourceMatchButtons(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(MetadataProviderKind.allCases) { provider in
                sourceMatchButton(provider: provider, compact: compact)
            }
        }
    }

    private func sourceMatchButton(provider: MetadataProviderKind, compact: Bool) -> some View {
        let isMatched = game.hasMetadata(from: provider)
        return Button {
            manualMatch(provider)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isMatched ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(compact ? .caption : .body)
                if !compact || provider == .theGamesDB {
                    Text(provider.title)
                        .lineLimit(1)
                }
            }
            .font(compact ? .caption.bold() : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 6 : 7)
            .background((isMatched ? Color.green : Color.red).opacity(isMatched ? 0.48 : 0.56), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.14))
            }
        }
        .buttonStyle(.plain)
        .help("\(isMatched ? "Fix" : "Set") \(provider.title) match")
    }

    private var addPartMenu: some View {
        Menu {
            Button("Main Game", action: addMain)
                .disabled(game.mainGames.isEmpty)
            Button("Updates", action: addUpdates)
                .disabled(game.updates.isEmpty)
            Button("DLC", action: addDLC)
                .disabled(game.dlcs.isEmpty)
        } label: {
            Label("Add Part", systemImage: "list.bullet")
        }
    }

    @ViewBuilder
    private var titleArtwork: some View {
        if let url = game.metadata?.logoImageURL ?? game.metadata?.bannerImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: 420, maxHeight: 92, alignment: .leading)
            .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
        }
    }

    @ViewBuilder
    private var trailerButton: some View {
        if let trailer = trailer {
            Button {
                activeTrailer = trailer
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.caption.bold())
                    Text("Trailer")
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.red.opacity(0.52), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.14))
                }
            }
            .buttonStyle(.plain)
            .help("Watch trailer")
        }
    }

    private var trailer: YouTubeTrailer? {
        guard let url = game.metadata?.youtubeURL else { return nil }
        return YouTubeTrailer(title: "\(displayTitle) Trailer", url: url)
    }

    @ViewBuilder
    private var gamesDatabaseLink: some View {
        if let link = gamesDatabaseLinkDetails {
            Link(destination: link.url) {
                HStack(spacing: 7) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.caption.bold())
                    Text(link.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.44), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.12))
                }
            }
            .buttonStyle(.plain)
            .help("Open this game on \(link.title)")
        }
    }

    private var detailRows: [(label: String, value: String)] {
        let metadata = game.metadata
        return [
            ("Genres", joined(metadata?.genres, limit: 4))
        ].compactMap { row in
            guard let value = row.1 else { return nil }
            return (row.0, value)
        }
    }

    private var creditRows: [(label: String, value: String)] {
        let metadata = game.metadata
        return [
            ("Developer", joined(metadata?.developers, limit: 3)),
            ("Publisher", joined(metadata?.publishers, limit: 3))
        ].compactMap { row in
            guard let value = cleaned(row.1) else { return nil }
            return (row.0, value)
        }
    }

    private var gamesDatabaseLinkDetails: (title: String, url: URL)? {
        guard let metadata = game.metadata else { return nil }

        if metadata.provider == "ScreenScraper",
           let gameID = metadata.providerID.split(separator: ":").first,
           let url = URL(string: "https://www.screenscraper.fr/gameinfos.php?gameid=\(gameID)") {
            return ("ScreenScraper", url)
        }

        guard let id = cleaned(metadata.providerID),
              let url = URL(string: "https://thegamesdb.net/game.php?id=\(id)")
        else {
            return nil
        }
        return ("TheGamesDB", url)
    }

    private var fileCountRows: [(type: LibraryContentType, count: Int, size: UInt64)] {
        [
            (.mainGame, game.mainGames),
            (.update, game.updates),
            (.dlc, game.dlcs),
            (.other, game.others)
        ].compactMap { type, items in
            guard !items.isEmpty else { return nil }
            return (type, items.count, totalSize(for: items))
        }
    }

    private var totalInstallSize: UInt64 {
        totalSize(for: game.installOrderedItems)
    }

    private func totalSize(for items: [LibraryItem]) -> UInt64 {
        items.reduce(UInt64(0)) { $0 + $1.size }
    }

    private func formattedSize(_ size: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(size, UInt64(Int64.max))),
            countStyle: .file
        )
    }

    private func formattedFileSummary(count: Int, size: UInt64) -> String {
        "\(count) • \(formattedSize(size))"
    }

    private var mediaURLs: [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []

        func append(_ url: URL?) {
            guard let url, !seen.contains(url) else { return }
            seen.insert(url)
            urls.append(url)
        }

        append(game.metadata?.logoImageURL)
        append(game.metadata?.bannerImageURL)
        append(game.metadata?.artworkImageURL)
        append(game.metadata?.coverImageURL)
        game.metadata?.screenshotImageURLs.forEach { append($0) }
        return urls
    }

    private func detailGrid(columns: Int) -> some View {
        let rows = columns < 3 ? detailRows + Array(creditRows.prefix(2)) : detailRows
        let gridColumns = Array(repeating: GridItem(.flexible(minimum: 118), spacing: 10), count: columns)

        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                infoTile(label: row.label, value: row.value)
            }
        }
    }

    private func infoTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)

            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 54, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    private var creditsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.72))

            if creditRows.isEmpty {
                Text("No studio or publisher details cached yet.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(creditRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.48))
                        Text(row.value)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    @ViewBuilder
    private var trailerLink: some View {
        if let trailer = trailer {
            Button {
                activeTrailer = trailer
            } label: {
                Label("Watch Trailer", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var localFileSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(game.installOrderedItems.count) install item\(game.installOrderedItems.count == 1 ? "" : "s") • \(formattedSize(totalInstallSize))")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            ForEach(Array(fileCountRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    LibraryTypePill(type: row.type, compact: true)
                    Text(formattedFileSummary(count: row.count, size: row.size))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    @ViewBuilder
    private var mediaStrip: some View {
        let urls = mediaURLs
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Media")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.70))
                    Text("\(urls.count) image\(urls.count == 1 ? "" : "s")")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.44))
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(urls.prefix(10)), id: \.self) { url in
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Rectangle()
                                        .fill(.white.opacity(0.08))
                                        .overlay {
                                            Image(systemName: "photo")
                                                .foregroundStyle(.white.opacity(0.28))
                                        }
                                }
                            }
                            .frame(width: 190, height: 106)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.10))
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.07))
            }
        }
    }

    private var localPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(game.installOrderedItems.count) local file\(game.installOrderedItems.count == 1 ? "" : "s") • \(formattedSize(totalInstallSize))")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.72))

            ForEach(game.installOrderedItems) { item in
                HStack(spacing: 8) {
                    LibraryTypePill(type: item.contentType, compact: true)
                    Text(item.url.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 8)
                    Text(formattedSize(item.size))
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.54))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    private func cleaned(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func joined(_ values: [String]?, limit: Int) -> String? {
        let cleanedValues = Array((values ?? [])
            .compactMap { cleaned($0) }
            .prefix(limit))
        let text = cleanedValues.joined(separator: ", ")
        return text.isEmpty ? nil : text
    }
}

private struct HorizontalWheelScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WheelDrivenHorizontalScrollView {
        let scrollView = WheelDrivenHorizontalScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = []
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: WheelDrivenHorizontalScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        context.coordinator.hostingView?.invalidateIntrinsicContentSize()
        scrollView.needsLayout = true
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

private final class WheelDrivenHorizontalScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }

        let fittingSize = documentView.fittingSize
        let visibleSize = contentView.bounds.size
        let width = max(fittingSize.width, visibleSize.width)
        let height = max(fittingSize.height, visibleSize.height)
        documentView.setFrameSize(NSSize(width: width, height: height))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let documentView else {
            super.scrollWheel(with: event)
            return
        }

        let horizontalDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : -event.scrollingDeltaY
        let maxX = max(0, documentView.bounds.width - contentView.bounds.width)
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x + horizontalDelta, 0), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

private struct LibraryGamePoster: View {
    let game: LibraryGame
    let open: () -> Void
    let addAll: () -> Void
    let manualMatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                poster

                LinearGradient(
                    colors: [.clear, .black.opacity(0.46)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 8) {
                    if game.metadata == nil {
                        Button(action: manualMatch) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white)
                        .help("Manual match artwork/details")
                    }

                    Button(action: addAll) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                    .help("Queue in install order")
                }
                .padding(9)
            }
            .frame(width: 152, height: 228)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14))
            }
            .shadow(color: .black.opacity(0.26), radius: 10, y: 5)

            Text(game.metadata?.matchedTitle ?? game.title)
                .font(.callout.bold())
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(width: 152, alignment: .leading)

            HStack(spacing: 5) {
                if !game.mainGames.isEmpty {
                    LibraryTypePill(type: .mainGame, compact: true)
                }
                if !game.updates.isEmpty {
                    LibraryTypePill(type: .update, compact: true)
                }
                if !game.dlcs.isEmpty {
                    LibraryTypePill(type: .dlc, compact: true)
                }
                if !game.others.isEmpty {
                    LibraryTypePill(type: .other, compact: true)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 152)
        }
        .frame(width: 152, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: open)
        .help(game.metadata?.summary ?? game.title)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = game.posterImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackPoster
                }
            }
        } else {
            fallbackPoster
        }
    }

    private var fallbackPoster: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.34), Color.accentColor.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.20))
            Text(game.title)
                .font(.headline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(14)
                .foregroundStyle(.white.opacity(0.84))

            if game.metadata == nil {
                VStack {
                    Spacer()
                    Text("Manual Match")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.28), in: Capsule())
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.bottom, 38)
            }
        }
    }
}

private struct HomebrewCatalogRow: View {
    let entry: HomebrewCatalogEntry
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let select: (Bool) -> Void
    let download: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                select(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
            }
            .buttonStyle(.borderless)
            .help(isSelected ? "Untick" : "Tick")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    Text(entry.category.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(entry.category.tint.opacity(0.14), in: Capsule())
                        .foregroundStyle(entry.category.tint)

                    if !entry.isBuiltIn {
                        Text("Custom")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Link(destination: entry.repositoryURL) {
                        Label(entry.repositoryName, systemImage: "link")
                            .font(.caption)
                    }

                    if isDownloaded {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Downloaded", systemImage: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            Button {
                download()
            } label: {
                Label(isDownloading ? "Downloading" : "Download", systemImage: isDownloaded ? "arrow.clockwise" : "icloud.and.arrow.down")
            }
            .disabled(isDownloading)

            if !entry.isBuiltIn {
                Button(role: .destructive) {
                    remove()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove custom repo")
            }
        }
        .padding(.vertical, 6)
        .help(entry.repositoryURL.absoluteString)
        .contextMenu {
            Link(destination: entry.repositoryURL) {
                Label("Open GitHub", systemImage: "link")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.repositoryURL.absoluteString, forType: .string)
            } label: {
                Label("Copy GitHub Link", systemImage: "doc.on.doc")
            }
        }
    }
}

private struct LibraryGameDetailSheet: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    @State private var manualMatchProvider: MetadataProviderKind?
    let game: LibraryGame
    let close: () -> Void

    private var currentGame: LibraryGame {
        model.libraryGames.first(where: { $0.id == game.id }) ?? game
    }

    var body: some View {
        let game = currentGame

        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.left")
                }
                Text("Game Details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(MetadataProviderKind.allCases) { provider in
                        Button {
                            manualMatchProvider = provider
                        } label: {
                            Label(provider.title, systemImage: game.hasMetadata(from: provider) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                        .tint(game.hasMetadata(from: provider) ? .green : .red)
                    }
                }
                Button(action: close) {
                    Label("Close", systemImage: "xmark")
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero(game)

                    HStack(alignment: .top, spacing: 24) {
                        cover(game)

                        VStack(alignment: .leading, spacing: 14) {
                            Text(game.metadata?.matchedTitle ?? game.title)
                                .font(.largeTitle.bold())
                                .lineLimit(2)

                            metadataBadges(game)

                            if let summary = game.metadata?.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("No remote details cached yet.")
                                        .font(.title3.bold())
                                    Text("Use Manual Match to pick the correct Nintendo Switch entry and save artwork/details for this game.")
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        ForEach(MetadataProviderKind.allCases) { provider in
                                            Button {
                                                manualMatchProvider = provider
                                            } label: {
                                                Label(provider.matchTitle, systemImage: game.hasMetadata(from: provider) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(game.hasMetadata(from: provider) ? .green : .red)
                                        }
                                    }
                                }
                                .font(.body)
                                .foregroundStyle(.secondary)
                            }

                            actionButtons(game)
                        }
                    }

                    infoSections(game)

                    warning
                    localFiles(game)
                }
                .padding(24)
            }
        }
        .sheet(item: $manualMatchProvider) { provider in
            ManualMetadataMatchSheet(game: currentGame, provider: provider)
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    private func hero(_ game: LibraryGame) -> some View {
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
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .padding(22)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cover(_ game: LibraryGame) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        .frame(width: 190, height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        }
    }

    @ViewBuilder
    private func metadataBadges(_ game: LibraryGame) -> some View {
        let metadata = game.metadata
        let values = [
            metadata?.platformName,
            metadata?.releaseDate,
            metadata?.genres.prefix(3).joined(separator: ", "),
            metadata?.rating
        ].compactMap { value in
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }

        if !values.isEmpty {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.gray.opacity(0.16), in: Capsule())
                }
            }
        }
    }

    private func infoSections(_ game: LibraryGame) -> some View {
        let metadata = game.metadata

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DetailInfoSection(title: "Details") {
                    DetailInfoRow(label: "Platform", value: metadata?.platformName ?? "Nintendo Switch")
                    DetailInfoRow(label: "Release", value: metadata?.releaseDate)
                    DetailInfoRow(label: "Rating", value: metadata?.rating)
                    DetailInfoRow(label: "Players", value: metadata?.players)
                    DetailInfoRow(label: "Co-op", value: metadata?.coop)
                    DetailInfoRow(label: "Provider", value: metadata.map { "\($0.provider) #\($0.providerID)" })
                }

                DetailInfoSection(title: "Credits") {
                    DetailInfoRow(label: "Developer", value: metadata?.developers.joined(separator: ", "))
                    DetailInfoRow(label: "Publisher", value: metadata?.publishers.joined(separator: ", "))
                    DetailInfoRow(label: "Genres", value: metadata?.genres.joined(separator: ", "))
                    DetailInfoRow(label: "Aliases", value: metadata?.aliases?.joined(separator: ", "))
                }
            }

            if let youtubeURL = metadata?.youtubeURL ?? nil {
                Link(destination: youtubeURL) {
                    Label("Open trailer", systemImage: "play.rectangle")
                }
            }

            if let screenshots = metadata?.screenshotImageURLs, !screenshots.isEmpty {
                DetailInfoSection(title: "Media") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(screenshots.prefix(8), id: \.self) { url in
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Rectangle().fill(Color.gray.opacity(0.18))
                                    }
                                }
                                .frame(width: 190, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
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

    private func actionButtons(_ game: LibraryGame) -> some View {
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

    private func localFiles(_ game: LibraryGame) -> some View {
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

private struct DetailInfoSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailInfoRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ManualMetadataMatchSheet: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    @Environment(\.dismiss) private var dismiss
    let game: LibraryGame
    let provider: MetadataProviderKind
    @State private var query: String
    @State private var matches: [GameMetadataMatch] = []
    @State private var message = ""
    @State private var isSearching = false
    @State private var isApplying = false
    @State private var searchTask: Task<Void, Never>?

    init(game: LibraryGame, provider: MetadataProviderKind) {
        self.game = game
        self.provider = provider
        _query = State(initialValue: game.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.matchTitle)
                        .font(.title2.bold())
                    Text("Search \(provider.title) Nintendo Switch entries and save the correct artwork/details for \(game.title).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }

            HStack(spacing: 10) {
                TextField("Search title", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        startSearch()
                    }
                Button {
                    if isSearching {
                        cancelSearch()
                    } else {
                        startSearch()
                    }
                } label: {
                    Label(isSearching ? "Cancel" : "Search", systemImage: isSearching ? "xmark.circle" : "magnifyingglass")
                }
                .disabled(!isSearching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(matches) { match in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(match.title)
                                    .font(.headline)
                                Text([match.platformName, match.releaseDate, match.genres.prefix(3).joined(separator: ", ")]
                                    .compactMap { value in
                                        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                        return text.isEmpty ? nil : text
                                    }
                                    .joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let summary = match.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await apply(match) }
                            } label: {
                                Label("Use", systemImage: "checkmark.circle")
                            }
                            .disabled(isApplying)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            if message.isEmpty {
                message = "Search \(provider.title) when you are ready."
            }
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    private func startSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            await search()
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        message = "Search cancelled."
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        message = "Searching \(provider.title) Nintendo Switch matches..."
        defer {
            isSearching = false
            searchTask = nil
        }
        do {
            matches = try await model.searchMetadataMatches(for: trimmed, provider: provider)
            guard !Task.isCancelled else { return }
            message = matches.isEmpty ? "No \(provider.title) Nintendo Switch matches found. Try a shorter title." : "Found \(matches.count) \(provider.title) Nintendo Switch match\(matches.count == 1 ? "" : "es")."
        } catch {
            guard !Task.isCancelled else {
                message = "Search cancelled."
                return
            }
            message = error.localizedDescription
        }
    }

    private func apply(_ match: GameMetadataMatch) async {
        isApplying = true
        message = "Saving \(match.title)..."
        do {
            try await model.applyMetadataMatch(match, to: game, provider: provider)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
        isApplying = false
    }
}

private struct MetadataSettingsSheet: View {
    @EnvironmentObject private var model: SwitchLoaderModel
    @Binding var apiKey: String
    @Binding var screenScraperCredentials: ScreenScraperCredentials
    @State private var activeMetadataTest: MetadataProviderTest?
    @State private var testResult: MetadataTestResult?
    @State private var isShowingScreenScraperAdvanced = false
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Metadata Artwork")
                .font(.title2.bold())

            Text("Add TheGamesDB or ScreenScraper details to fetch cleaner artwork, fanart, summaries, and game details for your library. Saved credentials stay in SwitchLoader's local settings file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("TheGamesDB") {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        testTheGamesDB()
                    } label: {
                        Label(activeMetadataTest == .theGamesDB ? "Testing" : "Test TheGamesDB", systemImage: "checkmark.circle")
                    }
                    .disabled(activeMetadataTest != nil)
                }
                .padding(.top, 4)
            }

            GroupBox("ScreenScraper") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Username", text: $screenScraperCredentials.memberUsername)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $screenScraperCredentials.memberPassword)
                        .textFieldStyle(.roundedBorder)
                    Text("Use your ScreenScraper account password here. If the test says user identifiers failed, try the Password shown on your ScreenScraper account/API page, not the Debug Password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        testScreenScraper()
                    } label: {
                        Label(activeMetadataTest == .screenScraper ? "Testing" : "Test ScreenScraper", systemImage: "checkmark.circle")
                    }
                    .disabled(activeMetadataTest != nil)

                    DisclosureGroup("Advanced app credentials", isExpanded: $isShowingScreenScraperAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Most apps hide these because they ship with their own ScreenScraper app credentials. SwitchLoader keeps them in its local settings file for this development build.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            TextField("Dev username", text: $screenScraperCredentials.devUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Debug password", text: $screenScraperCredentials.debugPassword)
                                .textFieldStyle(.roundedBorder)
                            TextField("Software name", text: $screenScraperCredentials.softwareName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 4)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Clear All") {
                    apiKey = ""
                    screenScraperCredentials = ScreenScraperCredentials(
                        devUsername: "",
                        debugPassword: "",
                        softwareName: "SwitchLoader",
                        memberUsername: "",
                        memberPassword: ""
                    )
                    onSave()
                }
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .alert(item: $testResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func testTheGamesDB() {
        activeMetadataTest = .theGamesDB
        Task {
            do {
                let message = try await model.testTheGamesDBAPIKey(apiKey)
                await MainActor.run {
                    testResult = MetadataTestResult(title: "TheGamesDB Test Passed", message: message)
                    activeMetadataTest = nil
                }
            } catch {
                await MainActor.run {
                    testResult = MetadataTestResult(title: "TheGamesDB Test Failed", message: error.localizedDescription)
                    activeMetadataTest = nil
                }
            }
        }
    }

    private func testScreenScraper() {
        activeMetadataTest = .screenScraper
        Task {
            do {
                let message = try await model.testScreenScraperCredentials(screenScraperCredentials)
                await MainActor.run {
                    testResult = MetadataTestResult(title: "ScreenScraper Test Passed", message: message)
                    activeMetadataTest = nil
                }
            } catch {
                await MainActor.run {
                    testResult = MetadataTestResult(title: "ScreenScraper Test Failed", message: error.localizedDescription)
                    activeMetadataTest = nil
                }
            }
        }
    }
}

private enum MetadataProviderTest {
    case theGamesDB
    case screenScraper
}

private struct MetadataTestResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct CustomHomebrewSheet: View {
    @Binding var repositoryURL: String
    let errorMessage: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add GitHub Homebrew")
                .font(.title2.bold())

            Text("Paste a public GitHub repository link. SwitchLoader will use its latest release assets when downloading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://github.com/owner/repo", text: $repositoryURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)

            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Add") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    var shortTitle: String {
        switch self {
        case .mainGame:
            "Base"
        case .update:
            "Upd"
        case .dlc:
            "DLC"
        case .other:
            "More"
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

private extension HomebrewCategory {
    var tint: Color {
        switch self {
        case .launcher:
            .blue
        case .files:
            .teal
        case .saves:
            .green
        case .media:
            .purple
        case .utility:
            .orange
        case .overlay:
            .cyan
        case .sysmodule:
            .red
        case .modding:
            .pink
        case .development:
            .indigo
        case .custom:
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
