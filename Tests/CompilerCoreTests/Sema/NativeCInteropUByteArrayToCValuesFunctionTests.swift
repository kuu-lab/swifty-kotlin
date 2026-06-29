#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUByteArrayToCValuesFunctionTests {
    @Test func testUByteArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected UByteArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let uByteArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("UByteArray")]),
            "kotlin.UByteArray must be registered"
        )
        let uByteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: uByteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let uByteVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UByteVar")]),
            "kotlinx.cinterop.UByteVar must be registered"
        )
        let uByteVarType = sema.types.make(.classType(ClassType(
            classSymbol: uByteVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uByteVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try #require(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == uByteArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testUByteArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.UByteVar
        import kotlinx.cinterop.toCValues

        fun toUBytes(ubytes: UByteArray): CValues<UByteVar> {
            return ubytes.toCValues()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected UByteArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
