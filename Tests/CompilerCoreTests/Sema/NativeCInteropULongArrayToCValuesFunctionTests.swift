#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropULongArrayToCValuesFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.ULongVar
        import kotlinx.cinterop.toCValues

        fun toULongs(ulongs: ULongArray): CValues<ULongVar> {
            return ulongs.toCValues()
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
    @Test func testULongArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected ULongArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let uLongArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ULongArray")]),
            "kotlin.ULongArray must be registered"
        )
        let uLongArrayType = sema.types.make(.classType(ClassType(
            classSymbol: uLongArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let uLongVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ULongVar")]),
            "kotlinx.cinterop.ULongVar must be registered"
        )
        let uLongVarType = sema.types.make(.classType(ClassType(
            classSymbol: uLongVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uLongVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try #require(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == uLongArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testULongArrayToCValuesFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected ULongArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
