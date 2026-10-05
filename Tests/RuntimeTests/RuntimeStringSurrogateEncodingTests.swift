import RuntimeABI
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeStringSurrogateEncodingTests {
    @Test
    func allUTF16UnitsRoundTripWithoutPrivateUseCollisions() {
        let units = (0 ... 0xFFFF).map(UInt16.init)
        #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(
            KotlinStringSurrogateEncoding.fromUTF16CodeUnits(units)
        ) == units)
        for unit in UInt16(0xD800) ... UInt16(0xE800) {
            let encoded = KotlinStringSurrogateEncoding.fromUTF16CodeUnits([unit])
            #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(encoded) == [unit])
        }
    }

    @Test
    func escapePrefixAndMarkersRemainDistinctInEveryOrder() {
        let values: [UInt16] = [0xD800, 0xDFFF, 0xE000, 0xE7FF, 0xE800]
        for first in values {
            for second in values {
                let units = [first, second]
                let encoded = runtimeKotlinStringFromUTF16CodeUnits(units)
                #expect(runtimeKotlinStringUTF16CodeUnits(encoded) == units)
                #expect(runtimeKotlinStringUTF16Length(encoded) == 2)
                #expect(runtimeKotlinStringUTF16CodeUnit(encoded, at: 0) == first)
                #expect(runtimeKotlinStringUTF16CodeUnit(encoded, at: 1) == second)
            }
        }
    }

    @Test
    func utf8BoundaryPreservesLiteralPrivateUseCharacters() {
        let original = "\u{E800}\u{E000}\u{E7FF}\u{E800}"
        let bytes = Array(original.utf8)
        let raw = bytes.withUnsafeBufferPointer {
            Int(bitPattern: kk_string_from_utf8($0.baseAddress!, Int32($0.count)))
        }
        let value = runtimeStringFromRaw(raw)!
        #expect(runtimeStringUTF16CodeUnits(raw) == Array(original.utf16))
        #expect(KotlinStringSurrogateEncoding.unicodeString(value) == original)
    }

    @Test
    func flatAndStringBuilderRoundTripsPreserveLogicalUnits() {
        let units: [UInt16] = [0xE000, 0xE7FF, 0xE800, 0xD800, 0x0041, 0xDFFF]
        let raw = runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(units))
        var length = 0, byteCount = 0, hash = 0
        let data = kk_string_to_flat(raw, &length, &byteCount, &hash)
        #expect(length == units.count)
        let restored = kk_string_from_flat(data, length, byteCount, hash)
        #expect(runtimeStringUTF16CodeUnits(restored) == units)
        for (index, unit) in units.enumerated() {
            #expect(runtimeFlatStringCodeUnit(data: data, length: length, byteCount: byteCount, hash: hash, index: index).unit == unit)
        }
        let builder = __kk_string_builder_new()
        _ = __kk_string_builder_append_obj(builder, restored)
        #expect(__kk_string_builder_length_prop(builder) == units.count)
        #expect(runtimeStringUTF16CodeUnits(__kk_string_builder_toString(builder)) == units)
    }

    @Test
    func comparisonAndReplacementDoNotSeeSurrogateMarkers() {
        let surrogate = runtimeKotlinStringFromUTF16CodeUnits([0xD800])
        #expect(runtimeCompareStrings(surrogate, "\u{E000}") == -2048)
        let source = runtimeKotlinStringFromUTF16CodeUnits([0xD800, 0xE000, 0xE800])
        let replaced = runtimeReplacingStringCodeUnits(source, old: "\u{E000}", new: "x")
        #expect(runtimeKotlinStringUTF16CodeUnits(replaced) == [0xD800, 0x0078, 0xE800])
        let escape = KotlinStringSurrogateEncoding.encode("\u{E800}")
        #expect(runtimeKotlinStringUTF16CodeUnits(runtimeReplacingStringCodeUnits(source, old: escape, new: "y")) == [0xD800, 0xE000, 0x0079])
        #expect(runtimeKotlinStringUTF16CodeUnits(runtimeReplacingStringCodeUnits(source, old: "", new: "-")) == [0x2D, 0xD800, 0x2D, 0xE000, 0x2D, 0xE800, 0x2D])
    }
}
