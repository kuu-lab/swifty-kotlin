import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#elseif DEBUG
import CSHA256
#endif

public struct FileFingerprint: Equatable, Codable {
    public let path: String

    public let contentHash: String

    public let mtimeNanos: Int64

    public init(path: String, contentHash: String, mtimeNanos: Int64) {
        self.path = path
        self.contentHash = contentHash
        self.mtimeNanos = mtimeNanos
    }

    public static func compute(for path: String) -> FileFingerprint? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return compute(for: path, contents: data)
    }

    public static func compute(for path: String, contents: Data) -> FileFingerprint {
        let hash = sha256Hex(contents)
        let mtimeNanos = fileMtimeNanos(path: path)
        return FileFingerprint(path: path, contentHash: hash, mtimeNanos: mtimeNanos)
    }

    public func contentChanged(from other: FileFingerprint) -> Bool {
        contentHash != other.contentHash
    }

    static func sha256Hex(_ data: Data) -> String {
        let bytes = sha256Bytes(data)
        let hexChars: [Character] = Array("0123456789abcdef")
        var out = String()
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(hexChars[Int(byte >> 4)])
            out.append(hexChars[Int(byte & 0x0F)])
        }
        return out
    }

    static func sha256Bytes(_ data: Data) -> [UInt8] {
#if canImport(CryptoKit) || canImport(Crypto)
        return Array(SHA256.hash(data: data))
#else
#if DEBUG
        // The pure-Swift fallback below runs at ~7 MB/s in debug builds, so
        // hashing artifact-sized inputs (the bundled stdlib `.kklib` is
        // ~1 GB) takes minutes per cache resolve. The C implementation keeps
        // debug builds fast; release builds keep the optimized Swift path.
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            kswiftk_sha256(
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buffer.count,
                &digest
            )
        }
        return digest
#else
        return data.withUnsafeBytes { sha256(input: $0) }
#endif
#endif
    }

    private static let sha256K: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5,
        0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
        0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3,
        0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
        0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC,
        0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7,
        0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
        0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13,
        0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
        0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3,
        0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5,
        0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
        0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208,
        0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]

    @inline(__always)
    private static func sha256RotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static func sha256(input: UnsafeRawBufferPointer) -> [UInt8] {
        var h0: UInt32 = 0x6A09_E667
        var h1: UInt32 = 0xBB67_AE85
        var h2: UInt32 = 0x3C6E_F372
        var h3: UInt32 = 0xA54F_F53A
        var h4: UInt32 = 0x510E_527F
        var h5: UInt32 = 0x9B05_688C
        var h6: UInt32 = 0x1F83_D9AB
        var h7: UInt32 = 0x5BE0_CD19

        let w = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 64)
        defer { w.deallocate() }

        @inline(__always)
        func compress(_ buffer: UnsafeRawBufferPointer, _ blockOffset: Int) {
            for t in 0 ..< 16 {
                w[t] = UInt32(bigEndian: buffer.loadUnaligned(fromByteOffset: blockOffset + t * 4, as: UInt32.self))
            }
            for t in 16 ..< 64 {
                let x = w[t - 15]
                let y = w[t - 2]
                let s0 = sha256RotateRight(x, 7) ^ sha256RotateRight(x, 18) ^ (x >> 3)
                let s1 = sha256RotateRight(y, 17) ^ sha256RotateRight(y, 19) ^ (y >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h0, b = h1, c = h2, d = h3
            var e = h4, f = h5, g = h6, h = h7
            for t in 0 ..< 64 {
                let sum1 = sha256RotateRight(e, 6) ^ sha256RotateRight(e, 11) ^ sha256RotateRight(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ ch &+ sha256K[t] &+ w[t]
                let sum0 = sha256RotateRight(a, 2) ^ sha256RotateRight(a, 13) ^ sha256RotateRight(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ h
        }

        let fullBlockCount = input.count / 64
        for blockIndex in 0 ..< fullBlockCount {
            compress(input, blockIndex * 64)
        }

        let remaining = input.count - fullBlockCount * 64
        var tail = [UInt8](repeating: 0, count: 128)
        for index in 0 ..< remaining {
            tail[index] = input[fullBlockCount * 64 + index]
        }
        tail[remaining] = 0x80
        var tailEnd = remaining + 1
        while tailEnd % 64 != 56 {
            tailEnd += 1
        }
        let bitLength = UInt64(input.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) {
            tail[tailEnd] = UInt8((bitLength >> UInt64(shift)) & 0xFF)
            tailEnd += 1
        }
        tail.withUnsafeBufferPointer { tailBuffer in
            let rawTail = UnsafeRawBufferPointer(tailBuffer)
            let blockCount = tailEnd / 64
            for blockIndex in 0 ..< blockCount {
                compress(rawTail, blockIndex * 64)
            }
        }

        var output = [UInt8](repeating: 0, count: 32)
        let hashWords: [UInt32] = [h0, h1, h2, h3, h4, h5, h6, h7]
        for (index, word) in hashWords.enumerated() {
            output[index * 4] = UInt8((word >> 24) & 0xFF)
            output[index * 4 + 1] = UInt8((word >> 16) & 0xFF)
            output[index * 4 + 2] = UInt8((word >> 8) & 0xFF)
            output[index * 4 + 3] = UInt8(word & 0xFF)
        }
        return output
    }

    private static func fileMtimeNanos(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return 0
        }
        return Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
