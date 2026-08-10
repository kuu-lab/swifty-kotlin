#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumEntriesFunctionSurfaceTests {
    @Test
    func testEnumEntriesFunctionSurfaceTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            enum class Color { RED, BLUE }
            fun entries() = enumEntries<Color>()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let path0 = paths[0]
            let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
            #expect(
                !path0Diagnostics.contains(where: { $0.severity == .error }),
                "enumEntries surface should resolve without diagnostics: \(path0Diagnostics)"
            )

            // === testEnumEntriesFunctionIsRegisteredUnderKotlinEnums ===
            do {

                let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("enumEntries"),
                ]))
                #expect(sema.symbols.symbol(enumEntriesSymbol)?.kind == .function)
                #expect(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enumEntries"),
                ]) == nil)
            }

            // === testEnumEntriesFunctionIsDefaultImportedFromKotlinEnums ===
            do {

                let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("enumEntries"),
                ]))
                let entriesFunction = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern("entries"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: entriesFunction))
                guard case .classType = sema.types.kind(of: signature.returnType) else {
                    Issue.record("enumEntries<Color>() should return an EnumEntries-like class type"); return
                }
                let callBindingsContains = sema.bindings.callBindings.contains(where: { $0.value.chosenCallee == enumEntriesSymbol })
                #expect(
                    callBindingsContains,
                    "Unqualified enumEntries<Color>() should bind to kotlin.enums.enumEntries"
                )
            }
        }
    }
}
#endif
