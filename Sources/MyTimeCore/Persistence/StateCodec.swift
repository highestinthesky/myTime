import Foundation
import CryptoKit

public enum DecodeResult: Equatable { case ok(PersistedState), tampered }
public enum StateCodec {
    private struct Envelope: Codable {
        let v: Int
        let payload: String
        let mac: String
    }
    /// Version of the envelope format itself. Independent of `Constants.schemaVersion`, so a future schema bump
    /// doesn't make existing files look tampered.
    private static let envelopeVersion = 1
    private static let key = SymmetricKey(
        data: SHA256.hash(data: Data("myTime.integrity.v1.7c1e9b4a-5d2f-4e8a-9f61-2b3c4d5e6f70".utf8)))
    public static func encode(_ state: PersistedState) throws -> Data {
        let payload = try JSONEncoder.myTime.encode(state)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key).map { String(format: "%02x", $0) }.joined()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            Envelope(v: envelopeVersion, payload: payload.base64EncodedString(), mac: mac))
    }
    public static func decode(_ data: Data) -> DecodeResult {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            envelope.v == envelopeVersion,
            let payload = Data(base64Encoded: envelope.payload), let mac = Data(hex: envelope.mac),
            HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: payload, using: key),
            let state = try? JSONDecoder.myTime.decode(PersistedState.self, from: payload)
        else { return .tampered }
        return .ok(state)
    }
}
private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}
