import Foundation

public enum ArtifactKind: String, ResilientStringEnum {
    case implementationPlan
    case walkthrough
    case taskList
    case generativeUIHTML
    case urlBookmark
    case pdfDocument
    case jupyterNotebook
    case imageAsset
    case videoAsset
    /// Forward-compatible fallback for unrecognized artifact kinds produced by newer Desktop hosts.
    case unsupportedAsset

    public static var unknownFallback: ArtifactKind { .unsupportedAsset }
}

/// Represents an Antigravity artifact (`GetArtifactSnapshots` / `GetRevisionArtifact`).
public struct ArtifactSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String { artifactPath }
    public var artifactPath: String
    public var title: String
    public var summary: String
    public var kind: ArtifactKind
    public var rawKindName: String?
    public var content: String
    public var requestFeedback: Bool
    public var userFacing: Bool
    public var version: Int
    public var updatedAt: Date

    public init(
        artifactPath: String,
        title: String,
        summary: String,
        kind: ArtifactKind,
        content: String,
        requestFeedback: Bool = false,
        userFacing: Bool = true,
        version: Int = 1,
        updatedAt: Date = Date(),
        rawKindName: String? = nil
    ) {
        self.artifactPath = artifactPath
        self.title = title
        self.summary = summary
        self.kind = kind
        self.rawKindName = rawKindName
        self.content = content
        self.requestFeedback = requestFeedback
        self.userFacing = userFacing
        self.version = version
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case artifactPath, title, summary, kind, rawKindName, content, requestFeedback, userFacing, version, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.artifactPath = try container.decode(String.self, forKey: .artifactPath)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.kind = try container.decodeIfPresent(ArtifactKind.self, forKey: .kind) ?? .unsupportedAsset
        self.rawKindName = try container.decodeIfPresent(String.self, forKey: .rawKindName)
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.requestFeedback = try container.decodeIfPresent(Bool.self, forKey: .requestFeedback) ?? false
        self.userFacing = try container.decodeIfPresent(Bool.self, forKey: .userFacing) ?? true
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Remote Artifact & `<agent-embed>` Resource Resolution Models

public enum EmbedResourceSource: String, ResilientStringEnum, Equatable {
    case trajectoryStep
    case artifactSnapshot
    case remoteHost
    case directNetwork
    case inlineDataURI

    public static var unknownFallback: EmbedResourceSource { .remoteHost }
}

/// Resolved content backing an `<agent-embed src="file:///...">`, standalone image, or artifact preview.
public struct ResolvedEmbedResource: Codable, Sendable, Equatable {
    public var uri: String
    public var normalizedPath: String
    public var mimeType: String
    public var textContent: String?
    public var binaryData: Data?
    public var source: EmbedResourceSource

    public init(
        uri: String,
        normalizedPath: String? = nil,
        mimeType: String,
        textContent: String? = nil,
        binaryData: Data? = nil,
        source: EmbedResourceSource
    ) {
        self.uri = uri
        self.normalizedPath = normalizedPath ?? Self.normalizePath(uri)
        self.mimeType = mimeType
        self.textContent = textContent
        self.binaryData = binaryData
        self.source = source
    }

    public var isHTML: Bool {
        mimeType.lowercased().contains("html") || normalizedPath.lowercased().hasSuffix(".html") || normalizedPath.lowercased().hasSuffix(".htm")
    }

    public var isSVG: Bool {
        mimeType.lowercased().contains("svg") || normalizedPath.lowercased().hasSuffix(".svg")
    }

    public var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    public static func normalizePath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("file://") {
            s = String(s.dropFirst("file://".count))
        }
        if let decoded = s.removingPercentEncoding {
            s = decoded
        }
        if let hashIdx = s.firstIndex(of: "#") {
            s = String(s[..<hashIdx])
        }
        if let queryIdx = s.firstIndex(of: "?") {
            s = String(s[..<queryIdx])
        }
        return s
    }

    public static func inferredMimeType(for rawPathOrURI: String) -> String {
        let lower = normalizePath(rawPathOrURI).lowercased()
        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return "text/html" }
        if lower.hasSuffix(".svg") { return "image/svg+xml" }
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") { return "text/markdown" }
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".css") { return "text/css" }
        if lower.hasSuffix(".js") { return "application/javascript" }
        return "text/plain"
    }

    public static func isEmbeddableTextArtifactPath(_ rawPathOrURI: String) -> Bool {
        let lower = normalizePath(rawPathOrURI).lowercased()
        return lower.hasSuffix(".html")
            || lower.hasSuffix(".htm")
            || lower.hasSuffix(".svg")
            || lower.hasSuffix(".md")
            || lower.hasSuffix(".markdown")
            || lower.hasSuffix(".mmd")
            || lower.hasSuffix(".mermaid")
            || lower.hasSuffix(".json")
    }

    /// Decodes a `data:<mime>[;base64],<payload>` URI directly into a `ResolvedEmbedResource`.
    public static func decodeDataURI(_ rawURI: String) -> ResolvedEmbedResource? {
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let commaIdx = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let header = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<commaIdx])
        let payload = String(trimmed[trimmed.index(after: commaIdx)...])
        let parts = header.split(separator: ";").map(String.init)
        let mime = (parts.first?.isEmpty == false) ? parts[0] : "text/plain"
        let isBase64 = parts.contains { $0.lowercased() == "base64" }

        if isBase64 {
            guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
                return nil
            }
            let text = mime.lowercased().hasPrefix("text/") || mime.lowercased().contains("svg")
                ? String(data: data, encoding: .utf8)
                : nil
            return ResolvedEmbedResource(
                uri: trimmed,
                normalizedPath: trimmed,
                mimeType: mime,
                textContent: text,
                binaryData: data,
                source: .inlineDataURI
            )
        } else {
            let decodedText = payload.removingPercentEncoding ?? payload
            return ResolvedEmbedResource(
                uri: trimmed,
                normalizedPath: trimmed,
                mimeType: mime,
                textContent: decodedText,
                binaryData: Data(decodedText.utf8),
                source: .inlineDataURI
            )
        }
    }
}

