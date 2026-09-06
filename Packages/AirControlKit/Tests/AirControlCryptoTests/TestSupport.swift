import Foundation

/// Shared helpers for the frozen-vector tests. Not part of the `AirControlCrypto` public API.

func hexDecode(_ string: String) -> [UInt8] {
    var result: [UInt8] = []
    var chars = Substring(string)
    while !chars.isEmpty {
        let high = chars.removeFirst()
        let low = chars.removeFirst()
        result.append(UInt8(String([high, low]), radix: 16)!)
    }
    return result
}

func hexEncode(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

/// Loads a JSON vector file from `Tests/AirControlCryptoTests/Vectors/<name>.json` (packaged as a
/// resource via `Package.swift`'s `.copy("Vectors")`).
enum VectorFile {
    static func load(_ name: String) throws -> [String: Any] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors") else {
            throw VectorFileError.notFound(name)
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VectorFileError.malformed(name)
        }
        return json
    }
}

enum VectorFileError: Error {
    case notFound(String)
    case malformed(String)
}
