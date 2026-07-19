import SwiftUI
import WebKit

struct YouTubeTrailer: Identifiable {
    let title: String
    let videoKey: String
    let watchURL: URL?

    var id: String {
        videoKey
    }

    init?(title: String, url: URL) {
        guard let key = Self.videoKey(from: url) else { return nil }
        self.title = title
        self.videoKey = key
        self.watchURL = url
    }

    private static func videoKey(from url: URL) -> String? {
        if url.host?.localizedCaseInsensitiveContains("youtu.be") == true {
            return cleanedKey(url.pathComponents.dropFirst().first)
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let key = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return cleanedKey(key)
        }

        let pathParts = url.pathComponents.filter { $0 != "/" }
        if let embedIndex = pathParts.firstIndex(where: { ["embed", "shorts", "live"].contains($0.lowercased()) }),
           pathParts.indices.contains(pathParts.index(after: embedIndex)) {
            return cleanedKey(pathParts[pathParts.index(after: embedIndex)])
        }

        return cleanedKey(url.absoluteString)
    }

    private static func cleanedKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = trimmed.unicodeScalars.prefix { allowed.contains($0) }
        let key = String(String.UnicodeScalarView(scalars))
        return key.isEmpty ? nil : key
    }
}

struct TrailerPlayerSheet: View {
    let trailer: YouTubeTrailer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(trailer.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let watchURL = trailer.watchURL {
                    Link("Open in YouTube", destination: watchURL)
                        .font(.callout)
                        .help("Some trailers block embedding. Open on YouTube if playback fails.")
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            YouTubeEmbedView(videoKey: trailer.videoKey)
                .frame(width: 854, height: 480)
                .background(.black)
        }
        .frame(width: 854)
    }
}

struct YouTubeEmbedView: NSViewRepresentable {
    let videoKey: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="initial-scale=1.0">
        <style>
        html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
        iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
        </style>
        </head>
        <body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoKey)?autoplay=1&rel=0&playsinline=1"
                allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
                allowfullscreen></iframe>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
