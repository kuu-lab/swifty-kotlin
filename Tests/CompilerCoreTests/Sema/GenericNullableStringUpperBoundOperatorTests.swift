#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericNullableStringUpperBoundOperatorTests {

    @Test(arguments: [false, true])
    func nullableStringUpperBoundResolvesBinaryAndNamedPlus(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }

        let ctx = makeContextFromSource(
            """
            fun <T : String?> concat5(value: T): String = value + "!!"
            fun <T : String?> concatNamed(value: T): String = value.plus("!!")
            fun <T : String> concat4(value: T): String = value + "!!"
            fun <T : Int?> invalid(value: T): String = value + "!!"
            fun <T : Number?> unrefinedMember(value: T): Int = value.toInt()
            """,
            emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "Expected only the unrelated operator and unrefined member to fail: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" }, "\(errors)")

        let sema = try #require(ctx.sema)
        let stdlibPlus = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == .function
                && symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "text", "plus"]
                && sema.symbols.functionSignature(for: symbol.id)?.receiverType
                    == sema.types.makeNullable(sema.types.stringType)
        }
        #expect(!stdlibPlus.isEmpty, "Expected the bundled String?.plus declaration to be loaded")
        let stdlibPlusIDs = Set(stdlibPlus.map(\.id))
        #expect(
            sema.bindings.callBindings.values.contains { stdlibPlusIDs.contains($0.chosenCallee) },
            "Expected a generic String? upper-bound call to bind to the bundled String?.plus"
        )
    }

    @Test
    func genericNullableStringPlusKeepsMoreSpecificUserOperator() throws {
        let ctx = makeContextFromSource("""
        operator fun String?.plus(other: String): String = "CUSTOM"
        fun <T : String?> combine(value: T): String = value + "!!"
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let userPlus = try #require(sema.symbols.allSymbols().first { symbol in
            symbol.kind == .function
                && symbol.name == ctx.interner.intern("plus")
                && sema.symbols.sourceFileID(for: symbol.id).map(ctx.sourceManager.origin(of:)) == .user
        })
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == userPlus.id })
    }
}
#endif
