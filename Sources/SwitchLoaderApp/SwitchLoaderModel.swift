import Foundation
import SwitchLoaderCore

enum LibraryContentType: Hashable, Sendable {
    case mainGame
    case update
    case dlc
    case other

    var sortRank: Int {
        switch self {
        case .mainGame:
            0
        case .update:
            1
        case .dlc:
            2
        case .other:
            3
        }
    }
}

struct LibraryItem: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let contentType: LibraryContentType

    var id: URL {
        url
    }
}

@MainActor
final class SwitchLoaderModel: ObservableObject {
    @Published var selectedFiles: [URL] = []
    @Published var status: TransferStatus = .idle
    @Published var progress = 0.0
    @Published var logs: [TransferLogEntry] = []
    @Published var splitMergeOutputDirectory: URL?
    @Published var lastOutputURL: URL?
    @Published var libraryDirectory: URL?
    @Published var libraryItems: [LibraryItem] = []
    @Published var isScanningLibrary = false
    @Published var libraryMessage = "Choose your NSP/XCI folder to build the library."
    @Published var currentInstruction = "Choose XCI, NSP, NSZ, or a split folder to install."
    @Published var selectedPayloadURL: URL?
    @Published var rcmInstruction = "Choose a payload .bin file to push over RCM."

    private static let libraryDirectoryDefaultsKey = "SwitchLoader.libraryDirectory"
    private nonisolated static let libraryFileExtensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]
    private nonisolated static let libraryFolderTypes: [String: LibraryContentType] = [
        "main game": .mainGame,
        "base": .mainGame,
        "game": .mainGame,
        "update": .update,
        "updates": .update,
        "dlc": .dlc,
        "dlcs": .dlc
    ]

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.libraryDirectoryDefaultsKey), !path.isEmpty {
            libraryDirectory = URL(fileURLWithPath: path, isDirectory: true)
            libraryMessage = "Library ready to scan."
        }
    }

    var canStartUSBInstall: Bool {
        !selectedFiles.isEmpty && status != .running
    }

    var canPushRCMPayload: Bool {
        selectedPayloadURL != nil && status != .running
    }

    func addFiles(_ urls: [URL]) {
        let merged = selectedFiles + urls
        selectedFiles = Array(NSOrderedSet(array: merged).compactMap { $0 as? URL })
        currentInstruction = "Open your installer on the device, choose USB install, then connect the cable."
        appendLog("Added \(urls.count) item\(urls.count == 1 ? "" : "s").", .info)
    }

    func setLibraryDirectory(_ url: URL) {
        libraryDirectory = url
        UserDefaults.standard.set(url.path, forKey: Self.libraryDirectoryDefaultsKey)
        appendLog("Library folder set to \(url.path).", .info)
        scanLibrary()
    }

    func scanLibrary() {
        guard let libraryDirectory else {
            libraryItems = []
            libraryMessage = "Choose your NSP/XCI folder to build the library."
            return
        }

        isScanningLibrary = true
        libraryMessage = "Scanning library..."

        Task.detached(priority: .userInitiated) { [libraryDirectory] in
            do {
                let items = try Self.scanLibraryItems(in: libraryDirectory)
                await MainActor.run {
                    self.libraryItems = items
                    self.isScanningLibrary = false
                    self.libraryMessage = items.isEmpty ? "No install files found in this folder." : "Found \(items.count) item\(items.count == 1 ? "" : "s")."
                    self.appendLog("Library scan found \(items.count) item\(items.count == 1 ? "" : "s").", .success)
                }
            } catch {
                await MainActor.run {
                    self.libraryItems = []
                    self.isScanningLibrary = false
                    self.libraryMessage = error.localizedDescription
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func addLibraryToQueue() {
        addFiles(libraryItems.map(\.url))
    }

    func setRCMPayload(_ url: URL) {
        selectedPayloadURL = url
        rcmInstruction = "Put the Switch into RCM, connect USB, then push."
        appendLog("Selected RCM payload \(url.lastPathComponent).", .info)
    }

    func removeFiles(at offsets: IndexSet) {
        selectedFiles.remove(atOffsets: offsets)
        if selectedFiles.isEmpty {
            currentInstruction = "Choose XCI, NSP, NSZ, or a split folder to install."
        }
    }

    func clearFiles() {
        selectedFiles.removeAll()
        progress = 0
        currentInstruction = "Choose XCI, NSP, NSZ, or a split folder to install."
        appendLog("Cleared selected files.", .info)
    }

    func startUSBInstall() {
        guard canStartUSBInstall else { return }

        let configuration = USBInstallConfiguration(files: selectedFiles)
        status = .running
        progress = 0
        currentInstruction = "Keep the device connected and waiting. Sending starts when it asks for files."
        appendLog("Starting USB install.", .info)

        Task.detached(priority: .userInitiated) {
            let installer = TinfoilUSBInstaller()
            do {
                try installer.install(configuration: configuration) { event in
                    Task { @MainActor in
                        self.handleUSBEvent(event)
                    }
                }
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1
                    self.currentInstruction = "USB install complete."
                    self.appendLog("USB install finished.", .success)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.currentInstruction = "Fix the issue below, set the device waiting again, then send."
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func pushRCMPayload() {
        guard canPushRCMPayload, let payloadURL = selectedPayloadURL else { return }

        status = .running
        progress = 0
        rcmInstruction = "Keep the Switch connected in RCM while the payload is pushed."
        appendLog("Starting RCM payload push.", .info)

        Task.detached(priority: .userInitiated) {
            let launcher = RCMPayloadLauncher()
            do {
                try launcher.launch(payloadURL: payloadURL) { event in
                    Task { @MainActor in
                        self.handleRCMEvent(event)
                    }
                }
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1
                    self.rcmInstruction = "RCM payload launched."
                    self.appendLog("RCM payload push finished.", .success)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.rcmInstruction = "Fix the issue below, return to RCM, then push again."
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func splitSelectedFiles() {
        let files = selectedFiles
        let outputDirectory = splitMergeOutputDirectory

        runSplitMergeOperation(title: "Split") {
            let service = SplitMergeService()
            for file in files {
                let destination = outputDirectory ?? file.deletingLastPathComponent()
                let output = try service.split(file: file, destinationDirectory: destination) { progress in
                    Task { @MainActor in
                        self.progress = progress.fractionCompleted
                    }
                }
                Task { @MainActor in
                    self.lastOutputURL = output
                    self.appendLog("Split \(file.lastPathComponent) to \(output.lastPathComponent).", .success)
                }
            }
        }
    }

    func mergeSelectedFolders() {
        let folders = selectedFiles
        let outputDirectory = splitMergeOutputDirectory

        runSplitMergeOperation(title: "Merge") {
            let service = SplitMergeService()
            for folder in folders {
                let destination = outputDirectory ?? folder.deletingLastPathComponent()
                let output = try service.merge(splitDirectory: folder, destinationDirectory: destination) { progress in
                    Task { @MainActor in
                        self.progress = progress.fractionCompleted
                    }
                }
                Task { @MainActor in
                    self.lastOutputURL = output
                    self.appendLog("Merged \(folder.lastPathComponent) to \(output.lastPathComponent).", .success)
                }
            }
        }
    }

    private func runSplitMergeOperation(title: String, operation: @escaping @Sendable () throws -> Void) {
        guard !selectedFiles.isEmpty, status != .running else { return }
        status = .running
        progress = 0
        currentInstruction = "\(title) in progress."
        appendLog("\(title) started.", .info)

        Task.detached(priority: .userInitiated) {
            do {
                try operation()
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1
                    self.currentInstruction = "\(title) complete."
                    self.appendLog("\(title) complete.", .success)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.currentInstruction = "\(title) failed."
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    private func handleUSBEvent(_ event: USBInstallEvent) {
        switch event {
        case let .log(entry):
            logs.append(entry)
            if entry.level == .success {
                currentInstruction = entry.message
            }
        case let .progress(value):
            progress = value
        case .completed:
            status = .completed
            progress = 1
            currentInstruction = "USB install complete."
        }
    }

    private func handleRCMEvent(_ event: USBInstallEvent) {
        switch event {
        case let .log(entry):
            logs.append(entry)
            if entry.level == .success {
                rcmInstruction = entry.message
            }
        case let .progress(value):
            progress = value
        case .completed:
            status = .completed
            progress = 1
            rcmInstruction = "RCM payload launched."
        }
    }

    private func appendLog(_ message: String, _ level: TransferLogLevel) {
        logs.append(TransferLogEntry(level: level, message: message))
    }

    private nonisolated static func scanLibraryItems(in directory: URL) throws -> [LibraryItem] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var items: [LibraryItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)

            if values?.isDirectory == true {
                if isSplitDirectory(url) {
                    items.append(libraryItem(for: url, libraryRoot: directory, itemIsDirectory: true))
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            guard libraryFileExtensions.contains(url.pathExtension.lowercased()) else { continue }
            items.append(libraryItem(for: url, libraryRoot: directory, itemIsDirectory: false))
        }

        return items.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            if $0.contentType.sortRank != $1.contentType.sortRank {
                return $0.contentType.sortRank < $1.contentType.sortRank
            }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    private nonisolated static func libraryItem(for url: URL, libraryRoot: URL, itemIsDirectory: Bool) -> LibraryItem {
        let metadata = libraryMetadata(for: url, libraryRoot: libraryRoot, itemIsDirectory: itemIsDirectory)
        return LibraryItem(url: url, title: metadata.title, contentType: metadata.contentType)
    }

    private nonisolated static func libraryMetadata(
        for url: URL,
        libraryRoot: URL,
        itemIsDirectory: Bool
    ) -> (title: String, contentType: LibraryContentType) {
        let root = libraryRoot.standardizedFileURL
        let rootPath = root.path
        var current = itemIsDirectory ? url.standardizedFileURL : url.deletingLastPathComponent().standardizedFileURL

        while current.path.hasPrefix(rootPath) {
            if let contentType = libraryFolderTypes[normalizedFolderName(current.lastPathComponent)] {
                let gameFolder = current.deletingLastPathComponent()
                let title = gameFolder.path == rootPath ? current.lastPathComponent : gameFolder.lastPathComponent
                return (cleanLibraryTitle(title, fallback: url), contentType)
            }

            if current.path == rootPath { break }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }

        let containingFolder = itemIsDirectory ? url.deletingLastPathComponent() : url.deletingLastPathComponent()
        let title = containingFolder.standardizedFileURL.path == rootPath ? url.deletingPathExtension().lastPathComponent : containingFolder.lastPathComponent
        return (cleanLibraryTitle(title, fallback: url), .other)
    }

    private nonisolated static func normalizedFolderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private nonisolated static func cleanLibraryTitle(_ title: String, fallback url: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private nonisolated static func isSplitDirectory(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return false
        }

        return contents.contains { child in
            child.lastPathComponent.range(of: #"^\d\d$"#, options: .regularExpression) != nil
        }
    }
}
