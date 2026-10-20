import Foundation

/// Kotlin/JVM value-class mangling uses the first five bytes of MD5.
enum JVMNameHash {
    static func suffix(_ text: String) -> String {
        var bytes = Array(text.utf8)
        let length = UInt64(bytes.count) * 8
        bytes.append(128)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: length >> (i * 8))) }
        let shifts: [UInt32] = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21]
        let constants = (1...64).map { UInt32(abs(sin(Double($0))) * 4_294_967_296) }
        var state: [UInt32] = [0x67452301,0xefcdab89,0x98badcfe,0x10325476]
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words: [UInt32] = []
            for i in 0..<16 {
                let p = offset + 4 * i
                words.append(UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24)
            }
            var a = state[0], b = state[1], c = state[2], d = state[3]
            for i in 0..<64 {
                let f: UInt32, g: Int
                switch i {
                case 0..<16: f = (b & c) | (~b & d); g = i
                case 16..<32: f = (d & b) | (~d & c); g = (5*i+1)%16
                case 32..<48: f = b ^ c ^ d; g = (3*i+5)%16
                default: f = c ^ (b | ~d); g = (7*i)%16
                }
                let x = a &+ f &+ constants[i] &+ words[g]
                let old = d; d = c; c = b; b = b &+ ((x << shifts[i]) | (x >> (32-shifts[i]))); a = old
            }
            state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        }
        let digest = state.flatMap { x in (0..<4).map { UInt8(truncatingIfNeeded: x >> ($0 * 8)) } }
        return Data(digest.prefix(5)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
