@testable import CompilerCore
import RuntimeABI
import Testing

struct KotlinStringSurrogateLiteralTests {
    @Test
    func escapedAndActualPrivateUseLiteralsRemainDistinctFromSurrogates() {
        let decoded = decodeKotlinStringEscapes(#"\uE000\uE7FF\uE800\uD800x\uDFFF\uD800\uDC00"#)
        #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(decoded) == [
            0xE000, 0xE7FF, 0xE800, 0xD800, 0x0078, 0xDFFF, 0xD800, 0xDC00,
        ])
        let actual = decodeKotlinStringEscapes("\u{E800}\u{E000}")
        #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(actual) == [0xE800, 0xE000])
    }
}
