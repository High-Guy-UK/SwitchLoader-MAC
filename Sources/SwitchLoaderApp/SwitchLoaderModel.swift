import Foundation
import Security
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

struct LibraryGame: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var items: [LibraryItem]
    var metadata: GameMetadata?

    var mainGames: [LibraryItem] {
        items.filter { $0.contentType == .mainGame }
    }

    var updates: [LibraryItem] {
        items.filter { $0.contentType == .update }
    }

    var dlcs: [LibraryItem] {
        items.filter { $0.contentType == .dlc }
    }

    var others: [LibraryItem] {
        items.filter { $0.contentType == .other }
    }

    var installOrderedItems: [LibraryItem] {
        items.sorted {
            if $0.contentType.sortRank != $1.contentType.sortRank {
                return $0.contentType.sortRank < $1.contentType.sortRank
            }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    var heroImageURL: URL? {
        metadata?.bannerImageURL ?? metadata?.artworkImageURL ?? metadata?.screenshotImageURLs.first ?? metadata?.coverImageURL
    }

    var posterImageURL: URL? {
        metadata?.coverImageURL ?? metadata?.artworkImageURL ?? metadata?.bannerImageURL ?? metadata?.screenshotImageURLs.first
    }
}

struct GameMetadata: Codable, Hashable, Sendable {
    let provider: String
    let providerID: String
    let matchedTitle: String
    let summary: String?
    let releaseDate: String?
    let platformName: String?
    let rating: String?
    let players: String?
    let coop: String?
    let youtubeURL: URL?
    let aliases: [String]?
    let genres: [String]
    let developers: [String]
    let publishers: [String]
    let bannerImageURL: URL?
    let artworkImageURL: URL?
    let coverImageURL: URL?
    let logoImageURL: URL?
    let screenshotImageURLs: [URL]
}

struct GameMetadataMatch: Identifiable, Hashable, Sendable {
    let provider: String
    let providerID: String
    let title: String
    let summary: String?
    let releaseDate: String?
    let platformName: String?
    let rating: String?
    let players: String?
    let coop: String?
    let youtubeURL: URL?
    let aliases: [String]
    let genres: [String]
    let developers: [String]
    let publishers: [String]

    var id: String {
        providerID
    }
}

enum MetadataLookupState: String, Codable, Hashable, Sendable {
    case success
    case noMatch
    case failed
}

struct GameMetadataCacheEntry: Codable, Hashable, Sendable {
    let title: String
    let provider: String
    let state: MetadataLookupState
    let attemptedAt: Date
    let lookupPlatformID: Int?
    let metadata: GameMetadata?
    let message: String?
}

enum MetadataLookupError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a TGDB API key before matching artwork."
        }
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
    @Published var libraryGames: [LibraryGame] = []
    @Published var isScanningLibrary = false
    @Published var isFetchingMetadata = false
    @Published var libraryMessage = "Choose your NSP/XCI folder to build the library."
    @Published var metadataMessage = "Add a TGDB API key to fetch artwork and game details."
    @Published var hasTheGamesDBAPIKey = false
    @Published var currentInstruction = "Choose XCI, NSP, NSZ, or a split folder to install."
    @Published var selectedPayloadURL: URL?
    @Published var rcmPayloadDirectory: URL?
    @Published var isRCMDeviceConnected = false
    @Published var rcmInstruction = "Choose a payload .bin file to push over RCM."

    private nonisolated static let libraryDirectoryDefaultsKey = "SwitchLoader.libraryDirectory"
    private nonisolated static let libraryDirectoryBookmarkDefaultsKey = "SwitchLoader.libraryDirectoryBookmark"
    private nonisolated static let rcmPayloadDirectoryDefaultsKey = "SwitchLoader.rcmPayloadDirectory"
    private nonisolated static let gamesDBKeychainService = "SwitchLoader.TheGamesDB"
    private nonisolated static let gamesDBKeychainAccount = "apiKey"
    private var rcmMonitorTask: Task<Void, Never>?
    private var suppressNextRCMDisconnectLog = false
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
        if let url = Self.restoreLibraryDirectory() {
            libraryDirectory = url
            libraryMessage = "Library ready to scan."
        }

        if let path = UserDefaults.standard.string(forKey: Self.rcmPayloadDirectoryDefaultsKey), !path.isEmpty {
            rcmPayloadDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        hasTheGamesDBAPIKey = Self.loadTheGamesDBAPIKey()?.isEmpty == false
        metadataMessage = hasTheGamesDBAPIKey ? "Metadata ready." : "Add a TGDB API key to fetch artwork and game details."
        startRCMMonitor()

        if libraryDirectory != nil {
            scanLibrary()
        }
    }

    deinit {
        rcmMonitorTask?.cancel()
    }

    var canStartUSBInstall: Bool {
        !selectedFiles.isEmpty && status != .running
    }

    var canPushRCMPayload: Bool {
        selectedPayloadURL != nil && isRCMDeviceConnected && status != .running
    }

    func addFiles(_ urls: [URL]) {
        let merged = selectedFiles + urls
        selectedFiles = Array(NSOrderedSet(array: merged).compactMap { $0 as? URL })
        currentInstruction = "Open your installer on the device, choose USB install, then connect the cable."
        appendLog("Added \(urls.count) item\(urls.count == 1 ? "" : "s").", .info)
    }

    func setLibraryDirectory(_ url: URL) {
        libraryDirectory = url
        persistLibraryDirectory(url)
        appendLog("Library folder set to \(url.path).", .info)
        scanLibrary()
    }

    func scanLibrary() {
        guard let libraryDirectory else {
            libraryItems = []
            libraryGames = []
            libraryMessage = "Choose your NSP/XCI folder to build the library."
            return
        }

        isScanningLibrary = true
        libraryMessage = "Scanning library..."
        let apiKey = Self.loadTheGamesDBAPIKey()

        Task.detached(priority: .userInitiated) { [libraryDirectory] in
            do {
                let items = try Self.scanLibraryItems(in: libraryDirectory)
                let cache = Self.loadMetadataCache()
                let games = Self.groupLibraryGames(from: items, cache: cache)
                let enrichedCount = games.filter { $0.metadata != nil }.count
                let untriedGames = games.filter { cache[$0.id] == nil }
                await MainActor.run {
                    self.libraryItems = items
                    self.libraryGames = games
                    self.isScanningLibrary = false
                    self.libraryMessage = items.isEmpty ? "No install files found in this folder." : "Found \(games.count) game\(games.count == 1 ? "" : "s") and \(items.count) install item\(items.count == 1 ? "" : "s")."
                    if games.isEmpty {
                        self.metadataMessage = apiKey?.isEmpty == false ? "No games to enrich yet." : "Add a TGDB API key to fetch artwork and game details."
                    } else if untriedGames.isEmpty {
                        self.metadataMessage = enrichedCount == 0 ? "Metadata cache is up to date. No TGDB calls needed." : "Artwork/details loaded from cache for \(enrichedCount) game\(enrichedCount == 1 ? "" : "s"). No TGDB calls needed."
                    } else if apiKey?.isEmpty == false {
                        self.metadataMessage = "\(untriedGames.count) new game\(untriedGames.count == 1 ? "" : "s") need metadata."
                    } else {
                        self.metadataMessage = "Add a TGDB key to fetch artwork for \(untriedGames.count) new game\(untriedGames.count == 1 ? "" : "s")."
                    }
                    self.appendLog("Library scan found \(games.count) game\(games.count == 1 ? "" : "s").", .success)
                }

                guard let apiKey, !apiKey.isEmpty, !untriedGames.isEmpty else { return }

                await MainActor.run {
                    self.isFetchingMetadata = true
                    self.metadataMessage = "Fetching artwork/details for \(untriedGames.count) new game\(untriedGames.count == 1 ? "" : "s"). Cached games are skipped."
                }

                var updatedCache = cache
                let provider = TheGamesDBMetadataProvider(apiKey: apiKey)
                for game in untriedGames where updatedCache[game.id] == nil {
                    do {
                        if let metadata = try await provider.metadata(for: game.title) {
                            updatedCache[game.id] = GameMetadataCacheEntry(
                                title: game.title,
                                provider: metadata.provider,
                                state: .success,
                                attemptedAt: Date(),
                                lookupPlatformID: TheGamesDBMetadataProvider.nintendoSwitchPlatformID,
                                metadata: metadata,
                                message: nil
                            )
                            let gameID = game.id
                            await MainActor.run {
                                if let index = self.libraryGames.firstIndex(where: { $0.id == gameID }) {
                                    self.libraryGames[index].metadata = metadata
                                }
                            }
                        } else {
                            updatedCache[game.id] = GameMetadataCacheEntry(
                                title: game.title,
                                provider: "TheGamesDB",
                                state: .noMatch,
                                attemptedAt: Date(),
                                lookupPlatformID: TheGamesDBMetadataProvider.nintendoSwitchPlatformID,
                                metadata: nil,
                                message: "No Nintendo Switch TGDB match found."
                            )
                        }
                    } catch {
                        updatedCache[game.id] = GameMetadataCacheEntry(
                            title: game.title,
                            provider: "TheGamesDB",
                            state: .failed,
                            attemptedAt: Date(),
                            lookupPlatformID: TheGamesDBMetadataProvider.nintendoSwitchPlatformID,
                            metadata: nil,
                            message: error.localizedDescription
                        )
                    }

                    try? Self.saveMetadataCache(updatedCache)
                }

                let currentGameIDs = Set(games.map(\.id))
                let currentCacheEntries = updatedCache.filter { currentGameIDs.contains($0.key) }.values
                let failedCount = currentCacheEntries.filter { $0.state == .failed }.count
                let noMatchCount = currentCacheEntries.filter { $0.state == .noMatch }.count
                await MainActor.run {
                    let enrichedCount = self.libraryGames.filter { $0.metadata != nil }.count
                    self.isFetchingMetadata = false
                    if enrichedCount == 0 {
                        self.metadataMessage = "Metadata cache updated. No matched artwork yet; cached misses will not be retried automatically."
                    } else {
                        var detail = "Artwork/details cached for \(enrichedCount) game\(enrichedCount == 1 ? "" : "s")."
                        if noMatchCount > 0 || failedCount > 0 {
                            detail += " \(noMatchCount + failedCount) unmatched/failed lookup\(noMatchCount + failedCount == 1 ? "" : "s") cached too."
                        }
                        self.metadataMessage = detail
                    }
                }
            } catch {
                await MainActor.run {
                    self.libraryItems = []
                    self.libraryGames = []
                    self.isScanningLibrary = false
                    self.isFetchingMetadata = false
                    self.libraryMessage = error.localizedDescription
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func addLibraryToQueue() {
        addFiles(libraryGames.flatMap(\.installOrderedItems).map(\.url))
        appendLog("Queued library items in main game, update, DLC order.", .warning)
    }

    func addGameToQueue(_ game: LibraryGame, contentType: LibraryContentType? = nil) {
        let items = contentType.map { type in
            game.items.filter { $0.contentType == type }
        } ?? game.installOrderedItems

        addFiles(items.sorted {
            if $0.contentType.sortRank != $1.contentType.sortRank {
                return $0.contentType.sortRank < $1.contentType.sortRank
            }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }.map(\.url))

        if contentType == nil || contentType == .update || contentType == .dlc {
            appendLog("Install main games before updates or DLC. Queue all uses the safe order.", .warning)
        }
    }

    func saveTheGamesDBAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.saveTheGamesDBAPIKey(trimmed.isEmpty ? nil : trimmed)
        hasTheGamesDBAPIKey = !trimmed.isEmpty
        metadataMessage = hasTheGamesDBAPIKey ? "TGDB key saved. Only new, uncached games will call TGDB." : "Add a TGDB API key to fetch artwork and game details."
        appendLog(hasTheGamesDBAPIKey ? "TGDB API key saved." : "TGDB API key cleared.", .info)
    }

    func refreshLibraryMetadata() {
        scanLibrary()
    }

    func searchMetadataMatches(for query: String) async throws -> [GameMetadataMatch] {
        guard let apiKey = Self.loadTheGamesDBAPIKey(), !apiKey.isEmpty else {
            throw MetadataLookupError.missingAPIKey
        }

        let provider = TheGamesDBMetadataProvider(apiKey: apiKey)
        return try await provider.matches(for: query)
    }

    func applyMetadataMatch(_ match: GameMetadataMatch, to game: LibraryGame) async throws {
        guard let apiKey = Self.loadTheGamesDBAPIKey(), !apiKey.isEmpty else {
            throw MetadataLookupError.missingAPIKey
        }

        let provider = TheGamesDBMetadataProvider(apiKey: apiKey)
        let metadata = try await provider.metadata(for: match)
        var cache = Self.loadMetadataCache()
        cache[game.id] = GameMetadataCacheEntry(
            title: game.title,
            provider: metadata.provider,
            state: .success,
            attemptedAt: Date(),
            lookupPlatformID: TheGamesDBMetadataProvider.nintendoSwitchPlatformID,
            metadata: metadata,
            message: "Manual match selected."
        )
        try Self.saveMetadataCache(cache)

        if let index = libraryGames.firstIndex(where: { $0.id == game.id }) {
            libraryGames[index].metadata = metadata
        }
        metadataMessage = "Manual match saved for \(game.title)."
        appendLog("Manual TGDB match saved for \(game.title).", .success)
    }

    func setRCMPayload(_ url: URL) {
        selectedPayloadURL = url
        rcmPayloadDirectory = url.deletingLastPathComponent()
        UserDefaults.standard.set(rcmPayloadDirectory?.path, forKey: Self.rcmPayloadDirectoryDefaultsKey)
        rcmInstruction = isRCMDeviceConnected ? "RCM detected. Ready to push." : "Put the Switch into RCM, connect USB, then push."
        appendLog("Selected RCM payload \(url.lastPathComponent).", .info)
    }

    func refreshRCMConnection() {
        Task {
            let connected = await Self.detectRCMDevice()
            setRCMConnection(connected)
        }
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
            suppressNextRCMDisconnectLog = true
        }
    }

    private func appendLog(_ message: String, _ level: TransferLogLevel) {
        logs.append(TransferLogEntry(level: level, message: message))
    }

    private func startRCMMonitor() {
        rcmMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let connected = await Self.detectRCMDevice()
                await MainActor.run {
                    self?.setRCMConnection(connected)
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private nonisolated static func detectRCMDevice() async -> Bool {
        await Task.detached(priority: .utility) {
            RCMPayloadLauncher.isRCMDeviceConnected
        }.value
    }

    private func setRCMConnection(_ connected: Bool) {
        guard isRCMDeviceConnected != connected else { return }

        let wasConnected = isRCMDeviceConnected
        isRCMDeviceConnected = connected

        guard status != .running else { return }

        if connected {
            suppressNextRCMDisconnectLog = false
            if case .failed = status {
                status = .idle
            }
            rcmInstruction = selectedPayloadURL == nil ? "RCM detected. Choose a payload to push." : "RCM detected. Ready to push."
            appendLog("RCM device detected.", .success)
        } else if wasConnected {
            guard !suppressNextRCMDisconnectLog else {
                suppressNextRCMDisconnectLog = false
                return
            }
            rcmInstruction = selectedPayloadURL == nil ? "Choose a payload .bin file to push over RCM." : "Put the Switch into RCM, connect USB, then push."
            appendLog("RCM device disconnected.", .warning)
        }
    }

    private nonisolated static func scanLibraryItems(in directory: URL) throws -> [LibraryItem] {
        let didAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

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

    private func persistLibraryDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.libraryDirectoryDefaultsKey)

        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Self.libraryDirectoryBookmarkDefaultsKey)
        }
    }

    private nonisolated static func restoreLibraryDirectory() -> URL? {
        if let bookmark = UserDefaults.standard.data(forKey: libraryDirectoryBookmarkDefaultsKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale, let freshBookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(freshBookmark, forKey: libraryDirectoryBookmarkDefaultsKey)
                }
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: libraryDirectoryDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return nil
    }

    private nonisolated static func groupLibraryGames(
        from items: [LibraryItem],
        cache: [String: GameMetadataCacheEntry]
    ) -> [LibraryGame] {
        let grouped = Dictionary(grouping: items) { stableGameID(for: $0.title) }
        return grouped.map { id, items in
            let sortedItems = items.sorted {
                if $0.contentType.sortRank != $1.contentType.sortRank {
                    return $0.contentType.sortRank < $1.contentType.sortRank
                }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            let title = sortedItems.first?.title ?? id
            return LibraryGame(id: id, title: title, items: sortedItems, metadata: cache[id]?.metadata)
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated static func stableGameID(for title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }

    private nonisolated static func loadMetadataCache() -> [String: GameMetadataCacheEntry] {
        guard let data = try? Data(contentsOf: metadataCacheURL) else { return [:] }
        if let cache = try? JSONDecoder().decode([String: GameMetadataCacheEntry].self, from: data) {
            return cache.filter { _, entry in
                entry.lookupPlatformID == TheGamesDBMetadataProvider.nintendoSwitchPlatformID
            }
        }

        return [:]
    }

    private nonisolated static func saveMetadataCache(_ cache: [String: GameMetadataCacheEntry]) throws {
        let url = metadataCacheURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static var metadataCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("SwitchLoader", isDirectory: true)
            .appendingPathComponent("LibraryMetadataCache.json")
    }

    private nonisolated static func loadTheGamesDBAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: gamesDBKeychainService,
            kSecAttrAccount as String: gamesDBKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    private nonisolated static func saveTheGamesDBAPIKey(_ key: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: gamesDBKeychainService,
            kSecAttrAccount as String: gamesDBKeychainAccount
        ]

        SecItemDelete(query as CFDictionary)

        guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: gamesDBKeychainService,
            kSecAttrAccount as String: gamesDBKeychainAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(item as CFDictionary, nil)
    }
}

private struct TheGamesDBMetadataProvider: Sendable {
    static let nintendoSwitchPlatformID = 4971

    let apiKey: String

    func metadata(for title: String) async throws -> GameMetadata? {
        guard let game = try await findGame(named: title) else { return nil }
        return try await metadata(for: game.match)
    }

    func matches(for title: String) async throws -> [GameMetadataMatch] {
        try await findGames(named: title).map(\.match)
    }

    func metadata(for match: GameMetadataMatch) async throws -> GameMetadata {
        guard let gameID = Int(match.providerID) else {
            throw URLError(.badURL)
        }
        let images = try await loadImages(for: gameID)
        return GameMetadata(
            provider: "TheGamesDB",
            providerID: match.providerID,
            matchedTitle: match.title,
            summary: match.summary,
            releaseDate: match.releaseDate,
            platformName: match.platformName,
            rating: match.rating,
            players: match.players,
            coop: match.coop,
            youtubeURL: match.youtubeURL,
            aliases: match.aliases,
            genres: match.genres,
            developers: match.developers,
            publishers: match.publishers,
            bannerImageURL: images.preferredURL(types: ["banner", "fanart", "screenshot"]),
            artworkImageURL: images.preferredURL(types: ["fanart", "screenshot"]),
            coverImageURL: images.preferredURL(types: ["boxart"]),
            logoImageURL: images.preferredURL(types: ["clearlogo", "logo"]),
            screenshotImageURLs: images.urls(types: ["screenshot", "fanart"])
        )
    }

    private func findGame(named title: String) async throws -> RemoteGame? {
        try await findGames(named: title).max { lhs, rhs in
            score(lhs.name, against: title) < score(rhs.name, against: title)
        }
    }

    private func findGames(named title: String) async throws -> [RemoteGame] {
        guard var components = URLComponents(string: "https://api.thegamesdb.net/v1/Games/ByGameName") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "name", value: title),
            URLQueryItem(name: "fields", value: "overview,genres,developers,publishers,platform,players,coop,rating,youtube,alternates"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "filter[platform]", value: String(Self.nintendoSwitchPlatformID))
        ]
        guard let url = components.url else { return [] }

        let object = try await jsonObject(from: url)
        guard let data = object["data"] as? [String: Any],
              let games = data["games"] as? [[String: Any]]
        else {
            return []
        }

        return games
            .compactMap(RemoteGame.init(dictionary:))
            .filter(\.isNintendoSwitchRelease)
            .sorted {
                score($0.name, against: title) > score($1.name, against: title)
            }
    }

    private func loadImages(for gameID: Int) async throws -> RemoteImages {
        guard var components = URLComponents(string: "https://api.thegamesdb.net/v1/Games/Images") else {
            return RemoteImages(baseURLs: [:], images: [])
        }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "games_id", value: String(gameID))
        ]
        guard let url = components.url else { return RemoteImages(baseURLs: [:], images: []) }

        let object = try await jsonObject(from: url)
        guard let data = object["data"] as? [String: Any] else {
            return RemoteImages(baseURLs: [:], images: [])
        }

        let baseURLs = data["base_url"] as? [String: String] ?? [:]
        var images: [RemoteImage] = []
        if let imageGroups = data["images"] as? [String: [[String: Any]]] {
            images = imageGroups[String(gameID)]?.compactMap(RemoteImage.init(dictionary:)) ?? []
        } else if let imageGroups = data["images"] as? [String: [Any]],
                  let group = imageGroups[String(gameID)] {
            images = group.compactMap { ($0 as? [String: Any]).flatMap(RemoteImage.init(dictionary:)) }
        }

        return RemoteImages(baseURLs: baseURLs, images: images)
    }

    private func jsonObject(from url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func score(_ candidate: String, against title: String) -> Double {
        let lhs = normalized(candidate)
        let rhs = normalized(title)
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.85 }
        let lhsTokens = Set(lhs.split(separator: " "))
        let rhsTokens = Set(rhs.split(separator: " "))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let shared = lhsTokens.intersection(rhsTokens).count
        return Double(shared) / Double(max(lhsTokens.count, rhsTokens.count))
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private struct RemoteGame {
        let id: Int
        let name: String
        let overview: String?
        let releaseDate: String?
        let genres: [String]
        let developers: [String]
        let publishers: [String]
        let rating: String?
        let players: String?
        let coop: String?
        let youtubeURL: URL?
        let aliases: [String]
        let platformIDs: Set<Int>
        let platformNames: Set<String>

        var match: GameMetadataMatch {
            GameMetadataMatch(
                provider: "TheGamesDB",
                providerID: String(id),
                title: name,
                summary: overview,
                releaseDate: releaseDate,
                platformName: platformNames.sorted().first,
                rating: rating,
                players: players,
                coop: coop,
                youtubeURL: youtubeURL,
                aliases: aliases,
                genres: genres,
                developers: developers,
                publishers: publishers
            )
        }

        var isNintendoSwitchRelease: Bool {
            platformIDs.contains(TheGamesDBMetadataProvider.nintendoSwitchPlatformID)
                || platformNames.contains { name in
                    name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .localizedCaseInsensitiveContains("nintendo switch")
                }
        }

        init?(dictionary: [String: Any]) {
            guard let id = dictionary["id"] as? Int,
                  let name = dictionary["game_title"] as? String ?? dictionary["name"] as? String
            else {
                return nil
            }

            self.id = id
            self.name = name
            self.overview = Self.englishText(from: dictionary["overview"])
            self.releaseDate = Self.stringValue(from: dictionary["release_date"])
            self.genres = Self.stringList(from: dictionary["genres"])
            self.developers = Self.stringList(from: dictionary["developers"])
            self.publishers = Self.stringList(from: dictionary["publishers"])
            self.rating = Self.stringValue(from: dictionary["rating"] ?? dictionary["esrb"] ?? dictionary["certification"])
            self.players = Self.stringValue(from: dictionary["players"] ?? dictionary["max_players"])
            self.coop = Self.stringValue(from: dictionary["coop"] ?? dictionary["co-op"] ?? dictionary["co_op"])
            self.youtubeURL = Self.youtubeURL(from: dictionary["youtube"] ?? dictionary["youtube_url"] ?? dictionary["trailer"])
            self.aliases = Self.stringList(from: dictionary["alternates"] ?? dictionary["aliases"] ?? dictionary["alternate_titles"])
            let platform = Self.platformValues(from: dictionary["platform"])
            let platformID = Self.platformValues(from: dictionary["platform_id"])
            let platforms = Self.platformValues(from: dictionary["platforms"])
            self.platformIDs = platform.ids.union(platformID.ids).union(platforms.ids)
            self.platformNames = platform.names.union(platformID.names).union(platforms.names)
        }

        private static func englishText(from value: Any?) -> String? {
            if let string = value as? String {
                return string.isEmpty ? nil : string
            }

            if let dictionary = value as? [String: Any] {
                for key in ["en", "eng", "english", "EN", "English"] {
                    if let text = stringValue(from: dictionary[key]), !text.isEmpty {
                        return text
                    }
                }
                return dictionary.values.compactMap { stringValue(from: $0) }.first { !$0.isEmpty }
            }

            if let values = value as? [[String: Any]] {
                let english = values.first { entry in
                    let language = stringValue(from: entry["language"] ?? entry["lang"] ?? entry["locale"]) ?? ""
                    return language.localizedCaseInsensitiveContains("en")
                        || language.localizedCaseInsensitiveContains("english")
                }
                if let text = english.flatMap({ stringValue(from: $0["text"] ?? $0["overview"] ?? $0["value"]) }), !text.isEmpty {
                    return text
                }
            }

            return nil
        }

        private static func stringValue(from value: Any?) -> String? {
            switch value {
            case let string as String:
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case let number as NSNumber:
                return number.stringValue
            case let int as Int:
                return String(int)
            default:
                return nil
            }
        }

        private static func youtubeURL(from value: Any?) -> URL? {
            guard let text = stringValue(from: value) else { return nil }
            if let url = URL(string: text), url.scheme != nil {
                return url
            }
            return URL(string: "https://www.youtube.com/watch?v=\(text)")
        }

        private static func stringList(from value: Any?) -> [String] {
            if let values = value as? [String] {
                return values
            }
            if let values = value as? [Any] {
                return values.compactMap { item in
                    if let string = item as? String {
                        return string
                    }
                    if let dictionary = item as? [String: Any] {
                        return stringValue(from: dictionary["name"] ?? dictionary["title"] ?? dictionary["value"])
                    }
                    return nil
                }
            }
            if let dictionary = value as? [String: Any] {
                return dictionary.values.compactMap { stringValue(from: $0) }
            }
            return []
        }

        private static func platformValues(from value: Any?) -> (ids: Set<Int>, names: Set<String>) {
            var ids = Set<Int>()
            var names = Set<String>()

            func read(_ value: Any?) {
                switch value {
                case let int as Int:
                    ids.insert(int)
                case let number as NSNumber:
                    ids.insert(number.intValue)
                case let string as String:
                    if let int = Int(string) {
                        ids.insert(int)
                    } else if !string.isEmpty {
                        names.insert(string)
                    }
                case let values as [Any]:
                    values.forEach(read)
                case let dictionary as [String: Any]:
                    read(dictionary["id"])
                    read(dictionary["platform_id"])
                    read(dictionary["name"])
                    read(dictionary["platform_name"])
                default:
                    break
                }
            }

            read(value)
            return (ids, names)
        }
    }

    private struct RemoteImage {
        let type: String
        let filename: String

        init?(dictionary: [String: Any]) {
            guard let type = dictionary["type"] as? String,
                  let filename = dictionary["filename"] as? String
            else {
                return nil
            }

            self.type = type.lowercased()
            self.filename = filename
        }
    }

    private struct RemoteImages {
        let baseURLs: [String: String]
        let images: [RemoteImage]

        func preferredURL(types: [String]) -> URL? {
            urls(types: types).first
        }

        func urls(types: [String]) -> [URL] {
            let wanted = types.map { $0.lowercased() }
            return images
                .filter { wanted.contains($0.type) }
                .compactMap { url(for: $0) }
        }

        private func url(for image: RemoteImage) -> URL? {
            let base = baseURLs["original"] ?? baseURLs["large"] ?? baseURLs["medium"] ?? baseURLs.values.first
            guard let base else { return nil }
            let separator = base.hasSuffix("/") ? "" : "/"
            return URL(string: base + separator + image.filename)
        }
    }
}