// MARK: - Implementation Plan Review Models (UE11)

/// Proposed file modification or addition inside `ImplementationPlanReviewViewController` (`UE11`).
public struct PlanProposedFileChange: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var changeKind: String
    public var filePath: String
    public var summaryText: String
    public var highlightedSpan: String?
    public var isSelectedForCallout: Bool

    public init(
        id: String,
        changeKind: String,
        filePath: String,
        summaryText: String,
        highlightedSpan: String? = nil,
        isSelectedForCallout: Bool = false
    ) {
        self.id = id
        self.changeKind = changeKind
        self.filePath = filePath
        self.summaryText = summaryText
        self.highlightedSpan = highlightedSpan
        self.isSelectedForCallout = isSelectedForCallout
    }
}

/// Inline review comment anchored to a quoted text span in an Implementation Plan (`UE11`).
public struct PlanInlineComment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var authorInitials: String
    public var authorName: String
    public var statusLabel: String
    public var targetFilePath: String
    public var quotedSpan: String
    public var body: String

    public init(
        id: String = UUID().uuidString,
        authorInitials: String = "WL",
        authorName: String = "You",
        statusLabel: String = "Pending",
        targetFilePath: String,
        quotedSpan: String,
        body: String
    ) {
        self.id = id
        self.authorInitials = authorInitials
        self.authorName = authorName
        self.statusLabel = statusLabel
        self.targetFilePath = targetFilePath
        self.quotedSpan = quotedSpan
        self.body = body
    }
}

// MARK: - Multi-Turn Line-Level Diff Review Models (UE12 + Git VCS)

public struct DiffLine: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, ResilientStringEnum {
        case context
        case addition
        case deletion
        case hunkHeader

        public static var unknownFallback: Kind { .context }
    }

    public var id: Int
    public var kind: Kind
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var text: String
    public var wordHighlightRange: String?
    public var emphasizedRanges: [Range<Int>]

    public init(
        id: Int,
        kind: Kind,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil,
        text: String,
        wordHighlightRange: String? = nil,
        emphasizedRanges: [Range<Int>] = []
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
        self.wordHighlightRange = wordHighlightRange
        self.emphasizedRanges = emphasizedRanges
    }

    public var displayLineNumber: Int? {
        newLineNumber ?? oldLineNumber
    }
}

public struct FilePatchDiff: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(turnNumber):\(filePath)" }
    public var turnNumber: Int
    public var filePath: String
    public var additions: Int
    public var deletions: Int
    public var hunkHeader: String
    public var isReviewed: Bool
    public var statusLetter: GitFileStatusLetter
    public var isStaged: Bool
    public var compareScope: DiffCompareMode
    public var lines: [DiffLine]

    public init(
        turnNumber: Int = 3,
        filePath: String,
        additions: Int,
        deletions: Int,
        hunkHeader: String = "@@ -18,9 +18,27 @@ Allow",
        isReviewed: Bool = false,
        statusLetter: GitFileStatusLetter = .modified,
        isStaged: Bool = false,
        compareScope: DiffCompareMode = .turn,
        lines: [DiffLine]
    ) {
        self.turnNumber = turnNumber
        self.filePath = filePath
        self.additions = additions
        self.deletions = deletions
        self.hunkHeader = hunkHeader
        self.isReviewed = isReviewed
        self.statusLetter = statusLetter
        self.isStaged = isStaged
        self.compareScope = compareScope
        self.lines = lines
    }
}

/// Inline review annotation attached to a specific line in `TurnDiffReviewViewController` (`UE12`).
public struct DiffLineComment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var filePath: String
    public var lineNumber: Int
    public var body: String
    public var sentToAgent: Bool
    public var author: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        filePath: String,
        lineNumber: Int,
        body: String,
        sentToAgent: Bool = false,
        author: String = "You",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.body = body
        self.sentToAgent = sentToAgent
        self.author = author
        self.createdAt = createdAt
    }

    public var commentText: String {
        get { body }
        set { body = newValue }
    }
}

public typealias DiffLineReviewComment = DiffLineComment
