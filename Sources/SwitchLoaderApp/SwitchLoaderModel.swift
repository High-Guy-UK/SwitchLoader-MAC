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

enum MetadataProviderKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case theGamesDB = "TheGamesDB"
    case screenScraper = "ScreenScraper"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theGamesDB:
            return "TGDB"
        case .screenScraper:
            return "ScreenScraper"
        }
    }

    var matchTitle: String {
        switch self {
        case .theGamesDB:
            return "Fix TGDB Match"
        case .screenScraper:
            return "Fix ScreenScraper Match"
        }
    }
}

struct LibraryItem: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let contentType: LibraryContentType
    let size: UInt64

    var id: URL {
        url
    }
}

struct LibraryGame: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var items: [LibraryItem]
    var metadata: GameMetadata?
    var sourceMetadata: [String: GameMetadata] = [:]

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
        metadata?.artworkImageURL ?? metadata?.screenshotImageURLs.first
    }

    var posterImageURL: URL? {
        metadata?.coverImageURL ?? metadata?.artworkImageURL ?? metadata?.bannerImageURL ?? metadata?.screenshotImageURLs.first
    }

    func hasMetadata(from provider: MetadataProviderKind) -> Bool {
        if sourceMetadata[provider.rawValue] != nil {
            return true
        }
        if sourceMetadata.values.contains(where: { $0.provider == provider.rawValue }) {
            return true
        }
        guard let metadata else { return false }
        if metadata.provider == provider.rawValue {
            return true
        }

        switch provider {
        case .theGamesDB:
            return metadata.lookupPlatformID == TheGamesDBMetadataProvider.nintendoSwitchPlatformID
        case .screenScraper:
            return metadata.providerID.contains(":")
                || metadata.provider.localizedCaseInsensitiveContains("ScreenScraper")
        }
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

    var lookupPlatformID: Int? {
        if provider == "TheGamesDB" {
            return TheGamesDBMetadataProvider.nintendoSwitchPlatformID
        }
        if provider == "ScreenScraper" {
            return providerID.split(separator: ":").last.flatMap { Int($0) }
        }
        return nil
    }

    var isMissingRichArtworkOrDetails: Bool {
        let hasArtworkSet = coverImageURL != nil
            && artworkImageURL != nil
            && logoImageURL != nil
            && bannerImageURL != nil
            && !screenshotImageURLs.isEmpty
        let hasDetails = summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && !genres.isEmpty
            && (!developers.isEmpty || !publishers.isEmpty)
        return !hasArtworkSet || !hasDetails
    }

    func fillingMissingValues(from fallback: GameMetadata) -> GameMetadata {
        GameMetadata(
            provider: provider,
            providerID: providerID,
            matchedTitle: firstNonEmpty(matchedTitle, fallback.matchedTitle) ?? matchedTitle,
            summary: firstNonEmpty(summary, fallback.summary),
            releaseDate: firstNonEmpty(releaseDate, fallback.releaseDate),
            platformName: firstNonEmpty(platformName, fallback.platformName),
            rating: firstNonEmpty(rating, fallback.rating),
            players: firstNonEmpty(players, fallback.players),
            coop: firstNonEmpty(coop, fallback.coop),
            youtubeURL: youtubeURL ?? fallback.youtubeURL,
            aliases: mergedStrings(aliases ?? [], fallback.aliases ?? []),
            genres: mergedStrings(genres, fallback.genres),
            developers: mergedStrings(developers, fallback.developers),
            publishers: mergedStrings(publishers, fallback.publishers),
            bannerImageURL: bannerImageURL ?? fallback.bannerImageURL,
            artworkImageURL: artworkImageURL ?? fallback.artworkImageURL,
            coverImageURL: coverImageURL ?? fallback.coverImageURL,
            logoImageURL: logoImageURL ?? fallback.logoImageURL,
            screenshotImageURLs: mergedURLs(screenshotImageURLs, fallback.screenshotImageURLs)
        )
    }

    private func firstNonEmpty(_ preferred: String?, _ fallback: String?) -> String? {
        if let preferred, preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return preferred
        }
        if let fallback, fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return fallback
        }
        return nil
    }

    private func mergedStrings(_ preferred: [String], _ fallback: [String]) -> [String] {
        var seen = Set<String>()
        return (preferred + fallback).filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key.isEmpty == false, seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func mergedURLs(_ preferred: [URL], _ fallback: [URL]) -> [URL] {
        var seen = Set<String>()
        return (preferred + fallback).filter { url in
            let key = url.absoluteString
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }
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

struct ScreenScraperCredentials: Codable, Hashable, Sendable {
    var devUsername: String
    var debugPassword: String
    var softwareName: String
    var memberUsername: String
    var memberPassword: String

    var isComplete: Bool {
        !devUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !debugPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !softwareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !memberUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !memberPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct MetadataProviderCredentials: Codable, Sendable {
    var theGamesDBAPIKey: String?
    var screenScraperCredentials: ScreenScraperCredentials?
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
    let sourceMetadata: [String: GameMetadata]?
    let message: String?

    var availableSourceMetadata: [String: GameMetadata] {
        if let sourceMetadata, !sourceMetadata.isEmpty {
            return sourceMetadata
        }
        if let metadata {
            return [metadata.provider: metadata]
        }
        return [:]
    }
}

enum MetadataLookupError: LocalizedError {
    case missingAPIKey
    case providerRejected(String)
    case providerTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a metadata account before matching artwork."
        case let .providerRejected(message):
            message
        case let .providerTimedOut(provider):
            "\(provider) took too long to answer. Try a shorter title, an alternate spelling, or search again in a moment."
        }
    }
}

enum HomebrewLibraryError: LocalizedError {
    case missingArchiveFolder
    case invalidGitHubURL
    case duplicateEntry
    case noSelection
    case noReleaseAssets(String)
    case downloadFailed(String)
    case generateFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArchiveFolder:
            "Choose or create a HomebrewApps archive folder first."
        case .invalidGitHubURL:
            "Enter a GitHub repository link in the form https://github.com/owner/repo."
        case .duplicateEntry:
            "That GitHub repository is already in the Homebrew library."
        case .noSelection:
            "Tick at least one homebrew app before generating a folder."
        case let .noReleaseAssets(name):
            "\(name) does not have a downloadable .nro, .zip, .ovl, or .kip release asset."
        case let .downloadFailed(message), let .generateFailed(message):
            message
        }
    }
}

enum HomebrewCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case launcher = "Launcher"
    case files = "Files"
    case saves = "Saves"
    case media = "Media"
    case utility = "Utility"
    case overlay = "Overlay"
    case sysmodule = "Sysmodule"
    case modding = "Modding"
    case development = "Development"
    case custom = "Custom"
}

