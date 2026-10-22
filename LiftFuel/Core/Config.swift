import Foundation

/// App-wide constants. Change the coach model or proxy URL here.
enum AppConfig {
    // MARK: Claude

    /// Default model for the nutrition coach.
    static let claudeModel = "claude-sonnet-5-5"
    static let anthropicVersion = "2026-10-21"
    /// Opt into server-side refusal fallback (Claude API only, passed through the proxy).
    static let anthropicBeta = "server-side-fallback-2026-07-01"
    static let maxTokens = 8_000
    /// Chat is latency-sensitive; low effort keeps replies fast.
    static let effort = "low"
    /// How many prior chat messages are sent as context.
    static let historyMessageLimit = 16
    /// Safety cap on tool-use round trips within one user turn.
    static let maxToolIterations = 5
    static let requestTimeout: TimeInterval = 60
    /// Long edge of uploaded meal photos.
    static let imageMaxDimension: CGFloat = 1024
    static let imageJPEGQuality: CGFloat = 0.7

    // MARK: Backend proxy

    /// Your deployed Cloudflare Worker (see backend/README.md). Can be changed in Settings.
    static let defaultProxyBaseURL = "https://lift-fuel-proxy.example.workers.dev"
    static let directAPIBaseURL = "https://api.anthropic.com"

    // MARK: Development-only direct key

    /// DEVELOPMENT ONLY. Read from the git-ignored Config/Secrets.xcconfig via Info.plist.
    /// Always nil in Release builds, so the key can never ship.
    static var devAPIKey: String? {
        #if DEBUG
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ClaudeDevAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        #else
        return nil
        #endif
    }
}

/// Where coach requests go. Persisted in UserDefaults; the app token lives in the Keychain.
enum CoachConnection {
    enum Mode: String, CaseIterable, Identifiable {
        case proxy
        case directDevelopment

        var id: String { rawValue }
        var title: String {
            switch self {
            case .proxy: String(localized: "Secure proxy")
            case .directDevelopment: String(localized: "Direct API (development only)")
            }
        }
    }

    private static let modeKey = "coach.connectionMode"
    private static let proxyURLKey = "coach.proxyURL"
    static let appTokenKeychainKey = "coach.appToken"

    static var mode: Mode {
        get {
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: modeKey), let mode = Mode(rawValue: raw) {
                return mode
            }
            return AppConfig.devAPIKey != nil ? .directDevelopment : .proxy
            #else
            return .proxy
            #endif
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var proxyBaseURL: String {
        get { UserDefaults.standard.string(forKey: proxyURLKey) ?? AppConfig.defaultProxyBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: proxyURLKey) }
    }

    static var appToken: String? {
        get { KeychainService.read(appTokenKeychainKey) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainService.save(newValue, for: appTokenKeychainKey)
            } else {
                KeychainService.delete(appTokenKeychainKey)
            }
        }
    }

    /// Resolved endpoint + auth headers, or nil if the coach isn't configured yet.
    static func endpoint() -> ClaudeEndpoint? {
        switch mode {
        case .directDevelopment:
            guard let key = AppConfig.devAPIKey, let url = URL(string: AppConfig.directAPIBaseURL + "/v1/messages") else { return nil }
            return ClaudeEndpoint(url: url, headers: ["x-api-key": key])
        case .proxy:
            let base = proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: base + "/v1/messages"), url.scheme == "https" || url.host == "localhost" else { return nil }
            var headers: [String: String] = [:]
            if let token = appToken { headers["x-app-token"] = token }
            return ClaudeEndpoint(url: url, headers: headers)
        }
    }

    static var isConfigured: Bool {
        switch mode {
        case .directDevelopment: AppConfig.devAPIKey != nil
        case .proxy: !proxyBaseURL.contains("example.workers.dev") && appToken != nil
        }
    }
}

struct ClaudeEndpoint: Sendable {
    var url: URL
    var headers: [String: String]
}
