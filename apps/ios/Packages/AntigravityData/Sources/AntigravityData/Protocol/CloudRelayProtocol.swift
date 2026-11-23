import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Cloud Relay Instance Models (`devtools_jetski_boq_api_proto.ApiService/ListInstances`)

/// Connection lifecycle state reported by `ApiService/ListInstances` (JSPB field 3).
public enum RelayInstanceStatus: Int, Codable, Sendable, Equatable {
    case unknown = 0
    case connected = 1
    case disconnected = 2
    case idle = 3

    public init(rawStatusCode: Int) {
        self = RelayInstanceStatus(rawValue: rawStatusCode) ?? .unknown
    }

    public var isReachable: Bool {
        self == .connected || self == .idle
    }

    public var badgeText: String {
        switch self {
        case .connected: return "Online"
        case .idle: return "Idle"
        case .disconnected: return "Offline"
        case .unknown: return "Unknown"
        }
    }
}

/// Metadata for a Desktop or Cloud Antigravity instance registered on Google Cloud Relay.
public struct RelayInstanceInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let version: String
    public let supportsChunking: Bool
    public let status: RelayInstanceStatus
    public let updatedAt: Date?

    public init(
        uuid: String,
        name: String,
        version: String = "v2.32.0",
        supportsChunking: Bool = true,
        status: RelayInstanceStatus = .connected,
        updatedAt: Date? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.version = version
        self.supportsChunking = supportsChunking
        self.status = status
        self.updatedAt = updatedAt
    }

    /// Returns a copy of this Relay instance with an updated lifecycle `status` (e.g. after end-to-end `ProxyCommand` probe).
    public func withStatus(_ nextStatus: RelayInstanceStatus) -> RelayInstanceInfo {
        RelayInstanceInfo(
            uuid: uuid,
            name: name,
            version: version,
            supportsChunking: supportsChunking,
            status: nextStatus,
            updatedAt: updatedAt
        )
    }

    /// Matches either the full relay UUID (`0f5819ac-9308-40d8-a308-98b55122c533-v2`),
    /// human-readable device slug (`lt74xt6l0m-golden-star`), or UUID prefix.
    public func matches(identifier rawIdentifier: String) -> Bool {
        let needle = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        let uuidLower = uuid.lowercased()
        let nameLower = name.lowercased()
        if uuidLower == needle || nameLower == needle {
            return true
        }
        if needle.count >= 8 && (uuidLower.hasPrefix(needle) || nameLower.hasPrefix(needle)) {
            return true
        }
        return false
    }

    /// Returns `true` when `rawIdentifier` belongs to another Antigravity Desktop window on the same machine
    /// (for example `huangjiafandemac-mini-local-swift-vapor` vs `huangjiafandemac-mini-local-game-loop`,
    /// or `lt74xt6l0m-golden-star` vs `lt74xt6l0m-silver-moon`).
    public func sameHostFamily(as rawIdentifier: String) -> Bool {
        let needle = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty, !candidate.isEmpty else { return false }
        if matches(identifier: needle) { return true }

        let lhsParts = needle.split(separator: "-").map(String.init)
        let rhsParts = candidate.split(separator: "-").map(String.init)
        guard !lhsParts.isEmpty, !rhsParts.isEmpty else { return false }

        var commonSegments: [String] = []
        for (l, r) in zip(lhsParts, rhsParts) {
            if l == r {
                commonSegments.append(l)
            } else {
                break
            }
        }
        if commonSegments.count >= 2 && commonSegments.joined(separator: "-").count >= 7 {
            return true
        }
        let genericPrefixes: Set<String> = ["antigravity", "localhost", "macbook", "desktop", "workspace"]
        if commonSegments.count == 1,
           let first = commonSegments.first,
           first.count >= 8,
           !genericPrefixes.contains(first) {
            return true
        }
        return false
    }
}

// MARK: - Google SAPISIDHASH & ApiService Header Builder

