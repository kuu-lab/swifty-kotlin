@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIntegerTypeIdentityTests {
    private let tokens: [Int64] = [
        RuntimeTypeTokenEncoding.byteBase, RuntimeTypeTokenEncoding.shortBase,
        RuntimeTypeTokenEncoding.ubyteBase, RuntimeTypeTokenEncoding.ushortBase,
        RuntimeTypeTokenEncoding.uintBase, RuntimeTypeTokenEncoding.ulongBase,
        RuntimeTypeTokenEncoding.intBase, RuntimeTypeTokenEncoding.longBase,
    ]

    @Test
    func integerBoxesMatchOnlyTheirOwnType() {
        let legacy = [
            kk_box_byte(-128), kk_box_short(0x1234), kk_box_ubyte(255), kk_box_ushort(0x8000),
            kk_box_uint(0xDEADBEEF), kk_box_ulong_nonnull(Int.min), kk_box_int(42), kk_box_long_nonnull(Int.min),
        ]
        let fast = [
            kk_box_byte_static(-128), kk_box_short_static(0x1234), kk_box_ubyte_static(255), kk_box_ushort_static(0x8000),
            kk_box_uint_static(0xDEADBEEF), kk_box_ulong_nonnull_static(Int.min), kk_box_int_static(42), kk_box_long_nonnull_static(Int.min),
        ]
        for boxes in [legacy, fast] {
            for (index, box) in boxes.enumerated() {
                for (target, token) in tokens.enumerated() {
                    let matches = index == target
                    #expect(kk_op_is(box, Int(token)) == (matches ? 1 : 0))
                    #expect(kk_op_is(box, Int(token | RuntimeTypeTokenEncoding.nullableBit)) == (matches ? 1 : 0))
                    #expect(kk_op_safe_cast(box, Int(token)) == (matches ? box : runtimeNullSentinelInt))
                    var thrown = 0
                    let cast = kk_op_cast(box, Int(token), &thrown)
                    #expect((thrown == 0) == matches)
                    if matches { #expect(cast == box) }
                }
            }
        }
    }

    @Test
    func narrowBoxesPreservePayloadAndNull() {
        for (box, value) in [
            (kk_box_byte(-128), -128), (kk_box_byte_static(127), 127),
            (kk_box_short(-32768), -32768), (kk_box_short_static(32767), 32767),
        ] {
            #expect(kk_unbox_int(box) == value)
            #expect(kk_unbox_int_static(box) == value)
            #expect(kk_any_hashCode(box, 0) == value)
        }
        for box in [kk_box_byte, kk_box_short, kk_box_byte_static, kk_box_short_static] {
            #expect(box(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        }
        for token in tokens {
            #expect(kk_op_is(runtimeNullSentinelInt, Int(token)) == 0)
            #expect(kk_op_is(runtimeNullSentinelInt, Int(token | RuntimeTypeTokenEncoding.nullableBit)) == 1)
        }
    }

    @Test
    func nonIntegerAndNominalBoxesDoNotMatchIntegerTypes() {
        let enumBox = kk_enum_box_ordinal(1, 0, Int(runtimeStableNominalTypeID(fqName: "test.Entry")))
        let valueClassBox = kk_tag_value_class_box(
            kk_box_byte_static(1), Int(runtimeStableNominalTypeID(fqName: "test.WrappedByte"))
        )
        for box in [kk_box_bool(1), kk_box_char(65), kk_box_float(0), kk_box_double(0), enumBox, valueClassBox] {
            for token in tokens {
                #expect(kk_op_is(box, Int(token)) == 0)
            }
        }
    }
}