struct HomebrewCatalogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let repositoryURL: URL
    let category: HomebrewCategory
    let isBuiltIn: Bool

    var repositoryName: String {
        Self.repositoryName(from: repositoryURL) ?? repositoryURL.lastPathComponent
    }

    init(
        id: String? = nil,
        name: String,
        summary: String,
        repositoryURL: URL,
        category: HomebrewCategory,
        isBuiltIn: Bool
    ) {
        self.id = id ?? Self.stableID(for: repositoryURL)
        self.name = name
        self.summary = summary
        self.repositoryURL = repositoryURL
        self.category = category
        self.isBuiltIn = isBuiltIn
    }

    static func fromCustomRepository(_ value: String) throws -> HomebrewCatalogEntry {
        guard let url = normalizedGitHubURL(from: value),
              let repositoryName = repositoryName(from: url)
        else {
            throw HomebrewLibraryError.invalidGitHubURL
        }

        return HomebrewCatalogEntry(
            name: repositoryName.split(separator: "/").last.map(String.init) ?? repositoryName,
            summary: "Custom GitHub homebrew repository.",
            repositoryURL: url,
            category: .custom,
            isBuiltIn: false
        )
    }

    static func stableID(for url: URL) -> String {
        repositoryName(from: url)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
            ?? UUID().uuidString
    }

    static func repositoryName(from url: URL) -> String? {
        guard url.host?.localizedCaseInsensitiveContains("github.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return "\(owner)/\(repo)"
    }

    private static func normalizedGitHubURL(from value: String) -> URL? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.localizedCaseInsensitiveContains("://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed),
              let repositoryName = repositoryName(from: url)
        else {
            return nil
        }
        return URL(string: "https://github.com/\(repositoryName)")
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
    @Published var metadataProgress = 0.0
    @Published var metadataStatusDetail = ""
    @Published var libraryMessage = "Choose your NSP/XCI folder to build the library."
    @Published var metadataMessage = "Add a TGDB API key to fetch artwork and game details."
    @Published var hasTheGamesDBAPIKey = false
    @Published var hasScreenScraperCredentials = false
    @Published var currentInstruction = "Choose XCI, NSP, NSZ, or a split folder to install."
    @Published var selectedPayloadURL: URL?
    @Published var rcmPayloadDirectory: URL?
    @Published var isRCMDeviceConnected = false
    @Published var rcmInstruction = "Choose a payload .bin file to push over RCM."
    @Published var homebrewArchiveDirectory: URL?
    @Published var customHomebrewEntries: [HomebrewCatalogEntry] = []
    @Published var selectedHomebrewEntryIDs: Set<String> = []
    @Published var downloadedHomebrewEntryIDs: Set<String> = []
    @Published var downloadingHomebrewEntryIDs: Set<String> = []
    @Published var isGeneratingHomebrewFolder = false
    @Published var generatedHomebrewFolderURL: URL?
    @Published var homebrewMessage = "Choose or create a HomebrewApps archive folder."
    @Published var receiverInstruction = "Start the receiver server, then enter the Mac address on the Switch."
    @Published var receiverServerURL: String?

    private nonisolated static let libraryDirectoryDefaultsKey = "SwitchLoader.libraryDirectory"
    private nonisolated static let libraryDirectoryBookmarkDefaultsKey = "SwitchLoader.libraryDirectoryBookmark"
    private nonisolated static let homebrewArchiveDirectoryDefaultsKey = "SwitchLoader.homebrewArchiveDirectory"
    private nonisolated static let homebrewArchiveDirectoryBookmarkDefaultsKey = "SwitchLoader.homebrewArchiveDirectoryBookmark"
    private nonisolated static let customHomebrewEntriesDefaultsKey = "SwitchLoader.customHomebrewEntries"
    private nonisolated static let rcmPayloadDirectoryDefaultsKey = "SwitchLoader.rcmPayloadDirectory"
    private var rcmMonitorTask: Task<Void, Never>?
    private var cachedTheGamesDBAPIKey: String?
    private var cachedScreenScraperCredentials: ScreenScraperCredentials?
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

        customHomebrewEntries = Self.loadCustomHomebrewEntries()
        if let url = Self.restoreHomebrewArchiveDirectory() {
            homebrewArchiveDirectory = url
            homebrewMessage = "Homebrew archive ready."
            refreshHomebrewArchiveStatus()
        }

        cachedTheGamesDBAPIKey = Self.loadTheGamesDBAPIKey()
        cachedScreenScraperCredentials = Self.loadScreenScraperCredentials()
        hasTheGamesDBAPIKey = cachedTheGamesDBAPIKey?.isEmpty == false
        hasScreenScraperCredentials = cachedScreenScraperCredentials?.isComplete == true
        metadataMessage = hasAnyMetadataProvider ? "Metadata ready." : "Add a metadata account to fetch artwork and game details."
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

    var canStartReceiverServer: Bool {
        !selectedFiles.isEmpty && status != .running
    }

    var canSendGeneratedHomebrewFolderToReceiver: Bool {
        generatedHomebrewFolderURL != nil && status != .running
    }

    var canPushRCMPayload: Bool {
        selectedPayloadURL != nil && isRCMDeviceConnected && status != .running
    }

    var hasAnyMetadataProvider: Bool {
        hasTheGamesDBAPIKey || hasScreenScraperCredentials
    }

    var homebrewCatalog: [HomebrewCatalogEntry] {
        Self.defaultHomebrewCatalog + customHomebrewEntries.sorted {
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var selectedHomebrewEntries: [HomebrewCatalogEntry] {
        homebrewCatalog.filter { selectedHomebrewEntryIDs.contains($0.id) }
    }

    func setHomebrewArchiveDirectory(_ url: URL) {
        homebrewArchiveDirectory = url
        persistHomebrewArchiveDirectory(url)
        homebrewMessage = "Homebrew archive set to \(url.lastPathComponent)."
        appendLog("Homebrew archive folder set to \(url.path).", .info)
        refreshHomebrewArchiveStatus()
    }

    func addCustomHomebrewRepository(_ value: String) throws {
        let entry = try HomebrewCatalogEntry.fromCustomRepository(value)
        guard !homebrewCatalog.contains(where: { $0.id == entry.id }) else {
            throw HomebrewLibraryError.duplicateEntry
        }
        customHomebrewEntries.append(entry)
        persistCustomHomebrewEntries()
        selectedHomebrewEntryIDs.insert(entry.id)
        refreshHomebrewArchiveStatus()
        homebrewMessage = "Added \(entry.repositoryName) to the Homebrew library."
        appendLog("Added custom homebrew repo \(entry.repositoryName).", .success)
    }

    func removeCustomHomebrewEntry(_ entry: HomebrewCatalogEntry) {
        guard !entry.isBuiltIn else { return }
        customHomebrewEntries.removeAll { $0.id == entry.id }
        selectedHomebrewEntryIDs.remove(entry.id)
        downloadedHomebrewEntryIDs.remove(entry.id)
        downloadingHomebrewEntryIDs.remove(entry.id)
        persistCustomHomebrewEntries()
        refreshHomebrewArchiveStatus()
        homebrewMessage = "Removed \(entry.name) from the custom catalog."
        appendLog("Removed custom homebrew repo \(entry.repositoryName).", .info)
    }

    func setHomebrewSelection(_ entry: HomebrewCatalogEntry, isSelected: Bool) {
        if isSelected {
            selectedHomebrewEntryIDs.insert(entry.id)
        } else {
            selectedHomebrewEntryIDs.remove(entry.id)
        }
    }

    func refreshHomebrewArchiveStatus() {
        guard let homebrewArchiveDirectory else {
            downloadedHomebrewEntryIDs = []
            homebrewMessage = "Choose or create a HomebrewApps archive folder."
            return
        }

        let entries = homebrewCatalog
        Task.detached(priority: .utility) { [homebrewArchiveDirectory, entries] in
            let downloaded = Set(entries.compactMap { entry in
                Self.homebrewEntryHasDownloads(entry, in: homebrewArchiveDirectory) ? entry.id : nil
            })
            await MainActor.run {
                self.downloadedHomebrewEntryIDs = downloaded
                self.homebrewMessage = downloaded.isEmpty
                    ? "Archive ready. Download apps to mark them ready."
                    : "\(downloaded.count) homebrew app\(downloaded.count == 1 ? "" : "s") downloaded and ready."
            }
        }
    }

    func downloadHomebrew(_ entry: HomebrewCatalogEntry) {
        guard let homebrewArchiveDirectory else {
            homebrewMessage = HomebrewLibraryError.missingArchiveFolder.localizedDescription
            appendLog(homebrewMessage, .failure)
            return
        }

        downloadingHomebrewEntryIDs.insert(entry.id)
        homebrewMessage = "Downloading \(entry.name) from GitHub..."
        appendLog("Downloading \(entry.repositoryName).", .info)

        Task.detached(priority: .userInitiated) { [entry, homebrewArchiveDirectory] in
            do {
                let assetCount = try await Self.downloadHomebrewEntry(entry, to: homebrewArchiveDirectory)
                await MainActor.run {
                    self.downloadingHomebrewEntryIDs.remove(entry.id)
                    self.downloadedHomebrewEntryIDs.insert(entry.id)
                    self.homebrewMessage = "\(entry.name) ready with \(assetCount) file\(assetCount == 1 ? "" : "s")."
                    self.appendLog("Downloaded \(entry.name).", .success)
                }
            } catch {
                await MainActor.run {
                    self.downloadingHomebrewEntryIDs.remove(entry.id)
                    self.downloadedHomebrewEntryIDs.remove(entry.id)
                    self.homebrewMessage = error.localizedDescription
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func downloadSelectedHomebrew() {
        let entries = selectedHomebrewEntries.filter { !downloadedHomebrewEntryIDs.contains($0.id) }
        if entries.isEmpty {
            homebrewMessage = selectedHomebrewEntries.isEmpty ? HomebrewLibraryError.noSelection.localizedDescription : "Selected apps are already downloaded."
            return
        }

        for entry in entries {
            downloadHomebrew(entry)
        }
    }

    func generateHomebrewFolder(in destinationDirectory: URL) {
        guard let homebrewArchiveDirectory else {
            homebrewMessage = HomebrewLibraryError.missingArchiveFolder.localizedDescription
            appendLog(homebrewMessage, .failure)
            return
        }

        let entries = selectedHomebrewEntries
        guard !entries.isEmpty else {
            homebrewMessage = HomebrewLibraryError.noSelection.localizedDescription
            appendLog(homebrewMessage, .warning)
            return
        }

        let missing = entries.filter { !downloadedHomebrewEntryIDs.contains($0.id) }
        guard missing.isEmpty else {
            homebrewMessage = "Download \(missing.first?.name ?? "the selected apps") before generating."
            appendLog(homebrewMessage, .warning)
            return
        }

        isGeneratingHomebrewFolder = true
        homebrewMessage = "Generating Homebrew folder..."
        appendLog("Generating Homebrew folder for \(entries.count) app\(entries.count == 1 ? "" : "s").", .info)

        Task.detached(priority: .userInitiated) { [entries, homebrewArchiveDirectory, destinationDirectory] in
            do {
                let output = try Self.generateHomebrewFolder(
                    entries: entries,
                    archiveDirectory: homebrewArchiveDirectory,
                    destinationDirectory: destinationDirectory
                )
                await MainActor.run {
                    self.isGeneratingHomebrewFolder = false
                    self.generatedHomebrewFolderURL = output
                    self.homebrewMessage = "Generated \(output.lastPathComponent)."
                    self.appendLog("Generated Homebrew folder at \(output.path).", .success)
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingHomebrewFolder = false
                    self.homebrewMessage = error.localizedDescription
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
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
            metadataProgress = 0
            metadataStatusDetail = ""
            libraryMessage = "Choose your NSP/XCI folder to build the library."
            return
        }

        isScanningLibrary = true
        metadataProgress = 0
        metadataStatusDetail = ""
        libraryMessage = "Scanning library..."
        let apiKey = cachedTheGamesDBAPIKey
        let screenScraperCredentials = cachedScreenScraperCredentials
        let hasMetadataProvider = apiKey?.isEmpty == false || screenScraperCredentials?.isComplete == true

        Task.detached(priority: .userInitiated) { [libraryDirectory] in
            do {
                let items = try Self.scanLibraryItems(in: libraryDirectory)
                let cache = Self.loadMetadataCache()
                let games = Self.groupLibraryGames(from: items, cache: cache)
                let enrichedCount = games.filter { $0.metadata != nil }.count
                let gamesNeedingMetadata = games.filter {
                    Self.needsMetadataRefresh(
                        cache[$0.id],
                        hasTheGamesDB: apiKey?.isEmpty == false,
                        hasScreenScraper: screenScraperCredentials?.isComplete == true
                    )
                }
                await MainActor.run {
                    self.libraryItems = items
                    self.libraryGames = games
                    self.isScanningLibrary = false
                    self.libraryMessage = items.isEmpty ? "No install files found in this folder." : "Found \(games.count) game\(games.count == 1 ? "" : "s") and \(items.count) install item\(items.count == 1 ? "" : "s")."
                    if games.isEmpty {
                        self.metadataMessage = hasMetadataProvider ? "No games to enrich yet." : "Add a metadata account to fetch artwork and game details."
                    } else if gamesNeedingMetadata.isEmpty {
                        self.metadataMessage = enrichedCount == 0 ? "Metadata cache is up to date. No database calls needed." : "Artwork/details loaded from cache for \(enrichedCount) game\(enrichedCount == 1 ? "" : "s"). No database calls needed."
                    } else if hasMetadataProvider {
                        self.metadataMessage = "\(gamesNeedingMetadata.count) game\(gamesNeedingMetadata.count == 1 ? "" : "s") need richer metadata."
                    } else {
                        self.metadataMessage = "Add a metadata account to fetch artwork for \(gamesNeedingMetadata.count) game\(gamesNeedingMetadata.count == 1 ? "" : "s")."
                    }
                    self.appendLog("Library scan found \(games.count) game\(games.count == 1 ? "" : "s").", .success)
                }

                guard hasMetadataProvider, !gamesNeedingMetadata.isEmpty else { return }

                await MainActor.run {
                    self.isFetchingMetadata = true
                    self.metadataProgress = 0
                    self.metadataStatusDetail = "Preparing metadata lookups..."
                    self.metadataMessage = "Fetching richer artwork/details for \(gamesNeedingMetadata.count) game\(gamesNeedingMetadata.count == 1 ? "" : "s")."
                }

                var updatedCache = cache
                let gamesToFetch = gamesNeedingMetadata
                let totalToFetch = gamesToFetch.count
                for (offset, game) in gamesToFetch.enumerated() {
                    let current = offset + 1
                    await MainActor.run {
                        self.metadataProgress = totalToFetch > 0 ? Double(offset) / Double(totalToFetch) : 0
                        self.metadataStatusDetail = "Matching \(current) of \(totalToFetch): \(game.title)"
                    }

                    do {
                        let sourceMetadata = try await Self.metadataSources(
                            for: game.title,
                            theGamesDBAPIKey: apiKey,
                            screenScraperCredentials: screenScraperCredentials
                        )
                        if let metadata = Self.combinedMetadata(from: sourceMetadata) {
                            updatedCache[game.id] = GameMetadataCacheEntry(
                                title: game.title,
                                provider: metadata.provider,
                                state: .success,
                                attemptedAt: Date(),
                                lookupPlatformID: metadata.lookupPlatformID,
                                metadata: metadata,
                                sourceMetadata: sourceMetadata,
                                message: nil
                            )
                            let gameID = game.id
                            await MainActor.run {
                                if let index = self.libraryGames.firstIndex(where: { $0.id == gameID }) {
                                    self.libraryGames[index].metadata = metadata
                                    self.libraryGames[index].sourceMetadata = sourceMetadata
                                }
                                let providers = sourceMetadata.keys.sorted().joined(separator: " + ")
                                self.metadataStatusDetail = "Matched \(current) of \(totalToFetch): \(metadata.matchedTitle) via \(providers)"
                            }
                        } else {
                            updatedCache[game.id] = GameMetadataCacheEntry(
                                title: game.title,
                                provider: "Metadata",
                                state: .noMatch,
                                attemptedAt: Date(),
                                lookupPlatformID: nil,
                                metadata: nil,
                                sourceMetadata: nil,
                                message: "No Nintendo Switch metadata match found."
                            )
                            await MainActor.run {
                                self.metadataStatusDetail = "No match for \(current) of \(totalToFetch): \(game.title)"
                            }
                        }
                    } catch {
                            updatedCache[game.id] = GameMetadataCacheEntry(
                                title: game.title,
                                provider: "Metadata",
                                state: .failed,
                                attemptedAt: Date(),
                                lookupPlatformID: nil,
                                metadata: nil,
                                sourceMetadata: nil,
                                message: error.localizedDescription
                            )
                        await MainActor.run {
                            self.metadataStatusDetail = "Failed \(current) of \(totalToFetch): \(game.title)"
                        }
                    }

                    try? Self.saveMetadataCache(updatedCache)
                    await MainActor.run {
                        self.metadataProgress = totalToFetch > 0 ? Double(current) / Double(totalToFetch) : 1
                    }
                }

                let currentGameIDs = Set(games.map(\.id))
                let currentCacheEntries = updatedCache.filter { currentGameIDs.contains($0.key) }.values
                let failedCount = currentCacheEntries.filter { $0.state == .failed }.count
                let noMatchCount = currentCacheEntries.filter { $0.state == .noMatch }.count
                await MainActor.run {
                    let enrichedCount = self.libraryGames.filter { $0.metadata != nil }.count
                    self.isFetchingMetadata = false
                    self.metadataProgress = 1
                    if enrichedCount == 0 {
                        self.metadataStatusDetail = "No metadata matches found."
                        self.metadataMessage = "Metadata cache updated. No matched artwork yet; cached misses will not be retried automatically."
                    } else {
                        var detail = "Artwork/details cached for \(enrichedCount) game\(enrichedCount == 1 ? "" : "s")."
                        if noMatchCount > 0 || failedCount > 0 {
                            detail += " \(noMatchCount + failedCount) unmatched/failed lookup\(noMatchCount + failedCount == 1 ? "" : "s") cached too."
                        }
                        self.metadataStatusDetail = "Metadata scan complete."
                        self.metadataMessage = detail
                    }
                }
            } catch {
                await MainActor.run {
                    self.libraryItems = []
                    self.libraryGames = []
                    self.isScanningLibrary = false
                    self.isFetchingMetadata = false
                    self.metadataProgress = 0
                    self.metadataStatusDetail = "Metadata scan stopped."
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
        cachedTheGamesDBAPIKey = trimmed.isEmpty ? nil : trimmed
        hasTheGamesDBAPIKey = !trimmed.isEmpty
        metadataMessage = hasAnyMetadataProvider ? "Metadata settings saved. Only new, uncached games will call databases." : "Add a metadata account to fetch artwork and game details."
        appendLog(hasTheGamesDBAPIKey ? "TGDB API key saved." : "TGDB API key cleared.", .info)
    }

    func saveScreenScraperCredentials(_ credentials: ScreenScraperCredentials) {
        let trimmed = ScreenScraperCredentials(
            devUsername: credentials.devUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            debugPassword: credentials.debugPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            softwareName: credentials.softwareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SwitchLoader" : credentials.softwareName.trimmingCharacters(in: .whitespacesAndNewlines),
            memberUsername: credentials.memberUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            memberPassword: credentials.memberPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Self.saveScreenScraperCredentials(trimmed.isComplete ? trimmed : nil)
        cachedScreenScraperCredentials = trimmed.isComplete ? trimmed : nil
        hasScreenScraperCredentials = trimmed.isComplete
        metadataMessage = hasAnyMetadataProvider ? "Metadata settings saved. Only new, uncached games will call databases." : "Add a metadata account to fetch artwork and game details."
        appendLog(hasScreenScraperCredentials ? "ScreenScraper credentials saved." : "ScreenScraper credentials cleared.", .info)
    }

    func loadScreenScraperSettingsForEditing() -> ScreenScraperCredentials {
        if cachedScreenScraperCredentials == nil {
            cachedScreenScraperCredentials = Self.loadScreenScraperCredentials()
            hasScreenScraperCredentials = cachedScreenScraperCredentials?.isComplete == true
        }
        return cachedScreenScraperCredentials ?? ScreenScraperCredentials(
            devUsername: "",
            debugPassword: "",
            softwareName: "SwitchLoader",
            memberUsername: "",
            memberPassword: ""
        )
    }

    func loadTheGamesDBAPIKeyForEditing() -> String {
        if cachedTheGamesDBAPIKey == nil {
            cachedTheGamesDBAPIKey = Self.loadTheGamesDBAPIKey()
            hasTheGamesDBAPIKey = cachedTheGamesDBAPIKey?.isEmpty == false
        }
        return cachedTheGamesDBAPIKey ?? ""
    }

    func testTheGamesDBAPIKey(_ key: String) async throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MetadataLookupError.providerRejected("Enter a TheGamesDB API key first.")
        }

        let result = try await TheGamesDBMetadataProvider(apiKey: trimmed).testConnection()
        return result
    }

    func testScreenScraperCredentials(_ credentials: ScreenScraperCredentials) async throws -> String {
        let trimmed = ScreenScraperCredentials(
            devUsername: credentials.devUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            debugPassword: credentials.debugPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            softwareName: credentials.softwareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SwitchLoader" : credentials.softwareName.trimmingCharacters(in: .whitespacesAndNewlines),
            memberUsername: credentials.memberUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            memberPassword: credentials.memberPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard trimmed.isComplete else {
            throw MetadataLookupError.providerRejected("Enter your ScreenScraper username and password. If this development build has no bundled app credentials yet, also open Advanced app credentials and fill in Dev username, Debug password, and Software name.")
        }

        return try await ScreenScraperMetadataProvider(credentials: trimmed).testConnection()
    }

    func refreshLibraryMetadata() {
        scanLibrary()
    }

    func searchMetadataMatches(for query: String) async throws -> [GameMetadataMatch] {
        let apiKey = cachedTheGamesDBAPIKey
        let screenScraperCredentials = cachedScreenScraperCredentials
        guard apiKey?.isEmpty == false || screenScraperCredentials?.isComplete == true else {
            throw MetadataLookupError.missingAPIKey
        }

        return try await Self.matches(
            for: query,
            theGamesDBAPIKey: apiKey,
            screenScraperCredentials: screenScraperCredentials
        )
    }

    func searchMetadataMatches(for query: String, provider: MetadataProviderKind) async throws -> [GameMetadataMatch] {
        let apiKey = cachedTheGamesDBAPIKey
        let screenScraperCredentials = cachedScreenScraperCredentials

        switch provider {
        case .theGamesDB:
            guard apiKey?.isEmpty == false else { throw MetadataLookupError.missingAPIKey }
            return try await Self.matches(
                for: query,
                theGamesDBAPIKey: apiKey,
                screenScraperCredentials: nil
            )
        case .screenScraper:
            guard screenScraperCredentials?.isComplete == true else { throw MetadataLookupError.missingAPIKey }
            return try await Self.matches(
                for: query,
                theGamesDBAPIKey: nil,
                screenScraperCredentials: screenScraperCredentials
            )
        }
    }

    func applyMetadataMatch(_ match: GameMetadataMatch, to game: LibraryGame) async throws {
        let apiKey = cachedTheGamesDBAPIKey
        let screenScraperCredentials = cachedScreenScraperCredentials
        guard apiKey?.isEmpty == false || screenScraperCredentials?.isComplete == true else {
            throw MetadataLookupError.missingAPIKey
        }

        let metadata = try await Self.metadata(
            for: match,
            theGamesDBAPIKey: apiKey,
            screenScraperCredentials: screenScraperCredentials
        )
        var cache = Self.loadMetadataCache()
        cache[game.id] = GameMetadataCacheEntry(
            title: game.title,
            provider: metadata.provider,
            state: .success,
            attemptedAt: Date(),
            lookupPlatformID: metadata.lookupPlatformID,
            metadata: metadata,
            sourceMetadata: [metadata.provider: metadata],
            message: "Manual match selected."
        )
        try Self.saveMetadataCache(cache)

        if let index = libraryGames.firstIndex(where: { $0.id == game.id }) {
            libraryGames[index].metadata = metadata
        }
        metadataMessage = "Manual match saved for \(game.title)."
        appendLog("Manual \(metadata.provider) match saved for \(game.title).", .success)
    }

    func applyMetadataMatch(_ match: GameMetadataMatch, to game: LibraryGame, provider: MetadataProviderKind) async throws {
        let apiKey = cachedTheGamesDBAPIKey
        let screenScraperCredentials = cachedScreenScraperCredentials

        let matchedMetadata = try await Self.metadata(
            for: match,
            theGamesDBAPIKey: provider == .theGamesDB ? apiKey : nil,
            screenScraperCredentials: provider == .screenScraper ? screenScraperCredentials : nil
        )

        var cache = Self.loadMetadataCache()
        var sourceMetadata = cache[game.id]?.availableSourceMetadata ?? game.sourceMetadata
        sourceMetadata[provider.rawValue] = matchedMetadata
        let combinedMetadata = Self.combinedMetadata(from: sourceMetadata) ?? matchedMetadata

        cache[game.id] = GameMetadataCacheEntry(
            title: game.title,
            provider: combinedMetadata.provider,
            state: .success,
            attemptedAt: Date(),
            lookupPlatformID: combinedMetadata.lookupPlatformID,
            metadata: combinedMetadata,
            sourceMetadata: sourceMetadata,
            message: "Manual \(provider.title) match selected."
        )
        try Self.saveMetadataCache(cache)

        if let index = libraryGames.firstIndex(where: { $0.id == game.id }) {
            libraryGames[index].metadata = combinedMetadata
            libraryGames[index].sourceMetadata = sourceMetadata
        }
        metadataMessage = "\(provider.title) match saved for \(game.title)."
        appendLog("Manual \(provider.title) match saved for \(game.title).", .success)
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

    func startReceiverServer() {
        guard canStartReceiverServer else { return }

        let configuration = NetworkReceiverConfiguration(files: selectedFiles)
        status = .running
        progress = 0
        receiverServerURL = nil
        receiverInstruction = "Starting the receiver server for the selected queue."
        appendLog("Starting SwitchLoader Receiver server.", .info)

        Task.detached(priority: .userInitiated) {
            let service = NetworkReceiverService()
            do {
                try service.start(configuration: configuration) { event in
                    Task { @MainActor in
                        self.handleReceiverEvent(event)
                    }
                }
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1
                    self.receiverInstruction = "Receiver transfer session ended."
                    self.appendLog("Receiver server stopped.", .success)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.receiverInstruction = "Fix the issue below, then start the receiver server again."
                    self.appendLog(error.localizedDescription, .failure)
                }
            }
        }
    }

    func sendGeneratedHomebrewFolderToReceiver() {
        guard canSendGeneratedHomebrewFolderToReceiver, let generatedHomebrewFolderURL else { return }

        status = .running
        progress = 0
        homebrewMessage = "Open SwitchLoader Receiver on the Switch, connect USB, then keep it waiting."
        appendLog("Installing generated Homebrew folder with SwitchLoader Receiver.", .info)

        Task.detached(priority: .userInitiated) {
            let sender = SwitchLoaderUSBReceiverSender()
            do {
                try sender.sendHomebrewFolder(generatedHomebrewFolderURL) { event in
                    Task { @MainActor in
                        self.handleUSBEvent(event)
                    }
                }
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1
                    self.homebrewMessage = "Homebrew install transfer complete."
                    self.appendLog("SwitchLoader Receiver Homebrew install finished.", .success)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.homebrewMessage = "Fix the issue below, set the receiver waiting again, then send."
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

    private func handleReceiverEvent(_ event: NetworkInstallEvent) {
        switch event {
        case let .log(entry):
            logs.append(entry)
            if entry.message.hasPrefix("Receiver server ready at ") {
                let value = entry.message
                    .replacingOccurrences(of: "Receiver server ready at ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                receiverServerURL = value
                receiverInstruction = "Enter \(value) in SwitchLoader Receiver."
            } else if entry.level == .success || entry.level == .info {
                receiverInstruction = entry.message
            }
        case let .progress(value):
            progress = value
        case .completed:
            status = .completed
            progress = 1
            receiverInstruction = "Receiver transfer session ended."
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
                    if let item = try? libraryItem(for: url, libraryRoot: directory, itemIsDirectory: true) {
                        items.append(item)
                    }
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            guard libraryFileExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if let item = try? libraryItem(for: url, libraryRoot: directory, itemIsDirectory: false) {
                items.append(item)
            }
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

    private nonisolated static func libraryItem(for url: URL, libraryRoot: URL, itemIsDirectory: Bool) throws -> LibraryItem {
        let metadata = libraryMetadata(for: url, libraryRoot: libraryRoot, itemIsDirectory: itemIsDirectory)
        let size = try SwitchTransferFile(url: url).size
        return LibraryItem(url: url, title: metadata.title, contentType: metadata.contentType, size: size)
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

    private func persistHomebrewArchiveDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.homebrewArchiveDirectoryDefaultsKey)

        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Self.homebrewArchiveDirectoryBookmarkDefaultsKey)
        }
    }

    private nonisolated static func restoreHomebrewArchiveDirectory() -> URL? {
        if let bookmark = UserDefaults.standard.data(forKey: homebrewArchiveDirectoryBookmarkDefaultsKey) {
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
                    UserDefaults.standard.set(freshBookmark, forKey: homebrewArchiveDirectoryBookmarkDefaultsKey)
                }
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: homebrewArchiveDirectoryDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return nil
    }

    private func persistCustomHomebrewEntries() {
        if let data = try? JSONEncoder().encode(customHomebrewEntries) {
            UserDefaults.standard.set(data, forKey: Self.customHomebrewEntriesDefaultsKey)
        }
    }

    private nonisolated static func loadCustomHomebrewEntries() -> [HomebrewCatalogEntry] {
        guard let data = UserDefaults.standard.data(forKey: customHomebrewEntriesDefaultsKey),
              let entries = try? JSONDecoder().decode([HomebrewCatalogEntry].self, from: data)
        else {
            return []
        }
        return entries.filter { !$0.isBuiltIn }
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
            let sourceMetadata = cache[id]?.availableSourceMetadata ?? [:]
            return LibraryGame(
                id: id,
                title: title,
                items: sortedItems,
                metadata: combinedMetadata(from: sourceMetadata) ?? cache[id]?.metadata,
                sourceMetadata: sourceMetadata
            )
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated static func combinedMetadata(from sources: [String: GameMetadata]) -> GameMetadata? {
        let screenScraper = sources[MetadataProviderKind.screenScraper.rawValue]
        let theGamesDB = sources[MetadataProviderKind.theGamesDB.rawValue]

        if let screenScraper, let theGamesDB {
            return screenScraper.fillingMissingValues(from: theGamesDB)
        }

        return screenScraper ?? theGamesDB ?? sources.values.first
    }

    private nonisolated static func stableGameID(for title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }

    private nonisolated static func metadataSources(
        for title: String,
        theGamesDBAPIKey: String?,
        screenScraperCredentials: ScreenScraperCredentials?
    ) async throws -> [String: GameMetadata] {
        var sources: [String: GameMetadata] = [:]
        var lastError: Error?

        if let screenScraperCredentials, screenScraperCredentials.isComplete {
            do {
                if let metadata = try await ScreenScraperMetadataProvider(credentials: screenScraperCredentials).metadata(for: title) {
                    sources[MetadataProviderKind.screenScraper.rawValue] = metadata
                }
            } catch {
                lastError = error
            }
        }

        if let theGamesDBAPIKey, !theGamesDBAPIKey.isEmpty {
            do {
                if let metadata = try await TheGamesDBMetadataProvider(apiKey: theGamesDBAPIKey).metadata(for: title) {
                    sources[MetadataProviderKind.theGamesDB.rawValue] = metadata
                }
            } catch {
                lastError = error
            }
        }

        if sources.isEmpty, let lastError {
            throw lastError
        }
        return sources
    }

    private nonisolated static func metadata(
        for title: String,
        theGamesDBAPIKey: String?,
        screenScraperCredentials: ScreenScraperCredentials?
    ) async throws -> GameMetadata? {
        let sources = try await metadataSources(
            for: title,
            theGamesDBAPIKey: theGamesDBAPIKey,
            screenScraperCredentials: screenScraperCredentials
        )
        return combinedMetadata(from: sources)
    }

    private nonisolated static func needsMetadataRefresh(
        _ entry: GameMetadataCacheEntry?,
        hasTheGamesDB: Bool,
        hasScreenScraper: Bool
    ) -> Bool {
        guard let entry else { return true }
        guard entry.state == .success else {
            return true
        }

        let sourceMetadata = entry.availableSourceMetadata
        if hasTheGamesDB, sourceMetadata[MetadataProviderKind.theGamesDB.rawValue] == nil {
            return true
        }
        if hasScreenScraper, sourceMetadata[MetadataProviderKind.screenScraper.rawValue] == nil {
            return true
        }

        guard let metadata = combinedMetadata(from: sourceMetadata) ?? entry.metadata else {
            return true
        }
        return metadata.isMissingRichArtworkOrDetails
    }

    private nonisolated static func matches(
        for query: String,
        theGamesDBAPIKey: String?,
        screenScraperCredentials: ScreenScraperCredentials?
    ) async throws -> [GameMetadataMatch] {
        var matches: [GameMetadataMatch] = []
        var lastError: Error?

        if let screenScraperCredentials, screenScraperCredentials.isComplete {
            do {
                matches.append(contentsOf: try await ScreenScraperMetadataProvider(credentials: screenScraperCredentials).matches(for: query))
            } catch {
                lastError = error
            }
        }

        if let theGamesDBAPIKey, !theGamesDBAPIKey.isEmpty {
            do {
                matches.append(contentsOf: try await TheGamesDBMetadataProvider(apiKey: theGamesDBAPIKey).matches(for: query))
            } catch {
                lastError = error
            }
        }

        if matches.isEmpty, let lastError {
            throw lastError
        }

        var seen = Set<String>()
        return matches.filter { match in
            let key = "\(match.provider):\(match.providerID)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private nonisolated static func metadata(
        for match: GameMetadataMatch,
        theGamesDBAPIKey: String?,
        screenScraperCredentials: ScreenScraperCredentials?
    ) async throws -> GameMetadata {
        switch match.provider {
        case "ScreenScraper":
            guard let screenScraperCredentials, screenScraperCredentials.isComplete else {
                throw MetadataLookupError.missingAPIKey
            }
            return try await ScreenScraperMetadataProvider(credentials: screenScraperCredentials).metadata(for: match)
        default:
            guard let theGamesDBAPIKey, !theGamesDBAPIKey.isEmpty else {
                throw MetadataLookupError.missingAPIKey
            }
            return try await TheGamesDBMetadataProvider(apiKey: theGamesDBAPIKey).metadata(for: match)
        }
    }

    private nonisolated static func loadMetadataCache() -> [String: GameMetadataCacheEntry] {
        guard let data = try? Data(contentsOf: metadataCacheURL) else { return [:] }
        if let cache = try? JSONDecoder().decode([String: GameMetadataCacheEntry].self, from: data) {
            return cache.filter { _, entry in
                if entry.provider == "TheGamesDB" {
                    return entry.lookupPlatformID == TheGamesDBMetadataProvider.nintendoSwitchPlatformID
                }
                return entry.provider == "ScreenScraper" || entry.provider == "Metadata"
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
        loadMetadataProviderCredentials().theGamesDBAPIKey
    }

    private nonisolated static func saveTheGamesDBAPIKey(_ key: String?) {
        var credentials = loadMetadataProviderCredentials()
        credentials.theGamesDBAPIKey = key
        saveMetadataProviderCredentials(credentials)
    }

    private nonisolated static func loadScreenScraperCredentials() -> ScreenScraperCredentials? {
        let credentials = loadMetadataProviderCredentials().screenScraperCredentials
        return credentials?.isComplete == true ? credentials : nil
    }

    private nonisolated static func saveScreenScraperCredentials(_ credentials: ScreenScraperCredentials?) {
        var storedCredentials = loadMetadataProviderCredentials()
        storedCredentials.screenScraperCredentials = credentials
        saveMetadataProviderCredentials(storedCredentials)
    }

    private nonisolated static func loadMetadataProviderCredentials() -> MetadataProviderCredentials {
        guard let data = try? Data(contentsOf: metadataProviderCredentialsURL),
              let credentials = try? JSONDecoder().decode(MetadataProviderCredentials.self, from: data)
        else {
            return MetadataProviderCredentials(theGamesDBAPIKey: nil, screenScraperCredentials: nil)
        }
        return credentials
    }

    private nonisolated static func saveMetadataProviderCredentials(_ credentials: MetadataProviderCredentials) {
        let url = metadataProviderCredentialsURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(credentials)
            try data.write(to: url, options: .atomic)
        } catch {
            // Credential persistence should not block normal app use.
        }
    }

    private nonisolated static var metadataProviderCredentialsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("SwitchLoader", isDirectory: true)
            .appendingPathComponent("MetadataProviders.json")
    }

    private nonisolated static let defaultHomebrewCatalog: [HomebrewCatalogEntry] = [
        homebrew("nx-hbmenu", "switchbrew/nx-hbmenu", .launcher, "The Nintendo Switch Homebrew Menu."),
        homebrew("sphaira", "ITotalJustice/sphaira", .launcher, "A modern homebrew menu for Nintendo Switch."),
        homebrew("uLaunch", "XorTroll/uLaunch", .launcher, "Themeable HOME menu replacement for Nintendo Switch."),
        homebrew("HekateBrew", "bemardev/HekateBrew", .launcher, "Homebrew companion for Hekate and payload launching."),
        homebrew("JKSV", "J-D-K/JKSV", .saves, "Save manager for Nintendo Switch."),
        homebrew("Amiigo", "CompSciOrBust/Amiigo", .utility, "Amiibo management UI for emuiibo setups."),
        homebrew("AmiiSwap", "FuryBaguette/AmiiSwap", .utility, "GUI amiibo manager for emuiibo."),
        homebrew("AmiiboGenerator", "Slluxx/AmiiboGenerator", .utility, "Generate amiibo data directly on Switch."),
        homebrew("MiiPort", "Genwald/MiiPort", .utility, "Import and export Mii data."),
        homebrew("SwitchVerifier", "LotP1/SwitchVerifier", .utility, "Generate verification tokens from a Switch."),
        homebrew("battery_desync_fix_nx", "CTCaer/battery_desync_fix_nx", .utility, "Battery desync repair utility."),
        homebrew("NX-Shell", "joel16/NX-Shell", .files, "Multi-purpose file manager for Nintendo Switch."),
        homebrew("N-Xplorer", "CompSciOrBust/N-Xplorer", .files, "Multi-functional file manager."),
        homebrew("NXGallery", "iUltimateLP/NXGallery", .files, "Transfer screenshots to a phone or computer."),
        homebrew("NXShare", "musebrot1/NXShare", .files, "Browse the Switch album from another device."),
        homebrew("Moonlight-Switch", "XITRIX/Moonlight-Switch", .media, "Moonlight streaming client for Nintendo Switch."),
        homebrew("TriPlayer", "tallbl0nde/TriPlayer", .media, "Background audio player for Atmosphere."),
        homebrew("PlayerNX", "XorTroll/PlayerNX", .media, "Video player homebrew using FFmpeg libraries."),
        homebrew("FlashNX", "Jonathan8520/FlashNX", .media, "Flash player powered by Ruffle."),
        homebrew("eBookReaderNX", "reworks-org/eBookReaderNX", .media, "EPUB eBook reader for Nintendo Switch."),
        homebrew("SwitchTV", "peterrauscher/SwitchTV", .media, "Twitch client for Switch homebrew."),
        homebrew("switchcord", "vbe0201/switchcord", .media, "Unofficial Discord client for Nintendo Switch."),
        homebrew("wiliwili", "xfangfang/wiliwili", .media, "Bilibili client that also supports Nintendo Switch."),
        homebrew("switchfin", "dragonflylee/switchfin", .media, "Native Jellyfin client for Nintendo Switch."),
        homebrew("TsVitch", "giovannimirulla/TsVitch", .media, "TV/IPTV client for Nintendo Switch."),
        homebrew("lennytube", "noirscape/lennytube", .media, "YouTube client in NRO format."),
        homebrew("SimpleModManager", "nadrino/SimpleModManager", .modding, "Simple on-device mod manager."),
        homebrew("SimpleModDownloader", "PoloNX/SimpleModDownloader", .modding, "Download supported mods from GameBanana."),
        homebrew("ARCropolis", "Raytwo/ARCropolis", .modding, "Modding framework for Super Smash Bros. Ultimate."),
        homebrew("Switchseerr", "PoloNX/Switchseerr", .utility, "Third-party Jellyseerr client."),
        homebrew("CaptureSight", "zaksabeast/CaptureSight", .overlay, "Overlay for viewing supported Pokemon game info."),
        homebrew("PNGShot", "J-D-K/PNGShot", .sysmodule, "Export screenshots as PNG files."),
        homebrew("SwitchPresence-Rewritten", "SunResearchInstitute/SwitchPresence-Rewritten", .sysmodule, "Discord rich presence sysmodule server."),
        homebrew("SwitchPresence", "Random06457/SwitchPresence", .sysmodule, "Discord rich presence sysmodule."),
        homebrew("sys-clk", "retronx-team/sys-clk", .sysmodule, "Clock management sysmodule and frontend."),
        homebrew("sys-clk-Overlay", "SunResearchInstitute/sys-clk-Overlay", .overlay, "Overlay editor for sys-clk configuration."),
        homebrew("Horizon-OC", "Horizon-OC/Horizon-OC", .utility, "Open source overclocking tool for Atmosphere."),
        homebrew("kdeconnect-nx", "timschneeb/kdeconnect-nx", .sysmodule, "KDE Connect client as sysmodule and overlay."),
        homebrew("twili", "misson20000/twili", .development, "Homebrew debug monitor for Nintendo Switch."),
        homebrew("SwiTAS", "TheGreatRambler/SwiTAS", .development, "Toolkit for tool-assisted workflows with homebrew."),
        homebrew("libnx", "switchbrew/libnx", .development, "Core library for Switch homebrew development."),
        homebrew("deko3d", "devkitPro/deko3d", .development, "Low-level graphics API for Switch homebrew."),
        homebrew("borealis", "natinusala/borealis", .development, "Controller and TV-oriented UI library."),
        homebrew("Plutonium", "XorTroll/Plutonium", .development, "SDL2-based UI framework for Switch homebrew."),
        homebrew("nx.js", "TooTallNate/nx.js", .development, "JavaScript runtime for Switch homebrew apps."),
        homebrew("SwiftNX", "mitchtreece/SwiftNX", .development, "Swift homebrew framework for Nintendo Switch."),
        homebrew("ONScripter-NX", "clamintus/ONScripter-NX", .media, "ONScripter visual novel engine port."),
        homebrew("unreal_nx", "fgsfdsfgs/unreal_nx", .media, "Unreal/Unreal Gold port loader for Nintendo Switch."),
        homebrew("botw-unexplored", "lud99/botw-unexplored", .utility, "View unexplored Breath of the Wild save locations."),
        homebrew("totk-unexplored", "lud99/totk-unexplored", .utility, "View unexplored Tears of the Kingdom save collectibles.")
    ]

    private nonisolated static func homebrew(
        _ name: String,
        _ repository: String,
        _ category: HomebrewCategory,
        _ summary: String
    ) -> HomebrewCatalogEntry {
        HomebrewCatalogEntry(
            name: name,
            summary: summary,
            repositoryURL: URL(string: "https://github.com/\(repository)")!,
            category: category,
            isBuiltIn: true
        )
    }

    private nonisolated static func homebrewEntryHasDownloads(_ entry: HomebrewCatalogEntry, in archiveDirectory: URL) -> Bool {
        let directory = homebrewEntryArchiveDirectory(entry, in: archiveDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return contents.contains { $0.lastPathComponent != "manifest.json" }
    }

    private nonisolated static func downloadHomebrewEntry(_ entry: HomebrewCatalogEntry, to archiveDirectory: URL) async throws -> Int {
        let didAccess = archiveDirectory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                archiveDirectory.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

        let assets = try await latestReleaseAssets(for: entry).filter { isInstallableHomebrewAsset($0.name) }
        guard !assets.isEmpty else {
            throw HomebrewLibraryError.noReleaseAssets(entry.name)
        }

        let target = homebrewEntryArchiveDirectory(entry, in: archiveDirectory)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

        var savedAssets: [String] = []
        for asset in assets {
            let (downloadedURL, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HomebrewLibraryError.downloadFailed("GitHub download failed for \(asset.name).")
            }

            let destination = target.appendingPathComponent(safeFileName(asset.name))
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: downloadedURL, to: destination)
            savedAssets.append(destination.lastPathComponent)
        }

        let manifest = HomebrewArchiveManifest(
            name: entry.name,
            repositoryURL: entry.repositoryURL,
            downloadedAt: Date(),
            assets: savedAssets
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: target.appendingPathComponent("manifest.json"), options: .atomic)
        return savedAssets.count
    }

    private nonisolated static func latestReleaseAssets(for entry: HomebrewCatalogEntry) async throws -> [GitHubReleaseAsset] {
        guard let repository = HomebrewCatalogEntry.repositoryName(from: entry.repositoryURL),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else {
            throw HomebrewLibraryError.invalidGitHubURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwitchLoader", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw HomebrewLibraryError.noReleaseAssets(entry.name)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HomebrewLibraryError.downloadFailed("GitHub returned \(http.statusCode) for \(entry.name).")
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return release.assets
    }

    private nonisolated static func generateHomebrewFolder(
        entries: [HomebrewCatalogEntry],
        archiveDirectory: URL,
        destinationDirectory: URL
    ) throws -> URL {
        let archiveAccess = archiveDirectory.startAccessingSecurityScopedResource()
        let destinationAccess = destinationDirectory.startAccessingSecurityScopedResource()
        defer {
            if archiveAccess {
                archiveDirectory.stopAccessingSecurityScopedResource()
            }
            if destinationAccess {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let output = destinationDirectory.appendingPathComponent("SwitchLoader Homebrew Pack \(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        for entry in entries {
            let source = homebrewEntryArchiveDirectory(entry, in: archiveDirectory)
            guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                  !files.isEmpty
            else {
                throw HomebrewLibraryError.generateFailed("\(entry.name) is not downloaded yet.")
            }

            for file in files where file.lastPathComponent != "manifest.json" {
                try placeHomebrewAsset(file, for: entry, into: output)
            }
        }

        return output
    }

    private nonisolated static func placeHomebrewAsset(_ file: URL, for entry: HomebrewCatalogEntry, into output: URL) throws {
        let fileManager = FileManager.default
        switch file.pathExtension.lowercased() {
        case "zip":
            let temporary = fileManager.temporaryDirectory
                .appendingPathComponent("SwitchLoader-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: temporary)
            }
            try expandZip(file, into: temporary)
            try placeExtractedHomebrewFolder(temporary, for: entry, into: output)
        case "nro":
            let target = output
                .appendingPathComponent("switch", isDirectory: true)
                .appendingPathComponent(safeFileName(entry.name), isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try copyReplacing(file, to: target.appendingPathComponent(file.lastPathComponent))
        case "ovl":
            let target = output.appendingPathComponent("switch/.overlays", isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try copyReplacing(file, to: target.appendingPathComponent(file.lastPathComponent))
        case "kip":
            let target = output.appendingPathComponent("atmosphere/kips", isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try copyReplacing(file, to: target.appendingPathComponent(file.lastPathComponent))
        default:
            let target = output
                .appendingPathComponent("Homebrew Assets", isDirectory: true)
                .appendingPathComponent(safeFileName(entry.name), isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try copyReplacing(file, to: target.appendingPathComponent(file.lastPathComponent))
        }
    }

    private nonisolated static func placeExtractedHomebrewFolder(_ extracted: URL, for entry: HomebrewCatalogEntry, into output: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let installRootNames: Set<String> = ["atmosphere", "bootloader", "config", "switch", "themes"]
        let hasInstallRoot = contents.contains { installRootNames.contains($0.lastPathComponent.lowercased()) }

        if hasInstallRoot {
            for item in contents {
                try copyMerging(item, to: output.appendingPathComponent(item.lastPathComponent))
            }
            return
        }

        let nroFiles = recursiveFiles(in: extracted).filter { $0.pathExtension.localizedCaseInsensitiveCompare("nro") == .orderedSame }
        if !nroFiles.isEmpty {
            let target = output
                .appendingPathComponent("switch", isDirectory: true)
                .appendingPathComponent(safeFileName(entry.name), isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            for nro in nroFiles {
                try copyReplacing(nro, to: target.appendingPathComponent(nro.lastPathComponent))
            }
            return
        }

        let target = output
            .appendingPathComponent("Homebrew Assets", isDirectory: true)
            .appendingPathComponent(safeFileName(entry.name), isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for item in contents {
            try copyMerging(item, to: target.appendingPathComponent(item.lastPathComponent))
        }
    }

    private nonisolated static func recursiveFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }

    private nonisolated static func expandZip(_ zip: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HomebrewLibraryError.generateFailed("Could not expand \(zip.lastPathComponent).")
        }
    }

    private nonisolated static func copyMerging(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for child in children {
                try copyMerging(child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            try copyReplacing(source, to: destination)
        }
    }

    private nonisolated static func copyReplacing(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private nonisolated static func homebrewEntryArchiveDirectory(_ entry: HomebrewCatalogEntry, in archiveDirectory: URL) -> URL {
        archiveDirectory.appendingPathComponent(safeFileName(entry.name), isDirectory: true)
    }

    private nonisolated static func safeFileName(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[/:]+"#, with: "-", options: .regularExpression)
        return cleaned.isEmpty ? "Homebrew" : cleaned
    }

    private nonisolated static func isInstallableHomebrewAsset(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        let extensionAllowed = ["nro", "zip", "ovl", "kip"].contains(URL(fileURLWithPath: lowercased).pathExtension)
        guard extensionAllowed else { return false }
        let blockedTerms = ["source-code", "source_code", "src-only"]
        return !blockedTerms.contains { lowercased.contains($0) }
    }
}

private struct HomebrewArchiveManifest: Codable, Sendable {
    let name: String
    let repositoryURL: URL
    let downloadedAt: Date
    let assets: [String]
}

private struct GitHubRelease: Decodable, Sendable {
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct ScreenScraperMetadataProvider: Sendable {
    let credentials: ScreenScraperCredentials
    private static let nintendoSwitchSystemIDCacheKey = "SwitchLoader.ScreenScraper.NintendoSwitchSystemID"

    func metadata(for title: String) async throws -> GameMetadata? {
        guard let game = try await findGames(named: title).max(by: { score($0.name, against: title) < score($1.name, against: title) })
        else {
            return nil
        }
        return game.metadata
    }

    func matches(for title: String) async throws -> [GameMetadataMatch] {
        try await findGames(named: title).map(\.match)
    }

    func testConnection() async throws -> String {
        do {
            _ = try await jsonObject(endpoint: "ssinfraInfos.php", queryItems: appQuery())
        } catch {
            throw MetadataLookupError.providerRejected("ScreenScraper app credentials failed before member login. Check Advanced app credentials: Dev username, Debug password, and Software name.\n\n\(error.localizedDescription)")
        }

        let object = try await jsonObject(endpoint: "ssuserInfos.php", queryItems: baseQuery())
        let response = object["response"] as? [String: Any]
        let user = response?["ssuser"] as? [String: Any]
            ?? object["ssuser"] as? [String: Any]
            ?? response
            ?? object

        let name = Self.stringValue(from: user["id"] ?? user["pseudo"] ?? user["username"])
            ?? credentials.memberUsername
        let requestsToday = Self.stringValue(from: user["requeststoday"] ?? user["requestcount"])
        let maxRequests = Self.stringValue(from: user["maxrequestsperday"])
        let threads = Self.stringValue(from: user["maxthreads"])

        var details = ["Connected to ScreenScraper as \(name)."]
        if let requestsToday, let maxRequests {
            details.append("Requests today: \(requestsToday) / \(maxRequests).")
        }
        if let threads {
            details.append("Allowed threads: \(threads).")
        }
        return details.joined(separator: "\n")
    }

    func metadata(for match: GameMetadataMatch) async throws -> GameMetadata {
        let parts = match.providerID.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2, let game = try await loadGameInfo(gameID: parts[0], systemID: parts[1]) {
            return game.metadata
        }

        return GameMetadata(
            provider: "ScreenScraper",
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
            bannerImageURL: nil,
            artworkImageURL: nil,
            coverImageURL: nil,
            logoImageURL: nil,
            screenshotImageURLs: []
        )
    }

    private func findGames(named title: String) async throws -> [RemoteGame] {
        var combined: [RemoteGame] = []
        let systemID = try? await nintendoSwitchSystemID()
        var lastError: Error?
        for searchTerm in Self.searchTerms(for: title) {
            var query = baseQuery()
            query.append(URLQueryItem(name: "recherche", value: searchTerm))
            if let systemID {
                query.append(URLQueryItem(name: "systemeid", value: String(systemID)))
            }

            do {
                let object = try await jsonObject(endpoint: "jeuRecherche.php", queryItems: query, timeout: 40)
                combined.append(contentsOf: Self.games(from: object))
                if !combined.isEmpty { break }
            } catch {
                lastError = error
            }
        }

        let games = Self.deduplicatedGames(combined)
        if games.isEmpty, let lastError {
            throw lastError
        }
        if systemID == nil {
            let filtered = games.filter(\.isNintendoSwitchRelease)
            return filtered.isEmpty ? games.sorted { score($0.name, against: title) > score($1.name, against: title) } : filtered
        }
        return games.sorted { score($0.name, against: title) > score($1.name, against: title) }
    }

    private func loadGameInfo(gameID: Int, systemID: Int) async throws -> RemoteGame? {
        var query = baseQuery()
        query.append(URLQueryItem(name: "gameid", value: String(gameID)))
        query.append(URLQueryItem(name: "systemeid", value: String(systemID)))
        query.append(URLQueryItem(name: "romtype", value: "rom"))
        query.append(URLQueryItem(name: "romnom", value: "SwitchLoader"))
        query.append(URLQueryItem(name: "romtaille", value: "1"))

        let object = try await jsonObject(endpoint: "jeuInfos.php", queryItems: query)
        return Self.games(from: object).first
    }

    private func nintendoSwitchSystemID() async throws -> Int? {
        let cachedID = UserDefaults.standard.integer(forKey: Self.nintendoSwitchSystemIDCacheKey)
        if cachedID > 0 {
            return cachedID
        }

        let object = try await jsonObject(endpoint: "systemesListe.php", queryItems: baseQuery())
        let systems = Self.array(named: "systemes", or: "systeme", in: object)
        let systemID = systems.compactMap(RemoteSystem.init(dictionary:)).first { system in
            let names = system.names.joined(separator: " ")
            return names.localizedCaseInsensitiveContains("switch")
                && !names.localizedCaseInsensitiveContains("switch 2")
        }?.id
        if let systemID {
            UserDefaults.standard.set(systemID, forKey: Self.nintendoSwitchSystemIDCacheKey)
        }
        return systemID
    }

    private func baseQuery() -> [URLQueryItem] {
        appQuery() + [
            URLQueryItem(name: "ssid", value: credentials.memberUsername),
            URLQueryItem(name: "sspassword", value: credentials.memberPassword)
        ]
    }

    private func appQuery() -> [URLQueryItem] {
        [
            URLQueryItem(name: "devid", value: credentials.devUsername),
            URLQueryItem(name: "devpassword", value: credentials.debugPassword),
            URLQueryItem(name: "softname", value: credentials.softwareName),
            URLQueryItem(name: "output", value: "json")
        ]
    }

    private func jsonObject(endpoint: String, queryItems: [URLQueryItem], timeout: TimeInterval = 25) async throws -> [String: Any] {
        guard var components = URLComponents(string: "https://api.screenscraper.fr/api2/\(endpoint)") else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw MetadataLookupError.providerTimedOut("ScreenScraper")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MetadataLookupError.providerRejected(Self.screenScraperErrorMessage(statusCode: http.statusCode, message: message))
        }

        let object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let message = Self.errorMessage(in: object) {
            throw MetadataLookupError.providerRejected("ScreenScraper rejected the request: \(message)")
        }
        return object
    }

    private static func searchTerms(for title: String) -> [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var terms = [trimmed]
        let romanToNumber: [(String, String)] = [
            (" VIII", " 8"),
            (" VII", " 7"),
            (" VI", " 6"),
            (" IV", " 4"),
            (" IX", " 9"),
            (" V", " 5"),
            (" III", " 3"),
            (" II", " 2")
        ]
        for (roman, number) in romanToNumber {
            if trimmed.range(of: roman, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                terms.append(trimmed.replacingOccurrences(of: roman, with: number, options: [.caseInsensitive, .diacriticInsensitive]))
            }
        }

        return terms.reduce(into: []) { result, term in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(term) == .orderedSame }) {
                result.append(term)
            }
        }
    }

    private static func deduplicatedGames(_ games: [RemoteGame]) -> [RemoteGame] {
        var seen = Set<String>()
        return games.filter { game in
            let key = game.providerID
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
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

    private static func games(from object: [String: Any]) -> [RemoteGame] {
        if let response = object["response"] as? [String: Any] {
            let games = array(named: "jeux", or: "jeu", in: response).compactMap(RemoteGame.init(dictionary:))
            if !games.isEmpty { return games }
            if let game = response["jeu"] as? [String: Any], let remote = RemoteGame(dictionary: game) {
                return [remote]
            }
        }

        let games = array(named: "jeux", or: "jeu", in: object).compactMap(RemoteGame.init(dictionary:))
        if !games.isEmpty { return games }
        if let game = object["jeu"] as? [String: Any], let remote = RemoteGame(dictionary: game) {
            return [remote]
        }
        return []
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        let candidates: [Any?] = [
            object["erreur"],
            object["error"],
            object["message"],
            (object["response"] as? [String: Any])?["erreur"],
            (object["response"] as? [String: Any])?["error"],
            (object["response"] as? [String: Any])?["message"],
            (object["header"] as? [String: Any])?["erreur"],
            (object["header"] as? [String: Any])?["error"],
            (object["header"] as? [String: Any])?["message"]
        ]

        return candidates.compactMap { value in
            if let string = stringValue(from: value) { return string }
            if let dictionary = value as? [String: Any] {
                return dictionary.values.compactMap { stringValue(from: $0) }.first { !$0.isEmpty }
            }
            return nil
        }.first
    }

    private static func screenScraperErrorMessage(statusCode: Int, message: String?) -> String {
        let raw = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let explanation: String
        if raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .localizedCaseInsensitiveContains("identifiants utilisateurs") {
            explanation = "ScreenScraper accepted the app/debug side, but rejected the member username/password. Try the Password shown on your ScreenScraper account/API page for the member password field. Do not use the Debug Password there."
        } else if raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .localizedCaseInsensitiveContains("identifiants developpeur") {
            explanation = "ScreenScraper rejected the Advanced app credentials. Check Dev username, Debug password, and Software name."
        } else {
            explanation = "ScreenScraper rejected the request."
        }

        return "\(explanation)\n\nHTTP \(statusCode)\(raw.isEmpty ? "" : ": \(raw)")"
    }

    private static func stringValue(from value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func array(named plural: String, or singular: String, in dictionary: [String: Any]) -> [[String: Any]] {
        if let array = dictionary[plural] as? [[String: Any]] {
            return array
        }
        if let wrapper = dictionary[plural] as? [String: Any] {
            if let array = wrapper[singular] as? [[String: Any]] {
                return array
            }
            if let item = wrapper[singular] as? [String: Any] {
                return [item]
            }
        }
        if let array = dictionary[singular] as? [[String: Any]] {
            return array
        }
        if let item = dictionary[singular] as? [String: Any] {
            return [item]
        }
        return []
    }

    private struct RemoteSystem {
        let id: Int
        let names: [String]

        init?(dictionary: [String: Any]) {
            guard let id = Self.intValue(from: dictionary["id"]) else { return nil }
            self.id = id
            self.names = Self.strings(from: dictionary["noms"]) + Self.strings(from: dictionary["nom"]) + Self.strings(from: dictionary["name"])
        }

        private static func intValue(from value: Any?) -> Int? {
            if let int = value as? Int { return int }
            if let string = value as? String { return Int(string) }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }

        private static func strings(from value: Any?) -> [String] {
            if let string = value as? String, !string.isEmpty { return [string] }
            if let dictionary = value as? [String: Any] {
                return dictionary.values.compactMap { $0 as? String }.filter { !$0.isEmpty }
            }
            return []
        }
    }

    private struct RemoteGame {
        let id: Int
        let systemID: Int?
        let name: String
        let summary: String?
        let releaseDate: String?
        let rating: String?
        let players: String?
        let youtubeURL: URL?
        let genres: [String]
        let developers: [String]
        let publishers: [String]
        let aliases: [String]
        let platformName: String?
        let mediaURLs: [String: [URL]]

        var match: GameMetadataMatch {
            GameMetadataMatch(
                provider: "ScreenScraper",
                providerID: providerID,
                title: name,
                summary: summary,
                releaseDate: releaseDate,
                platformName: platformName,
                rating: rating,
                players: players,
                coop: nil,
                youtubeURL: youtubeURL,
                aliases: aliases,
                genres: genres,
                developers: developers,
                publishers: publishers
            )
        }

        var metadata: GameMetadata {
            GameMetadata(
                provider: "ScreenScraper",
                providerID: providerID,
                matchedTitle: name,
                summary: summary,
                releaseDate: releaseDate,
                platformName: platformName ?? "Nintendo Switch",
                rating: rating,
                players: players,
                coop: nil,
                youtubeURL: youtubeURL,
                aliases: aliases,
                genres: genres,
                developers: developers,
                publishers: publishers,
                bannerImageURL: preferredURL(types: ["banner", "steamgrid", "wheel", "wheelhd", "marquee", "fanart", "background"]),
                artworkImageURL: preferredURL(types: ["fanart", "background", "steamgrid", "screenshot", "ss", "bezel"]),
                coverImageURL: preferredURL(types: ["box2d", "box3d", "cover", "boxfront", "steamcard"]),
                logoImageURL: preferredURL(types: ["clearart", "clearlogo", "wheelhd", "wheel", "logo", "marquee", "title"]),
                screenshotImageURLs: urls(types: ["screenshot", "ss", "fanart", "background", "steamgrid"])
            )
        }

        var providerID: String {
            if let systemID {
                return "\(id):\(systemID)"
            }
            return "\(id)"
        }

        var isNintendoSwitchRelease: Bool {
            platformName?.localizedCaseInsensitiveContains("switch") == true
        }

        init?(dictionary: [String: Any]) {
            guard let id = Self.intValue(from: dictionary["id"] ?? dictionary["gameid"] ?? dictionary["jeu_id"]),
                  let name = Self.localizedText(from: dictionary["noms"])
                    ?? Self.stringValue(from: dictionary["nom"])
                    ?? Self.stringValue(from: dictionary["name"])
                    ?? Self.stringValue(from: dictionary["titre"])
            else {
                return nil
            }

            self.id = id
            let system = dictionary["systeme"] as? [String: Any]
            self.systemID = Self.intValue(from: system?["id"] ?? dictionary["systemeid"] ?? dictionary["systeme_id"])
            self.name = name
            self.summary = Self.localizedText(from: dictionary["synopsis"] ?? dictionary["synopsys"] ?? dictionary["overview"])
            self.releaseDate = Self.stringValue(from: dictionary["dates"] ?? dictionary["date"] ?? dictionary["releasedate"])
            self.rating = Self.localizedText(from: dictionary["classification"] ?? dictionary["classifications"] ?? dictionary["rating"])
            self.players = Self.stringValue(from: dictionary["joueurs"] ?? dictionary["nbjoueurs"] ?? dictionary["players"])
            self.youtubeURL = Self.youtubeURL(from: dictionary["youtube"] ?? dictionary["video"] ?? dictionary["trailer"])
            self.genres = Self.localizedList(from: dictionary["genres"] ?? dictionary["genre"])
            self.developers = Self.localizedList(from: dictionary["developpeur"] ?? dictionary["developer"] ?? dictionary["developpeurs"])
            self.publishers = Self.localizedList(from: dictionary["editeur"] ?? dictionary["publisher"] ?? dictionary["editeurs"])
            self.aliases = Self.localizedList(from: dictionary["noms"]) .filter { $0 != name }
            self.platformName = Self.localizedText(from: system?["noms"]) ?? Self.stringValue(from: system?["nom"]) ?? Self.stringValue(from: dictionary["systeme"])
            self.mediaURLs = Self.mediaURLs(from: dictionary["medias"] ?? dictionary["media"])
        }

        private func preferredURL(types: [String]) -> URL? {
            urls(types: types).first
        }

        private func urls(types: [String]) -> [URL] {
            var seen = Set<URL>()
            return types.flatMap { type in
                mediaURLs[Self.normalizedMediaType(type)] ?? []
            }.filter { url in
                guard !seen.contains(url) else { return false }
                seen.insert(url)
                return true
            }
        }

        private static func mediaURLs(from value: Any?) -> [String: [URL]] {
            let dictionaries: [[String: Any]]
            if let array = value as? [[String: Any]] {
                dictionaries = array
            } else if let dictionary = value as? [String: Any],
                      let array = dictionary["media"] as? [[String: Any]] {
                dictionaries = array
            } else if let dictionary = value as? [String: Any] {
                dictionaries = dictionary.values.compactMap { $0 as? [String: Any] }
            } else {
                dictionaries = []
            }

            var result: [String: [URL]] = [:]
            for dictionary in dictionaries {
                guard let type = stringValue(from: dictionary["type"] ?? dictionary["nomcourt"] ?? dictionary["media"]) else { continue }
                let url = urlValue(from: dictionary["url"] ?? dictionary["url_media"] ?? dictionary["media"] ?? dictionary["link"])
                if let url {
                    result[normalizedMediaType(type), default: []].append(url)
                }
            }
            return result
        }

        private static func normalizedMediaType(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: "", options: .regularExpression)
                .lowercased()
        }

        private static func localizedText(from value: Any?) -> String? {
            if let string = stringValue(from: value), !string.isEmpty {
                return string
            }
            if let dictionary = value as? [String: Any] {
                for key in ["text", "nom_en", "synopsis_en", "value", "en", "us", "wor", "ss", "nom", "name"] {
                    if let text = stringValue(from: dictionary[key]), !text.isEmpty {
                        return text
                    }
                }
                return dictionary.values.compactMap { stringValue(from: $0) }.first { !$0.isEmpty }
            }
            if let array = value as? [[String: Any]] {
                let preferred = array.first { dictionary in
                    let region = stringValue(from: dictionary["region"] ?? dictionary["langue"] ?? dictionary["lang"]) ?? ""
                    return ["en", "us", "uk", "wor", "ss"].contains { region.localizedCaseInsensitiveContains($0) }
                }
                return localizedText(from: preferred ?? array.first)
            }
            return nil
        }

        private static func localizedList(from value: Any?) -> [String] {
            if let text = localizedText(from: value) {
                return [text]
            }
            if let array = value as? [[String: Any]] {
                return array.compactMap { localizedText(from: $0) }
            }
            if let array = value as? [Any] {
                return array.compactMap { localizedText(from: $0) }
            }
            return []
        }

        private static func stringValue(from value: Any?) -> String? {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            return nil
        }

        private static func intValue(from value: Any?) -> Int? {
            if let int = value as? Int { return int }
            if let string = stringValue(from: value) { return Int(string) }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }

        private static func urlValue(from value: Any?) -> URL? {
            guard let string = stringValue(from: value) else { return nil }
            return URL(string: string)
        }

        private static func youtubeURL(from value: Any?) -> URL? {
            guard let string = stringValue(from: value) else { return nil }
            if string.localizedCaseInsensitiveContains("youtube"),
               let url = URL(string: string) {
                return url
            }
            return URL(string: "https://www.youtube.com/watch?v=\(string)")
        }
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

    func testConnection() async throws -> String {
        let matches = try await matches(for: "Mario Kart 8 Deluxe")
        if matches.isEmpty {
            return "Connected to TheGamesDB, but the test lookup returned no Nintendo Switch matches."
        }
        return "Connected to TheGamesDB.\nTest lookup found \(matches.count) Nintendo Switch match\(matches.count == 1 ? "" : "es")."
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
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MetadataLookupError.providerRejected("TheGamesDB returned HTTP \(http.statusCode)\(message?.isEmpty == false ? ": \(message!)" : ".")")
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