/// Computes Google `SAPISIDHASH` / `SAPISID1PHASH` / `SAPISID3PHASH` authorization headers
/// and attaches required `devtools_jetski_boq_api_proto.ApiService` gRPC-Web / JSPB headers.
public enum SAPISIDHashGenerator: Sendable {
    public static let defaultOrigin = "https://antigravity.google.com"
    public static let apiServicePrefix = "/$rpc/devtools_jetski_boq_api_proto.ApiService"
    public static let relayApiKeyEnvVarName = "ANTIGRAVITY_RELAY_API_KEY"
    public static let relayApiKeyInfoPlistKey = "AntigravityRelayAPIKey"
    public static let antigravityTestHeaderName = "x-antigravity-test-72e4dd1c-e8ae-4e97-873b-c3d3a01b735d"
    public static let mobileRemoteUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Optional explicit override via process environment (`ANTIGRAVITY_RELAY_API_KEY`)
    /// or `Info.plist` (`AntigravityRelayAPIKey`). Never hardcodes any API key in source.
    public static func configuredRelayWebApiKeyOverride() -> String? {
        if let envVal = ProcessInfo.processInfo.environment[relayApiKeyEnvVarName]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envVal.isEmpty,
           !envVal.hasPrefix("$(") {
            return envVal
        }
        if let plistVal = (Bundle.main.object(forInfoDictionaryKey: relayApiKeyInfoPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plistVal.isEmpty,
           !plistVal.hasPrefix("$(") {
            return plistVal
        }
        return nil
    }

    /// Returns `true` for loopback hosts (`127.0.0.1`, `localhost`, `::1`) used by local mock servers and tests.
    public static func isLoopbackOrigin(_ rawOrigin: String) -> Bool {
        guard let host = URLComponents(string: rawOrigin.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    /// Returns `true` when an HTTP 400/403 response indicates an invalid, missing, blocked, or rotated `X-Goog-Api-Key`.
    public static func isInvalidApiKeyError(statusCode: Int, responseBody: String) -> Bool {
        guard statusCode == 400 || statusCode == 403 else { return false }
        let lower = responseBody.lowercased()
        let markers = [
            "api_key_invalid",
            "api_key_service_blocked",
            "api_key_http_referrer_blocked",
            "api key not valid",
            "api key expired",
            "invalid api key",
            "missing a valid api key",
            "x-goog-api-key",
            "unregistered callers",
            "requests to this api",
            "are blocked",
            "keyinvalid"
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Extracts ALL unique candidate public frontend `X-Goog-Api-Key` values dynamically from `antigravity.google.com`
    /// HTML, `WIZ_global_data`, loaded JS bundles, or explicit relay metadata tags (in priority order).
    public static func extractAllWebApiKeys(from rawText: String) -> [String] {
        guard !rawText.isEmpty else { return [] }
        let fullRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        var seen = Set<String>()
        var ordered: [String] = []

        func collect(pattern: String, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: rawText, options: [], range: fullRange) {
                let groupIndex = match.numberOfRanges > 1 ? 1 : 0
                guard let range = Range(match.range(at: groupIndex), in: rawText) else { continue }
                let extracted = String(rawText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty && seen.insert(extracted).inserted {
                    ordered.append(extracted)
                }
            }
        }

        // 1. Contextual Google Boq/Wiz config keys paired with a 39-char Google browser API key
        collect(
            pattern: #"(?:x-goog-api-key|WIu0Nc|QrtxK|P10xbc|apiKey|api_key|webApiKey)["']?\s*[:=]\s*["'](AIza[0-9A-Za-z_\-]{35})["']"#,
            options: [.caseInsensitive]
        )
        // 2. Standalone Google browser API key tokens in HTML/JS bootstrap
        collect(pattern: #"(?<![0-9A-Za-z_\-])(AIza[0-9A-Za-z_\-]{35})(?![0-9A-Za-z_\-])"#)
        // 3. Explicit relay metadata tags (used by custom/mock relays in verification & testing)
        collect(
            pattern: #"<meta\b[^>]*\bname\s*=\s*["']antigravity-relay-api-key["'][^>]*\bcontent\s*=\s*["']([A-Za-z0-9_\-\.]{8,128})["']"#,
            options: [.caseInsensitive]
        )
        collect(
            pattern: #"<meta\b[^>]*\bcontent\s*=\s*["']([A-Za-z0-9_\-\.]{8,128})["'][^>]*\bname\s*=\s*["']antigravity-relay-api-key["']"#,
            options: [.caseInsensitive]
        )
        collect(
            pattern: #"["']x-goog-api-key["']\s*[:=]\s*["']([A-Za-z0-9_\-\.]{8,128})["']"#,
            options: [.caseInsensitive]
        )

        return ordered
    }

    /// Extracts the primary public frontend `X-Goog-Api-Key` dynamically from `antigravity.google.com`
    /// HTML, `WIZ_global_data`, loaded JS bundles, or explicit relay metadata tags.
    public static func extractWebApiKey(from rawText: String) -> String? {
        extractAllWebApiKeys(from: rawText).first
    }

    /// Extracts trusted same-origin or Google-hosted `<script src="...">` and `<link rel="modulepreload" href="...">`
    /// bootstrap bundle URLs from HTML.
    public static func extractBootstrapScriptURLs(
        fromHTML html: String,
        baseURL: URL,
        limit: Int = 12
    ) -> [URL] {
        guard !html.isEmpty, limit > 0 else { return [] }
        let patterns = [
            #"<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            #"<link\b[^>]*\brel\s*=\s*["'](?:modulepreload|preload)["'][^>]*\bhref\s*=\s*["']([^"']+\.m?js(?:\?[^"']*)?)["']"#,
            #"<link\b[^>]*\bhref\s*=\s*["']([^"']+\.m?js(?:\?[^"']*)?)["'][^>]*\brel\s*=\s*["'](?:modulepreload|preload)["']"#
        ]
        let baseHost = baseURL.host?.lowercased()
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)

        var seen = Set<String>()
        var prioritized: [URL] = []
        var secondary: [URL] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: html, options: [], range: fullRange) {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else {
                    continue
                }
                let rawSrc = String(html[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "&amp;", with: "&")
                guard !rawSrc.isEmpty,
                      let resolved = URL(string: rawSrc, relativeTo: baseURL)?.absoluteURL,
                      let scheme = resolved.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      let host = resolved.host?.lowercased() else {
                    continue
                }
                let isTrustedHost =
                    (baseHost != nil && host == baseHost) ||
                    host == "google.com" ||
                    host.hasSuffix(".google.com") ||
                    host == "gstatic.com" ||
                    host.hasSuffix(".gstatic.com") ||
                    host.hasSuffix(".googleusercontent.com")
                guard isTrustedHost else { continue }

                let key = resolved.absoluteString
                guard seen.insert(key).inserted else { continue }

                let lowerPathAndQuery = (resolved.path + "?" + (resolved.query ?? "")).lowercased()
                let isPriorityBundle =
                    lowerPathAndQuery.contains("antigravity") ||
                    lowerPathAndQuery.contains("jetski") ||
                    lowerPathAndQuery.contains("boq") ||
                    lowerPathAndQuery.contains("/_/") ||
                    lowerPathAndQuery.contains("main") ||
                    lowerPathAndQuery.contains("app") ||
                    lowerPathAndQuery.contains("bundle") ||
                    lowerPathAndQuery.contains("chunk") ||
                    lowerPathAndQuery.contains("bootstrap")
                if isPriorityBundle {
                    prioritized.append(resolved)
                } else {
                    secondary.append(resolved)
                }
            }
        }

        return Array((prioritized + secondary).prefix(limit))
    }

    /// Parses a semicolon-delimited HTTP `Cookie` header into `[name: value]`.
    public static func parseCookies(_ rawCookieHeader: String) -> [String: String] {
        var result: [String: String] = [:]
        var cleaned = rawCookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("cookie:") {
            cleaned = String(cleaned.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for part in cleaned.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    /// Lightweight platform-independent cookie representation for RFC 6265 domain matching and deduplication.
    public struct RelayCookieDescriptor: Sendable, Equatable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let expiresDate: Date?

        public init(
            name: String,
            value: String,
            domain: String,
            path: String = "/",
            expiresDate: Date? = nil
        ) {
            self.name = name
            self.value = value
            self.domain = domain
            self.path = path
            self.expiresDate = expiresDate
        }
    }

    /// Returns `true` iff a cookie scoped to `cookieDomain` is valid to send to `targetHost` per RFC 6265
    /// (exact host match or proper parent-domain suffix, strictly excluding unrelated sibling subdomains
    /// such as `accounts.google.com` or `myaccount.google.com` when sending to `antigravity.google.com`).
    public static func cookieDomain(_ cookieDomain: String, appliesToHost targetHost: String) -> Bool {
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawDomain = cookieDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanDomain = rawDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, !cleanDomain.isEmpty else { return false }
        if host == cleanDomain {
            return true
        }
        return host.hasSuffix(".\(cleanDomain)")
    }

    /// Returns `true` iff a cookie's `path` applies to requests at `requestPath` (default `/$rpc`).
    public static func cookiePath(_ cookiePath: String, appliesToRequestPath requestPath: String = "/$rpc") -> Bool {
        let trimmed = cookiePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" {
            return true
        }
        if requestPath == trimmed {
            return true
        }
        if trimmed.hasSuffix("/") {
            return requestPath.hasPrefix(trimmed)
        }
        return requestPath.hasPrefix(trimmed + "/")
    }

    /// Builds a deduplicated `Cookie` header strictly scoped to `targetHost` (default `antigravity.google.com`)
    /// and `/$rpc` request paths. Excludes expired cookies, path-mismatched cookies (such as `/r`-only cookies
    /// shadowing root cookies), and unrelated sibling subdomains.
    public static func buildCookieHeader(
        from cookies: [RelayCookieDescriptor],
        forHost targetHost: String = "antigravity.google.com",
        now: Date = Date()
    ) -> String? {
        let normalizedHost = targetHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var bestByName: [String: (cookie: RelayCookieDescriptor, isExactHost: Bool, domainLength: Int, pathLength: Int)] = [:]

        for cookie in cookies {
            let trimmedName = cookie.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedValue.isEmpty else { continue }
            if let expires = cookie.expiresDate, expires <= now {
                continue
            }
            guard cookieDomain(cookie.domain, appliesToHost: normalizedHost) else {
                continue
            }
            guard cookiePath(cookie.path, appliesToRequestPath: "/$rpc") else {
                continue
            }
            let cleanDomain = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isExactHost = (cleanDomain == normalizedHost)
            let candidate = (cookie: cookie, isExactHost: isExactHost, domainLength: cleanDomain.count, pathLength: cookie.path.count)

            if let existing = bestByName[trimmedName] {
                let candidateWins: Bool
                if candidate.isExactHost != existing.isExactHost {
                    candidateWins = candidate.isExactHost
                } else if candidate.domainLength != existing.domainLength {
                    candidateWins = candidate.domainLength > existing.domainLength
                } else if candidate.pathLength != existing.pathLength {
                    candidateWins = candidate.pathLength > existing.pathLength
                } else {
                    let candExp = candidate.cookie.expiresDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                    let existExp = existing.cookie.expiresDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                    candidateWins = candExp > existExp
                }
                if candidateWins {
                    bestByName[trimmedName] = candidate
                }
            } else {
                bestByName[trimmedName] = candidate
            }
        }

        guard !bestByName.isEmpty else { return nil }
        let orderedPairs = bestByName.keys.sorted().compactMap { name -> String? in
            guard let entry = bestByName[name] else { return nil }
            return "\(entry.cookie.name)=\(entry.cookie.value)"
        }
        let header = orderedPairs.joined(separator: "; ")
        return hasRequiredGoogleAuthCookies(header) ? header : nil
    }

    /// Returns `true` when the cookie string or token contains valid Google session credentials
    /// (`SAPISID` / `__Secure-1PAPISID` / `__Secure-3PAPISID`, or an OAuth `Bearer` token).
    public static func hasRequiredGoogleAuthCookies(_ rawCookieOrToken: String) -> Bool {
        let trimmed = rawCookieOrToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") || trimmed.hasPrefix("ya29.") {
            return true
        }
        let cookies = parseCookies(trimmed)
        let hasApiSid = cookies["SAPISID"] != nil
            || cookies["__Secure-1PAPISID"] != nil
            || cookies["__Secure-3PAPISID"] != nil
        let hasSid = cookies["SID"] != nil
            || cookies["__Secure-1PSID"] != nil
            || cookies["__Secure-3PSID"] != nil
        return hasApiSid && (hasSid || cookies.count >= 1)
    }

    /// Computes the `Authorization` header value (`SAPISIDHASH <ts>_<sha1> SAPISID1PHASH ... SAPISID3PHASH ...`).
    public static func computeAuthorizationHeader(
        cookieHeader: String,
        origin: String = defaultOrigin,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> String? {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return trimmed
        }
        if trimmed.hasPrefix("ya29.") && !trimmed.contains("=") {
            return "Bearer \(trimmed)"
        }

        let normalizedOrigin = normalizeOrigin(origin)
        let cookies = parseCookies(trimmed)
        var schemes: [String] = []

        if let sapisid = cookies["SAPISID"], !sapisid.isEmpty {
            let digest = sha1Hex("\(timestamp) \(sapisid) \(normalizedOrigin)")
            schemes.append("SAPISIDHASH \(timestamp)_\(digest)")
        }
        if let p1 = cookies["__Secure-1PAPISID"], !p1.isEmpty {
            let digest = sha1Hex("\(timestamp) \(p1) \(normalizedOrigin)")
            schemes.append("SAPISID1PHASH \(timestamp)_\(digest)")
        }
        if let p3 = cookies["__Secure-3PAPISID"], !p3.isEmpty {
            let digest = sha1Hex("\(timestamp) \(p3) \(normalizedOrigin)")
            schemes.append("SAPISID3PHASH \(timestamp)_\(digest)")
        }

        return schemes.isEmpty ? nil : schemes.joined(separator: " ")
    }

    /// Attaches all Google Boq `ApiService` JSPB request headers to `request`.
    public static func applyApiServiceHeaders(
        to request: inout URLRequest,
        cookieHeader: String,
        origin: String = defaultOrigin,
        authUser: String = "0",
        apiKey: String? = nil,
        isStreaming: Bool? = nil,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) {
        let normalizedOrigin = normalizeOrigin(origin)
        request.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "X-User-Agent")
        let explicitKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveApiKey = (explicitKey?.isEmpty == false ? explicitKey : nil)
            ?? configuredRelayWebApiKeyOverride()
        if let effectiveApiKey, !effectiveApiKey.isEmpty {
            request.setValue(effectiveApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        }
        request.setValue(authUser.isEmpty ? "0" : authUser, forHTTPHeaderField: "X-Goog-AuthUser")
        if isStreaming != true {
            request.setValue("base64", forHTTPHeaderField: "X-Goog-Encode-Response-If-Executable")
        }
        request.setValue(normalizedOrigin, forHTTPHeaderField: "Origin")
        request.setValue(normalizedOrigin, forHTTPHeaderField: "X-Origin")
        request.setValue("\(normalizedOrigin)/", forHTTPHeaderField: "Referer")
        request.setValue("true", forHTTPHeaderField: antigravityTestHeaderName)
        if let isStreaming {
            request.setValue(isStreaming ? "true" : "false", forHTTPHeaderField: "x-is-streaming")
        }

        var cleanedCookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedCookie.lowercased().hasPrefix("cookie:") {
            cleanedCookie = String(cleanedCookie.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !cleanedCookie.isEmpty && !cleanedCookie.lowercased().hasPrefix("bearer ") && !cleanedCookie.hasPrefix("ya29.") {
            request.setValue(cleanedCookie, forHTTPHeaderField: "Cookie")
        }
        if let auth = computeAuthorizationHeader(
            cookieHeader: cleanedCookie,
            origin: normalizedOrigin,
            timestamp: timestamp
        ) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
    }

    /// Safe, non-secret diagnostic summary of which Google auth cookie names are present (never exposes values).
    public static func summarizeCookieNames(_ rawCookieHeader: String) -> String {
        let trimmed = rawCookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "none" }
        if trimmed.lowercased().hasPrefix("bearer ") || trimmed.hasPrefix("ya29.") { return "bearer" }
        let cookies = parseCookies(trimmed)
        let interesting = [
            "SAPISID",
            "__Secure-1PAPISID",
            "__Secure-3PAPISID",
            "SID",
            "__Secure-1PSID",
            "__Secure-3PSID",
            "OSID",
            "__Secure-OSID",
            "SIDCC",
            "__Secure-1PSIDCC",
            "__Secure-1PSIDTS",
        ]
        let present = interesting.filter { cookies[$0] != nil }.map { name -> String in
            name.hasPrefix("__Secure-") ? String(name.dropFirst("__Secure-".count)) : name
        }
        return "n=\(cookies.count)[\(present.joined(separator: ","))]"
    }

    public static func normalizeOrigin(_ rawOrigin: String) -> String {
        let trimmed = rawOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              let rawHost = comps.host?.lowercased() else {
            return defaultOrigin
        }
        let host = RemoteHostInstance.canonicalizeRelayHost(rawHost)
        if let port = comps.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Computes lowercase hex SHA-1 digest using `CryptoKit` when available, with a pure-Swift fallback.
    public static func sha1Hex(_ string: String) -> String {
        let bytes = Array(string.utf8)
        #if canImport(CryptoKit)
        let digest = Insecure.SHA1.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return pureSwiftSHA1Hex(bytes)
        #endif
    }

    /// Pure-Swift FIPS 180-4 SHA-1 implementation for cross-platform determinism.
    public static func pureSwiftSHA1Hex(_ message: [UInt8]) -> String {
        var bytes = message
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 {
            bytes.append(0x00)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xc3d2e1f0

        @inline(__always)
        func rotl(_ value: UInt32, _ bits: UInt32) -> UInt32 {
            (value << bits) | (value >> (32 - bits))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = (UInt32(bytes[offset]) << 24)
                    | (UInt32(bytes[offset + 1]) << 16)
                    | (UInt32(bytes[offset + 2]) << 8)
                    | UInt32(bytes[offset + 3])
            }
            for i in 16..<80 {
                w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4

            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5a827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ed9eba1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8f1bbcdc
                default:
                    f = b ^ c ^ d
                    k = 0xca62c1d6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotl(b, 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        return String(format: "%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
    }
}

// MARK: - JSPB (`application/json+protobuf`) Codec for `ApiService`

/// Encodes and decodes Google JSPB (`application/json+protobuf`) arrays for
/// `ListInstances`, `ProxyCommand`, and `StreamProxyCommand`.
public enum CloudRelayJSPBCodec: Sendable {

    /// Flexible Base64 / Base64URL decoder handling missing `=` padding and whitespace.
    public static func decodeBase64Flexible(_ raw: String) -> Data? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if cleaned.isEmpty {
            return Data()
        }
        let remainder = cleaned.count % 4
        if remainder == 1 {
            return nil
        }
        let padded = remainder == 0
            ? cleaned
            : cleaned + String(repeating: "=", count: 4 - remainder)
        return Data(base64Encoded: padded, options: [.ignoreUnknownCharacters])
    }

    /// Validates that a JSON string token contains only Base64 / Base64URL characters
    /// (with optional CR/LF line wrapping) and a structurally valid Base64 length.
    public static func isPlausibleBase64Payload(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        var b64Count = 0
        for byte in trimmed.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "+"), UInt8(ascii: "/"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"),
                 UInt8(ascii: "="):
                b64Count += 1
            case UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                continue
            default:
                return false
            }
        }
        return b64Count >= 2 && (b64Count % 4) != 1
    }

    /// Unwraps `X-Goog-Safety-Encoding: base64` / `Content-Transfer-Encoding: base64`
    /// and Google XSSI prefix (`)]}'\n`) when present.
    public static func unwrapGoogleRPCBody(
        _ rawData: Data,
        responseHeaders: [AnyHashable: Any] = [:]
    ) -> Data {
        var data = rawData
        let isBase64Header = responseHeaders.contains { key, val in
            let lowerKey = String(describing: key).lowercased()
            guard lowerKey == "x-goog-safety-encoding" || lowerKey == "content-transfer-encoding" else {
                return false
            }
            return String(describing: val).lowercased().contains("base64")
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstChar = trimmed.first,
               firstChar != "[" && firstChar != "{" && firstChar != ")",
               let decoded = decodeBase64Flexible(trimmed),
               let decodedText = String(data: decoded, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               (isBase64Header || decodedText.hasPrefix("[") || decodedText.hasPrefix(")]}'")) {
                data = decoded
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(")]}'") {
                let afterPrefix = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
                return Data(afterPrefix.utf8)
            }
        }
        return data
    }

    /// Encodes `ListInstancesRequest` (`[]`).
    public static func encodeListInstancesRequest() -> Data {
        Data("[]".utf8)
    }

    /// Decodes `ListInstancesResponse` JSPB array (or protojson object fallback):
    /// `[ [ [uuid, [name, version, supportsChunking], statusInt, [seconds, nanos]], ... ], maxConnected ]`
    public static func decodeListInstancesResponse(
        _ rawData: Data,
        responseHeaders: [AnyHashable: Any] = [:]
    ) throws -> [RelayInstanceInfo] {
        let unwrapped = unwrapGoogleRPCBody(rawData, responseHeaders: responseHeaders)
        if unwrapped.isEmpty {
            return []
        }
        let rootValue = try JSONDecoder().decode(JSONValue.self, from: unwrapped)

        let rawInstances: [JSONValue]
        if let rootArray = rootValue.arrayValue {
            guard let firstArr = rootArray.first?.arrayValue else {
                return []
            }
            rawInstances = firstArr
        } else if let rootObj = rootValue.objectValue,
                  let objInstances = rootObj["instances"]?.arrayValue {
            rawInstances = objInstances
        } else {
            throw AntigravityRPCError.decodingError("Expected JSPB array from ListInstances")
        }

        func firstNonEmptyString(in obj: [String: JSONValue]?, keys: [String]) -> String? {
            guard let obj else { return nil }
            for key in keys {
                if let str = obj[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !str.isEmpty {
                    return str
                }
            }
            return nil
        }

        func decodeStatus(_ value: JSONValue?) -> RelayInstanceStatus {
            if let code = value?.intValue {
                return RelayInstanceStatus(rawStatusCode: code)
            }
            if let rawStr = value?.stringValue?.uppercased() {
                if rawStr.contains("CONNECTED") && !rawStr.contains("DISCONNECTED") {
                    return .connected
                }
                if rawStr.contains("IDLE") {
                    return .idle
                }
                if rawStr.contains("DISCONNECTED") || rawStr.contains("OFFLINE") {
                    return .disconnected
                }
            }
            return .unknown
        }

        func decodeTimestamp(_ value: JSONValue?) -> Date? {
            if let tsArr = value?.arrayValue, !tsArr.isEmpty {
                let secs = tsArr[0].doubleValue ?? Double(tsArr[0].stringValue ?? "")
                let nanos: Double
                if tsArr.count > 1 {
                    nanos = tsArr[1].doubleValue ?? Double(tsArr[1].stringValue ?? "") ?? 0
                } else {
                    nanos = 0
                }
                if let secs, secs > 0 {
                    return Date(timeIntervalSince1970: secs + nanos / 1_000_000_000.0)
                }
            } else if let tsObj = value?.objectValue {
                let secs = tsObj["seconds"]?.doubleValue ?? Double(tsObj["seconds"]?.stringValue ?? "")
                let nanos = tsObj["nanos"]?.doubleValue ?? Double(tsObj["nanos"]?.stringValue ?? "") ?? 0
                if let secs, secs > 0 {
                    return Date(timeIntervalSince1970: secs + nanos / 1_000_000_000.0)
                }
            } else if let iso = value?.stringValue {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = fmt.date(from: iso) {
                    return parsed
                }
                fmt.formatOptions = [.withInternetDateTime]
                return fmt.date(from: iso)
            }
            return nil
        }

        let preferredNameKeys = [
            "deviceName", "device_name",
            "displayName", "display_name",
            "customName", "custom_name",
            "nickname", "hostname", "name"
        ]
        let versionKeys = ["version", "appVersion", "app_version"]

        return rawInstances.compactMap { item -> RelayInstanceInfo? in
            if let row = item.arrayValue {
                guard let rawUuid = row.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawUuid.isEmpty else {
                    return nil
                }
                let metadataVal: JSONValue? = row.count > 1 ? row[1] : nil
                let metadataArr = metadataVal?.arrayValue
                let metadataObj = metadataVal?.objectValue

                let arrName = metadataArr?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                let objName = firstNonEmptyString(in: metadataObj, keys: preferredNameKeys)
                let resolvedName = objName ?? arrName
                let name = (resolvedName?.isEmpty == false) ? resolvedName! : rawUuid

                let arrVersion: String? = (metadataArr != nil && metadataArr!.count > 1) ? metadataArr![1].stringValue : nil
                let objVersion = firstNonEmptyString(in: metadataObj, keys: versionKeys)
                let version = objVersion ?? arrVersion ?? ""

                let supportsChunking: Bool = {
                    if let b = metadataObj?["supportsChunking"]?.boolValue { return b }
                    if let b = metadataObj?["supports_chunking"]?.boolValue { return b }
                    guard let metadataArr, metadataArr.count > 2 else { return true }
                    if let b = metadataArr[2].boolValue { return b }
                    if let i = metadataArr[2].intValue { return i != 0 }
                    return true
                }()

                let status = row.count > 2 ? decodeStatus(row[2]) : .unknown
                let updatedAt = row.count > 3 ? decodeTimestamp(row[3]) : nil

                return RelayInstanceInfo(
                    uuid: rawUuid,
                    name: name,
                    version: version,
                    supportsChunking: supportsChunking,
                    status: status,
                    updatedAt: updatedAt
                )
            }

            if let obj = item.objectValue {
                guard let rawUuid = firstNonEmptyString(in: obj, keys: ["uuid", "instanceId", "instance_id", "id"]) else {
                    return nil
                }
                let metadataObj = obj["metadata"]?.objectValue
                let metadataArr = obj["metadata"]?.arrayValue

                let topName = firstNonEmptyString(in: obj, keys: preferredNameKeys)
                let metaName = firstNonEmptyString(in: metadataObj, keys: preferredNameKeys)
                let arrName = metadataArr?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = topName ?? metaName ?? arrName
                let name = (resolvedName?.isEmpty == false) ? resolvedName! : rawUuid

                let metaVersion = firstNonEmptyString(in: metadataObj, keys: versionKeys)
                let topVersion = firstNonEmptyString(in: obj, keys: versionKeys)
                let arrVersion: String? = (metadataArr != nil && metadataArr!.count > 1) ? metadataArr![1].stringValue : nil
                let version = metaVersion ?? topVersion ?? arrVersion ?? ""

                let chunkFlag = metadataObj?["supportsChunking"]?.boolValue
                    ?? metadataObj?["supports_chunking"]?.boolValue
                let supportsChunking = chunkFlag ?? true
                let status = obj["status"] != nil ? decodeStatus(obj["status"]) : .connected
                let tsVal = obj["updatedAt"] ?? obj["updated_at"] ?? obj["lastSeen"] ?? obj["last_seen"]
                let updatedAt = decodeTimestamp(tsVal)

                return RelayInstanceInfo(
                    uuid: rawUuid,
                    name: name,
                    version: version,
                    supportsChunking: supportsChunking,
                    status: status,
                    updatedAt: updatedAt
                )
            }

            return nil
        }
    }

    /// Encodes `ProxyCommandRequest` JSPB 4-tuple:
    /// `[ targetInstanceUuid, rpcPath, base64Payload, [ [headerKey, headerVal], ... ] ]`
    public static func encodeProxyCommandRequest(
        targetInstanceUuid: String,
        rpcPath: String,
        payload: Data,
        contentType: String = "application/json",
        isStreaming: Bool = false,
        remoteUserAgent: String = SAPISIDHashGenerator.mobileRemoteUserAgent
    ) throws -> Data {
        let base64Payload = payload.isEmpty ? "" : payload.base64EncodedString()
        let headerPairs: [[String]] = [
            ["x-is-streaming", isStreaming ? "true" : "false"],
            ["x-jetski-remote-control-user-agent", remoteUserAgent],
            ["content-type", contentType],
            ["connect-protocol-version", "1"]
        ]
        let jspb: JSONValue = .array([
            .string(targetInstanceUuid),
            .string(rpcPath),
            .string(base64Payload),
            .array(headerPairs.map { pair in .array(pair.map(JSONValue.string)) })
        ])
        return try JSONEncoder().encode(jspb)
    }

    /// Transparently decompresses RFC 1952 `gzip` (`0x1f 0x8b 0x08`) and RFC 1950 `zlib` (`0x78 ...`)
    /// payloads returned inside Cloud Relay `ProxyCommand` / `StreamProxyCommand` and Connect-RPC frames.
    public static func decompressPayloadIfNeeded(_ data: Data) -> Data {
        let bytes = Array(data)
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // 1. RFC 1952 GZIP (`0x1f 0x8b 0x08`)
        if bytes.count >= 18,
           bytes[0] == 0x1f,
           bytes[1] == 0x8b,
           bytes[2] == 0x08 {
            let flags = bytes[3]
            var headerEnd = 10
            let payloadLimit = bytes.count - 8

            if (flags & 0x04) != 0 {
                guard headerEnd + 2 <= payloadLimit else { return data }
                let xlen = Int(bytes[headerEnd]) | (Int(bytes[headerEnd + 1]) << 8)
                headerEnd += 2 + xlen
            }
            if (flags & 0x08) != 0 {
                while headerEnd < payloadLimit && bytes[headerEnd] != 0 { headerEnd += 1 }
                headerEnd += 1
            }
            if (flags & 0x10) != 0 {
                while headerEnd < payloadLimit && bytes[headerEnd] != 0 { headerEnd += 1 }
                headerEnd += 1
            }
            if (flags & 0x02) != 0 {
                headerEnd += 2
            }
            guard headerEnd <= payloadLimit else { return data }

            let deflateSlice = Data(bytes[headerEnd..<payloadLimit])
            if let decompressed = try? (deflateSlice as NSData).decompressed(using: .zlib) {
                return Data(referencing: decompressed)
            }
            return data
        }

        // 2. RFC 1950 ZLIB (`CM == 8`, `(CMF*256 + FLG) % 31 == 0`)
        if bytes.count >= 6,
           (bytes[0] & 0x0f) == 0x08,
           (bytes[0] >> 4) <= 7,
           ((Int(bytes[0]) << 8) | Int(bytes[1])) % 31 == 0 {
            let headerEnd = (bytes[1] & 0x20) != 0 ? 6 : 2
            let payloadLimit = bytes.count - 4
            if headerEnd <= payloadLimit {
                let deflateSlice = Data(bytes[headerEnd..<payloadLimit])
                if let decompressed = try? (deflateSlice as NSData).decompressed(using: .zlib) {
                    return Data(referencing: decompressed)
                }
            }
        }
        #endif
        return data
    }

    private static func parseInnerHeaderPairs(_ pairsValue: JSONValue?) -> [String: String] {
        guard let pairs = pairsValue?.arrayValue else { return [:] }
        var headers: [String: String] = [:]
        for pairVal in pairs {
            if let pair = pairVal.arrayValue,
               pair.count >= 2,
               let k = pair[0].stringValue?.lowercased(),
               let v = pair[1].stringValue {
                headers[k] = v
            }
        }
        return headers
    }

    /// Decodes `ProxyCommandResponse` JSPB tuple:
    /// - Standard: `[ "<base64ResponseBytes>", [ ["accept-encoding", "gzip"], ["content-type", "application/json"] ] ]`
    /// - Nested Boq wrapper: `[ [ "<base64ResponseBytes>", [ ... ] ], trailer ]`
    /// - Chunked response (`supportsChunking == true`): `[ "<b64Part1>", [ ... ] ]\n[ "<b64Part2>", [] ]`
    public static func decodeProxyCommandResponse(
        _ rawData: Data,
        responseHeaders: [AnyHashable: Any] = [:]
    ) throws -> (payload: Data, headers: [String: String]) {
        let unwrapped = unwrapGoogleRPCBody(rawData, responseHeaders: responseHeaders)
        if unwrapped.isEmpty {
            return (Data(), [:])
        }

        if let rootValue = try? JSONDecoder().decode(JSONValue.self, from: unwrapped) {
            guard let rootArray = rootValue.arrayValue else {
                throw AntigravityRPCError.decodingError("Expected JSPB array in ProxyCommandResponse")
            }

            // Check if Boq returned `[null, errorTrailer]` when upstream RPC failed
            if rootArray.first == .null, rootArray.count >= 2 {
                let errSummary = String(data: unwrapped, encoding: .utf8) ?? "Cloud Relay RPC error"
                throw AntigravityRPCError.httpError(statusCode: 502, body: errSummary)
            }

            if let b64Payload = rootArray.first?.stringValue {
                guard let decodedPayload = decodeBase64Flexible(b64Payload) else {
                    throw AntigravityRPCError.decodingError("Invalid base64 payload in ProxyCommandResponse")
                }
                let innerHeaders = rootArray.count > 1 ? parseInnerHeaderPairs(rootArray[1]) : [:]
                return (decompressPayloadIfNeeded(decodedPayload), innerHeaders)
            }

            // Nested JSPB wrapper (`[[ "<b64>", headers ], trailer]`) or multi-element array
            var innerHeaders: [String: String] = [:]
            if let nestedFirst = rootArray.first?.arrayValue, nestedFirst.count > 1 {
                innerHeaders = parseInnerHeaderPairs(nestedFirst[1])
            }
            let nestedChunks = extractPayloadsFromJSPBArray(rootArray)
            var combined = Data()
            for chunk in nestedChunks {
                combined.append(chunk)
            }
            return (decompressPayloadIfNeeded(combined), innerHeaders)
        }

        // Multi-chunk concatenated JSPB arrays (`[chunk1]\n[chunk2]`) when `supportsChunking == true`
        var streamParser = CloudRelayJSPBStreamParser()
        let streamedChunks = streamParser.feed(unwrapped)
        guard !streamedChunks.isEmpty else {
            throw AntigravityRPCError.decodingError("Expected JSPB array in ProxyCommandResponse")
        }
        var combined = Data()
        for chunk in streamedChunks {
            combined.append(chunk)
        }
        return (decompressPayloadIfNeeded(combined), [:])
    }

    /// Extracts base64 payload chunks from a `StreamProxyCommand` JSPB response buffer.
    public static func extractStreamProxyPayloads(from rawText: String) -> [Data] {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        let stripped: String
        if cleaned.hasPrefix(")]}'") {
            stripped = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            stripped = cleaned
        }
        guard let data = stripped.data(using: .utf8) else { return [] }
        if let root = try? JSONDecoder().decode(JSONValue.self, from: data),
           let arr = root.arrayValue {
            return extractPayloadsFromJSPBArray(arr)
        }
        if let decodedB64 = decodeBase64Flexible(stripped),
           let text = String(data: decodedB64, encoding: .utf8),
           text != stripped {
            return extractStreamProxyPayloads(from: text)
        }
        return []
    }

    fileprivate static func extractPayloadsFromJSPBArray(_ arr: [JSONValue]) -> [Data] {
        var payloads: [Data] = []
        func walk(_ node: [JSONValue]) {
            if let firstStr = node.first?.stringValue,
               node.count <= 3,
               (node.count == 1 || node[1].arrayValue != nil || node[1] == .null) {
                if !firstStr.isEmpty, let bytes = decodeBase64Flexible(firstStr), !bytes.isEmpty {
                    payloads.append(bytes)
                }
                return
            }
            for child in node {
                if let childArr = child.arrayValue {
                    walk(childArr)
                }
            }
        }
        walk(arr)
        return payloads
    }
}

/// Incremental Base64 / Base64URL byte decoder for Google Boq responses carrying
/// `X-Goog-Safety-Encoding: base64` or `Content-Transfer-Encoding: base64` on streaming RPCs.
public struct StreamingBase64Decoder: Sendable {
    private var quartet: [UInt8] = []

    public init() {
        quartet.reserveCapacity(4)
    }

    public mutating func feedByte(_ byte: UInt8) -> Data? {
        let normalized: UInt8
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="):
            normalized = byte
        case UInt8(ascii: "-"):
            normalized = UInt8(ascii: "+")
        case UInt8(ascii: "_"):
            normalized = UInt8(ascii: "/")
        default:
            return nil
        }
        quartet.append(normalized)
        guard quartet.count == 4 else { return nil }
        let chunk = Data(quartet)
        quartet.removeAll(keepingCapacity: true)
        return Data(base64Encoded: chunk)
    }

    public mutating func feed(_ bytes: Data) -> Data {
        var out = Data()
        for byte in bytes {
            if let decoded = feedByte(byte) {
                out.append(decoded)
            }
        }
        return out
    }

    public mutating func flush() -> Data {
        guard quartet.count >= 2 else {
            quartet.removeAll(keepingCapacity: true)
            return Data()
        }
        while quartet.count < 4 {
            quartet.append(UInt8(ascii: "="))
        }
        let chunk = Data(quartet)
        quartet.removeAll(keepingCapacity: true)
        return Data(base64Encoded: chunk) ?? Data()
    }
}

/// Incremental O(1)-memory byte-level parser for Google Boq `StreamProxyCommand` JSPB streams.
///
/// Google Boq server-streaming `application/json+protobuf` responses wrap all messages inside a
/// single **open** outer JSON array (e.g. `[[["<b64>",[["content-type","application/connect+json"]]]],[["<b64_2>"]],...`)
/// whose outermost `[` never closes for the lifetime of long-lived streams like `JetboxSubscribeToSummaries`.
///
/// This parser tracks a lightweight array stack and immediately emits every `ProxyCommandResponse`
/// payload tuple (`["<b64>"]`, `["<b64>", headers]`, or `["<b64>", null]`) on its closing `]`
/// without waiting for the outer array to close, while cleanly ignoring HTTP header pairs
/// (`[key, value]`), JSON objects (`{...}`), and Boq error trailers (`[null, [code, msg]]`).
public struct CloudRelayJSPBStreamParser: Sendable {
    private enum ElementKind: Sendable, Equatable {
        case string
        case array
        case null
        case other
    }

    private struct ArrayFrame: Sendable {
        var elementCount: Int = 0
        var firstElement: ElementKind? = nil
        var secondElement: ElementKind? = nil
        var firstString: String? = nil
        var firstInt: Int? = nil
        var secondString: String? = nil

        mutating func append(_ kind: ElementKind, stringValue: String? = nil, intValue: Int? = nil) {
            if elementCount == 0 {
                firstElement = kind
                firstString = stringValue
                firstInt = intValue
            } else if elementCount == 1 {
                secondElement = kind
                secondString = stringValue
            }
            elementCount += 1
        }
    }

    private var stack: [ArrayFrame] = []
    private var objectDepth: Int = 0
    private var inString: Bool = false
    private var isEscaped: Bool = false
    private var stringHasEscape: Bool = false
    private var captureCurrentString: Bool = false
    private var stringBytes: [UInt8] = []
    private var tokenBytes: [UInt8] = []

    /// Captures the last Boq error trailer (`[null, [code, message]]`) observed on the stream, if any.
    public private(set) var lastErrorTrailer: String? = nil

    public init() {}

    public mutating func feed(_ bytes: Data) -> [Data] {
        var emitted: [Data] = []
        for byte in bytes {
            if let chunks = feedByte(byte) {
                emitted.append(contentsOf: chunks)
            }
        }
        return emitted
    }

    private mutating func flushPendingToken() {
        guard !tokenBytes.isEmpty else { return }
        let token = String(decoding: tokenBytes, as: UTF8.self)
        tokenBytes.removeAll(keepingCapacity: true)
        guard !stack.isEmpty else { return }
        if token == "null" {
            stack[stack.count - 1].append(.null)
        } else if let intVal = Int(token) {
            stack[stack.count - 1].append(.other, intValue: intVal)
        } else {
            stack[stack.count - 1].append(.other)
        }
    }

    public mutating func feedByte(_ byte: UInt8) -> [Data]? {
        if inString {
            if captureCurrentString {
                stringBytes.append(byte)
            }
            if isEscaped {
                isEscaped = false
            } else if byte == UInt8(ascii: "\\") {
                isEscaped = true
                if captureCurrentString {
                    stringHasEscape = true
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = false
                if objectDepth == 0, !stack.isEmpty {
                    let decoded: String?
                    if captureCurrentString, stringBytes.count >= 2 {
                        if !stringHasEscape {
                            decoded = String(decoding: stringBytes[1..<(stringBytes.count - 1)], as: UTF8.self)
                        } else {
                            decoded = (try? JSONDecoder().decode(String.self, from: Data(stringBytes)))
                                ?? String(decoding: stringBytes[1..<(stringBytes.count - 1)], as: UTF8.self)
                        }
                    } else {
                        decoded = nil
                    }
                    let keepCap = stringBytes.count <= 65_536
                    stringBytes.removeAll(keepingCapacity: keepCap)
                    stringHasEscape = false
                    captureCurrentString = false
                    stack[stack.count - 1].append(.string, stringValue: decoded)
                }
            }
            return nil
        }

        if objectDepth > 0 {
            if byte == UInt8(ascii: "\"") {
                inString = true
                isEscaped = false
                captureCurrentString = false
            } else if byte == UInt8(ascii: "{") {
                objectDepth += 1
            } else if byte == UInt8(ascii: "}") {
                objectDepth -= 1
                if objectDepth == 0, !stack.isEmpty {
                    stack[stack.count - 1].append(.other)
                }
            }
            return nil
        }

        if stack.isEmpty {
            if byte == UInt8(ascii: "[") {
                stack.append(ArrayFrame())
                tokenBytes.removeAll(keepingCapacity: true)
            }
            return nil
        }

        switch byte {
        case UInt8(ascii: "\""):
            flushPendingToken()
            inString = true
            isEscaped = false
            stringHasEscape = false
            captureCurrentString = (stack[stack.count - 1].elementCount <= 1)
            stringBytes.removeAll(keepingCapacity: true)
            if captureCurrentString {
                stringBytes.append(byte)
            }
            return nil

        case UInt8(ascii: "{"):
            flushPendingToken()
            objectDepth = 1
            return nil

        case UInt8(ascii: "["):
            flushPendingToken()
            stack.append(ArrayFrame())
            return nil

        case UInt8(ascii: ","),
             UInt8(ascii: " "),
             UInt8(ascii: "\t"),
             UInt8(ascii: "\n"),
             UInt8(ascii: "\r"):
            flushPendingToken()
            return nil

        case UInt8(ascii: "]"):
            flushPendingToken()
            let closed = stack.removeLast()
            let insideErrorTrailer = stack.contains { $0.firstElement == .null || $0.firstElement == .other }
            if !stack.isEmpty {
                stack[stack.count - 1].append(.array)
            }
            if insideErrorTrailer {
                if let code = closed.firstInt, code != 0,
                   let msg = closed.secondString, !msg.isEmpty {
                    lastErrorTrailer = "Boq status \(code): \(msg)"
                }
                return nil
            }
            if closed.firstElement == .string,
               closed.elementCount >= 1 && closed.elementCount <= 3,
               (closed.elementCount == 1 || closed.secondElement == .array || closed.secondElement == .null),
               let b64 = closed.firstString,
               CloudRelayJSPBCodec.isPlausibleBase64Payload(b64),
               let decoded = CloudRelayJSPBCodec.decodeBase64Flexible(b64),
               !decoded.isEmpty {
                return [decoded]
            }
            return nil

        default:
            tokenBytes.append(byte)
            return nil
        }
    }
}
