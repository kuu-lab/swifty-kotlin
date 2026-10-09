@testable import CompilerCore
import Foundation
import Testing

@Suite
struct StableFNV1a64Tests {
    @Test
    func matchesKnownEmptyAndAsciiVectors() {
        #expect(StableFNV1a64.hex("") == "cbf29ce484222325")
        #expect(StableFNV1a64.hex("a") == "af63dc4c8601ec8c")
        #expect(StableFNV1a64.hex("hello") == "a430d84680aabd0b")
    }

    @Test
    func hashesUnicodeUtf8Bytes() {
        #expect(StableFNV1a64.hex("é") == "0ac21707b7181e01")
        #expect(StableFNV1a64.hex("🍣") == "ff468238753ed62c")
    }

    @Test
    func zeroPadsLeadingZeroHashesByDefault() {
        let value = "leading-zero-200"

        #expect(StableFNV1a64.hex(value) == "0fc5ecb561a3e7f9")
        #expect(StableFNV1a64.hex(value).count == 16)
        #expect(StableFNV1a64.hex(value, zeroPadded: false) == "fc5ecb561a3e7f9")
    }

    @Test
    func chunkedUpdatesMatchKnownPathAndContentVector() {
        var hasher = StableFNV1a64.Hasher()
        hasher.update(bytes: "__bundled_src/Δ.kt".utf8)
        hasher.update(bytes: Data())
        hasher.update(bytes: Data([0x00, 0xFF]))
        hasher.update(bytes: "KSwiftK".utf8)

        #expect(hasher.hexString() == "f7ee940f3114043a")
    }
}
