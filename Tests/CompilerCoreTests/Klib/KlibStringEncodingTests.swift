@testable import CompilerCore
import RuntimeABI
import Testing

@Suite
struct KlibStringEncodingTests {
    @Test
    func preservesSurrogatesSupplementaryScalarsAndRuntimeMarkers() throws {
        let cases: [([UInt8], [UInt16])] = [
            ([0xED, 0xA0, 0x80], [0xD800]),
            ([0xED, 0xBF, 0xBF], [0xDFFF]),
            ([0xF0, 0x9F, 0x98, 0x80], [0xD83D, 0xDE00]),
            ([0xEE, 0xA0, 0x80, 0xEE, 0x80, 0x80], [0xE800, 0xE000]),
            ([0x41, 0x00, 0x42], [0x41, 0, 0x42]),
            ([], []),
        ]
        for (bytes, units) in cases {
            let literal = try KlibStringEncoding.literal(bytes[...])
            #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(literal) == units)
        }
    }

    @Test
    func namesDoNotEscapeLiteralMarkerCharacters() throws {
        let bytes: [UInt8] = [0xEE, 0xA0, 0x80, 0xEE, 0x80, 0x80]
        #expect(try KlibStringEncoding.text(bytes[...]) == "\u{E800}\u{E000}")
    }

    @Test
    func rejectsMalformedWobblyTF8() {
        let invalidStrings: [[UInt8]] = [[0xED, 0xA0], [0x80], [0xC0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x41, 0xAC]]
        for bytes in invalidStrings {
            #expect(throws: KlibFormatError.self) { _ = try KlibStringEncoding.literal(bytes[...]) }
        }
    }
}
