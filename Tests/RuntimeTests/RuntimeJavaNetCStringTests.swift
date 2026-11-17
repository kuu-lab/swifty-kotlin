import Testing
@testable import Runtime

@Suite
struct RuntimeJavaNetCStringTests {
    @Test func decodesNULTerminatedUTF8Buffer() {
        let bytes = Array("héllo".utf8)
        var buffer = bytes.map { CChar(bitPattern: $0) }
        buffer += [0, 1, 2]
        #expect(javaNetUTF8String(fromCString: buffer) == "héllo")
    }

    @Test func decodesFullBufferWithoutNUL() {
        let buffer = Array("loopback".utf8).map { CChar(bitPattern: $0) }
        #expect(javaNetUTF8String(fromCString: buffer) == "loopback")
    }

    @Test func stopsAtLeadingNUL() {
        #expect(javaNetUTF8String(fromCString: [0, 1, 2]) == "")
    }
}
