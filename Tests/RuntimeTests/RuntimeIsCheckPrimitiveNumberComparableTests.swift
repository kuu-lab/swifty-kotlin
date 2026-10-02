@testable import Runtime
import Testing

/// Regression coverage for a bug where a Double/Float/Long/Int/... boxed
/// into an Any slot answered `is Number`/`is Comparable<*>` as false. Unlike
/// value classes and String, a boxed primitive carries no object type ID, so
/// `kk_op_is`'s nominalBase case had no way back to its Number/Comparable
/// ancestry -- fixed by `runtimePrimitiveBoxNominalTypeID` recovering the
/// identity from the box itself, the same way `runtimeIsStringBoxPointer`
/// already does for String.
@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIsCheckPrimitiveNumberComparableTests {
    // Mirrors RuntimeTypeCheckToken's encoding (CompilerCore/KIR/RuntimeTypeCheckToken.swift).
    private static let nominalBase: Int64 = 6
    private static let payloadShift: Int64 = 9

    private func nominalTypeToken(for fqName: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: fqName)
        return Int(Self.nominalBase | (typeID << Self.payloadShift))
    }

    private var numberToken: Int { nominalTypeToken(for: "kotlin.Number") }
    private var comparableToken: Int { nominalTypeToken(for: "kotlin.Comparable") }

    @Test
    func signedNumericBoxesAreNumberAndComparable() {
        let boxedDouble = kk_box_double_nonnull(kk_double_to_bits(3.0))
        let boxedFloat = kk_box_float(kk_float_to_bits(3.0))
        let boxedLong = kk_box_long_nonnull(3)
        let boxedInt = kk_box_int(3)

        for boxed in [boxedDouble, boxedFloat, boxedLong, boxedInt] {
            #expect(kk_op_is(boxed, numberToken) == 1)
            #expect(kk_op_is(boxed, comparableToken) == 1)
        }
    }

    @Test
    func unsignedCharAndBooleanBoxesAreComparableButNotNumber() {
        // UInt/UByte/UShort share RuntimeIntBox with Int, distinguished only
        // by anyFallbackTag -- this is the non-obvious routing this test pins.
        let boxedUInt = kk_box_uint(3)
        let boxedChar = kk_box_char(67) // 'C'
        let boxedBool = kk_box_bool(1)

        for boxed in [boxedUInt, boxedChar, boxedBool] {
            #expect(kk_op_is(boxed, numberToken) == 0)
            #expect(kk_op_is(boxed, comparableToken) == 1)
        }
    }
}
