#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropDoubleArrayToCValuesFunctionTests {
    @Test func testDoubleArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected DoubleArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let doubleArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("DoubleArray")]),
            "kotlin.DoubleArray must be registered"
        )
        let doubleArrayType = sema.types.make(.classType(ClassType(
            classSymbol: doubleArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let doubleVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("DoubleVar")]),
            "kotlinx.cinterop.DoubleVar must be registered"
        )
        let doubleVarType = sema.types.make(.classType(ClassType(
            classSymbol: doubleVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(doubleVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try #require(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == doubleArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testDoubleArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.DoubleVar
        import kotlinx.cinterop.toCValues

        fun toDoubles(doubles: DoubleArray): CValues<DoubleVar> {
            return doubles.toCValues()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected DoubleArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
