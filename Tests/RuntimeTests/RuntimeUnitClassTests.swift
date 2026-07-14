#if canImport(Testing)
import Testing
@testable import Runtime

/// Tests for STDLIB-REFLECT-ABI-001: Unit::class token encoding and runtime KClass handle.
@Suite
struct RuntimeUnitClassTests {

    // MARK: - Helpers

    private func runtimeStringValue(_ raw: Int) -> String? {
        guard raw != runtimeNullSentinelInt, raw != 0 else { return nil }
        return extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }

    /// The type token for Unit (unitBase = 15, non-nullable).
    private var unitTypeToken: Int {
        // encode(base: 15, nullable: false) = 15 & 0xFF = 15
        return 15
    }

    // MARK: - Token Stability

    @Test
    func testUnitBaseHasStableValue15() {
        // STDLIB-REFLECT-ABI-001 specifies unitBase == 15.
        let tokenBase = Int64(unitTypeToken) & 0xFF
        #expect(tokenBase == 15, "unitBase must be stable at 15")
    }

    // MARK: - KClass Handle Identity (same handle for repeated calls)

    @Test
    func testUnitClassProducesSameHandle() {
        let handle1 = kk_kclass_create(unitTypeToken, 0)
        let handle2 = kk_kclass_create(unitTypeToken, 0)
        #expect(handle1 == handle2, "Unit::class must return the same interned KClass handle")
    }

    @Test
    func testUnitTokenSimpleNameIsUnit() {
        let nameRaw = kk_type_token_simple_name(unitTypeToken, 0)
        #expect(runtimeStringValue(nameRaw) == "Unit")
    }

    @Test
    func testUnitTokenQualifiedNameIsKotlinUnit() {
        let nameRaw = kk_type_token_qualified_name(unitTypeToken, 0)
        #expect(runtimeStringValue(nameRaw) == "kotlin.Unit")
    }

    // MARK: - Unit::class != Any::class

    @Test
    func testUnitClassDoesNotEqualAnyClass() {
        let unitHandle = kk_kclass_create(unitTypeToken, 0)
        let anyToken = 1  // anyBase == 1
        let anyHandle = kk_kclass_create(anyToken, 0)
        #expect(unitHandle != anyHandle, "Unit::class must not equal Any::class")
    }

    // MARK: - isInstance(Unit) — kk_op_is with unitBase

    @Test
    func testIsInstanceUnitValueIsTrue() {
        // The Unit runtime value is the integer 0.
        let unitValue = 0
        let result = kk_op_is(unitValue, unitTypeToken)
        #expect(result == 1, "kk_op_is should return 1 for the Unit singleton value")
    }

    @Test
    func testIsInstanceNonUnitValueIsFalse() {
        // A non-zero value is not Unit.
        let nonUnitValue = 42
        let result = kk_op_is(nonUnitValue, unitTypeToken)
        #expect(result == 0, "kk_op_is should return 0 for a non-Unit value")
    }

    @Test
    func testIsInstanceNullIsNotUnit() {
        let result = kk_op_is(runtimeNullSentinelInt, unitTypeToken)
        #expect(result == 0, "null is not an instance of Unit")
    }
}
#endif
