#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ContextFunctionTypeTests {
    @Test func acceptsPlainFunctionValueForContextFunctionParameter() throws {
        let source = """
        fun withContext(f: context(String) () -> String) = f("OK")

        fun callWithContext(f: (String) -> String) = withContext(f)

        fun callWithLambda() = callWithContext { s -> s }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func contextualFunctionConversionMovesLeadingParametersToContexts() throws {
        let types = TypeSystem()
        let source = types.make(.functionType(FunctionType(
            params: [types.stringType, types.intType],
            returnType: types.stringType
        )))
        let target = types.make(.functionType(FunctionType(
            contextReceivers: [types.stringType],
            params: [types.intType],
            returnType: types.anyType
        )))

        let converted = try #require(types.contextualFunctionConversionType(from: source, to: target))
        guard case let .functionType(function) = types.kind(of: converted) else {
            Issue.record("Expected converted context function type")
            return
        }
        #expect(function.contextReceivers == [types.stringType])
        #expect(function.params == [types.intType])
        #expect(function.returnType == types.stringType)
        #expect(types.isSubtype(converted, target))
        #expect(!types.isSubtype(source, target))
    }

    @Test func contextualFunctionConversionRejectsDifferentInputArity() {
        let types = TypeSystem()
        let source = types.make(.functionType(FunctionType(params: [], returnType: types.unitType)))
        let target = types.make(.functionType(FunctionType(
            contextReceivers: [types.stringType],
            params: [],
            returnType: types.unitType
        )))

        #expect(types.contextualFunctionConversionType(from: source, to: target) == nil)
    }

    @Test func rejectsPlainFunctionValueWithIncompatibleContextType() throws {
        let source = """
        fun withContext(f: context(String) () -> String) = f("OK")
        fun invalid(f: (Int) -> String) = withContext(f)
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

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
