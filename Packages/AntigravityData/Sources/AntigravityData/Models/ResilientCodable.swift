import Foundation

/// Forward-compatible `String`-backed `Codable` enumeration protocol.
///
/// Any domain or wire enumeration conforming to `ResilientStringEnum` automatically decodes
/// unrecognized future raw values (from newer Antigravity Desktop / Cloud Relay payloads or
/// newer persisted snapshots) to `unknownFallback` instead of throwing `DecodingError.dataCorrupted`.
///
/// Enforced mechanically by `verification/verify_compat_guardrails.py` across all `String, Codable`
/// enumerations in `Packages/AntigravityData/Sources/AntigravityData/Models/`.
public protocol ResilientStringEnum: RawRepresentable, Codable, Sendable where RawValue == String {
    static var unknownFallback: Self { get }
}

public extension ResilientStringEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknownFallback
    }
}
