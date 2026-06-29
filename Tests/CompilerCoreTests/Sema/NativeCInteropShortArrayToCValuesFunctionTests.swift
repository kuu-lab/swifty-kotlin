#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropShortArrayToCValuesFunctionTests {
    @Test func testShortArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected ShortArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let shortArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ShortArray")]),
            "kotlin.ShortArray must be registered"
        )
        let shortArrayType = sema.types.make(.classType(ClassType(
            classSymbol: shortArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let shortVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]),
            "kotlinx.cinterop.ShortVar must be registered"
        )
        let shortVarType = sema.types.make(.classType(ClassType(
            classSymbol: shortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(shortVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try #require(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == shortArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testShortArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.ShortVar
        import kotlinx.cinterop.toCValues

        fun toShorts(shorts: ShortArray): CValues<ShortVar> {
            return shorts.toCValues()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected ShortArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
