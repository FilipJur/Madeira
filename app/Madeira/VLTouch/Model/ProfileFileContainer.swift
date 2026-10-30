// VLTouch: moved verbatim from ProfileSelectorViewController.swift:130-205 to break the Model->Pickers cycle (R1 finding 5).
// VLTouch: also carries the UInt64 littleEndianBytes helper (originally :278-286), used only by ProfileFileContainer.

import Foundation
import Compression

private enum ProfilePayloadCompression: UInt8 {
    case none = 0
    case lzfse = 1
    case lz4 = 2
    case lzma = 3
    case zlib = 4

    var systemAlgorithm: compression_algorithm? {
        switch self {
        case .none:
            return nil
        case .lzfse:
            return COMPRESSION_LZFSE
        case .lz4:
            return COMPRESSION_LZ4
        case .lzma:
            return COMPRESSION_LZMA
        case .zlib:
            return COMPRESSION_ZLIB
        }
    }
}

enum ProfileFileContainer {
    private static let magic = Array("VLPR".utf8)
    private static let version: UInt8 = 1
    private static let headerSize = 14
    private static let defaultCompression: ProfilePayloadCompression = .lz4

    static func packedData(from payload: Data) -> Data {
        pack(payload, compression: defaultCompression)
    }

    static func unpackedData(from data: Data) throws -> Data {
        guard hasHeader(data) else {
            return data
        }

        let header = Array(data.prefix(headerSize))
        guard header[4] == version,
              let compression = ProfilePayloadCompression(rawValue: header[5]) else {
            throw NSError(domain: "ProfileFileContainer", code: 1)
        }

        let originalLength = UInt64(littleEndianBytes: Array(header[6..<14]))
        let payload = data.dropFirst(headerSize)

        guard let algorithm = compression.systemAlgorithm else {
            return Data(payload)
        }

        guard let unpacked = decompress(Data(payload), originalLength: Int(originalLength), algorithm: algorithm) else {
            throw NSError(domain: "ProfileFileContainer", code: 2)
        }

        return unpacked
    }

    private static func pack(_ payload: Data, compression: ProfilePayloadCompression) -> Data {
        guard let algorithm = compression.systemAlgorithm,
              let compressedPayload = compress(payload, algorithm: algorithm) else {
            return header(compression: .none, originalLength: payload.count) + payload
        }

        return header(compression: compression, originalLength: payload.count) + compressedPayload
    }

    private static func hasHeader(_ data: Data) -> Bool {
        data.count >= headerSize && Array(data.prefix(magic.count)) == magic
    }

    private static func header(compression: ProfilePayloadCompression, originalLength: Int) -> Data {
        var data = Data(magic)
        data.append(version)
        data.append(compression.rawValue)

        var length = UInt64(originalLength).littleEndian
        withUnsafeBytes(of: &length) { bytes in
            data.append(contentsOf: bytes)
        }

        return data
    }

    private static func compress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        if data.isEmpty {
            return Data()
        }

        return data.withUnsafeBytes { sourceBuffer in
            guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            var destinationSize = max(64, data.count + data.count / 16 + 64)
            let maximumDestinationSize = max(destinationSize, data.count * 4 + 1024)

            while destinationSize <= maximumDestinationSize {
                var destination = [UInt8](repeating: 0, count: destinationSize)
                let encodedCount = compression_encode_buffer(
                    &destination,
                    destinationSize,
                    source,
                    data.count,
                    nil,
                    algorithm
                )

                if encodedCount > 0 {
                    return Data(destination.prefix(encodedCount))
                }

                destinationSize *= 2
            }

            return nil
        }
    }

    private static func decompress(_ data: Data, originalLength: Int, algorithm: compression_algorithm) -> Data? {
        if originalLength == 0 {
            return Data()
        }

        return data.withUnsafeBytes { sourceBuffer in
            guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            var destination = [UInt8](repeating: 0, count: originalLength)
            let decodedCount = compression_decode_buffer(
                &destination,
                originalLength,
                source,
                data.count,
                nil,
                algorithm
            )

            guard decodedCount == originalLength else {
                return nil
            }

            return Data(destination)
        }
    }
}

private extension UInt64 {
    init(littleEndianBytes bytes: [UInt8]) {
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << UInt64(index * 8)
        }
        self = value
    }
}
