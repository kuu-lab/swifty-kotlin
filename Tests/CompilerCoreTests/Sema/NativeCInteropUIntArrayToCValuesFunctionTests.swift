#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUIntArrayToCValuesFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.UIntVar
        import kotlinx.cinterop.toCValues

        fun toUInts(uints: UIntArray): CValues<UIntVar> {
            return uints.toCValues()
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testUIntArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected UIntArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let uIntArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("UIntArray")]),
            "kotlin.UIntArray must be registered"
        )
        let uIntArrayType = sema.types.make(.classType(ClassType(
            classSymbol: uIntArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let uIntVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UIntVar")]),
            "kotlinx.cinterop.UIntVar must be registered"
        )
        let uIntVarType = sema.types.make(.classType(ClassType(
            classSymbol: uIntVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uIntVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try #require(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == uIntArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testUIntArrayToCValuesFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected UIntArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
