#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ContextFunctionTypeTests {
    @Test func testFunctionSubtypingContextReceiverCountMismatch() {
        let ts = TypeSystem()
        let intType = ts.intType
        let left = ts.make(.functionType(FunctionType(
            contextReceivers: [intType],
            params: [],
            returnType: intType
        )))
        let right = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, intType],
            params: [],
            returnType: intType
        )))

        #expect(!(ts.isSubtype(left, right)))
        #expect(!(ts.isSubtype(right, left)))
    }

    @Test func testFunctionSubtypingContextReceiversAreOrderedAndContravariant() {
        let ts = TypeSystem()
        let intType = ts.intType
        let anyType = ts.anyType
        let left = ts.make(.functionType(FunctionType(
            contextReceivers: [anyType, intType],
            params: [],
            returnType: intType
        )))
        let right = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, intType],
            params: [],
            returnType: intType
        )))
        let reordered = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, anyType],
            params: [],
            returnType: intType
        )))

        #expect(ts.isSubtype(left, right))
        #expect(!(ts.isSubtype(right, left)))
        #expect(!(ts.isSubtype(left, reordered)))
    }

    @Test func testWithNullabilityPreservesContextReceivers() {
        let ts = TypeSystem()
        let intType = ts.intType
        let stringType = ts.stringType
        let fn = ts.make(.functionType(FunctionType(
            contextReceivers: [stringType],
            params: [intType],
            returnType: intType
        )))
        let nullable = ts.withNullability(.nullable, for: fn)

        guard case let .functionType(result) = ts.kind(of: nullable) else {
            Issue.record("Expected function type"); return
        }
        #expect(result.contextReceivers == [stringType])
        #expect(result.params == [intType])
        #expect(result.returnType == intType)
        #expect(result.nullability == .nullable)
    }
}
#endif
