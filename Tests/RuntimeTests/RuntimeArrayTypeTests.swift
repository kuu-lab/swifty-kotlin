@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeArrayTypeTests {
    private static let nominalBase: Int64 = 6
    private static let payloadShift: Int64 = 9

    private func nominalTypeToken(for fqName: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: fqName)
        return Int(Self.nominalBase | (typeID << Self.payloadShift))
    }

    @Test
    func taggedArrayMatchesItsNominalTypeAndSurvivesCopy() throws {
        let array = kk_array_new(2)
        let intArrayTypeID = runtimeStableNominalTypeID(fqName: "kotlin.IntArray")
        _ = kk_array_tag_type(array, Int(intArrayTypeID))

        #expect(kk_op_is(array, nominalTypeToken(for: "kotlin.IntArray")) == 1)
        #expect(kk_op_is(array, nominalTypeToken(for: "kotlin.LongArray")) == 0)

        let copy = __kk_array_copyOf(array)
        #expect(kk_op_is(copy, nominalTypeToken(for: "kotlin.IntArray")) == 1)
    }
}
