#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumAPISurfaceInventoryTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Enum surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testEnumAPISurfaceInventoryTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testEnumEntriesInterfaceIsRegisteredUnderKotlinEnums ===
            do {

                let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("EnumEntries"),
                ]))
                #expect(sema.symbols.symbol(enumEntriesSymbol)?.kind == .interface)
                #expect(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("EnumEntries"),
                ]) == nil)
            }

            // === testEnumEntriesFunctionReturnsKotlinEnumsEnumEntries ===
            do {

                let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("EnumEntries"),
                ]))
                let functionSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("enumEntries"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                    Issue.record("enumEntries<T>() should return EnumEntries<T>"); return
                }
                #expect(returnClassType.classSymbol == enumEntriesSymbol)
                #expect(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enumEntries"),
                ]) == nil)
            }
            // BUG: `EnumClass.entries.forEach { ... }` / `.size` reported "Unresolved
            // member function" because `EnumEntries<T>` (a read-only List<T> subtype
            // in real Kotlin) had no registered supertype at all, so neither the
            // ordinary member-call resolver nor the collection member-call fallback
            // ever discovered List's members on an EnumEntries-typed receiver.

            // === testEnumEntriesInterfaceDeclaresListAsSupertype ===
            do {

                let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("enums"),
                    interner.intern("EnumEntries"),
                ]))
                let listSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]))

                // Both the SymbolTable's member-lookup supertype graph and the
                // TypeSystem's nominal-subtype graph must agree: List member
                // resolution walks the former, generic-substitution / nominal
                // subtype checks (e.g. bindBundledIterableSourceFunction's
                // isNominalSubtypeSymbol) walk the latter.
                #expect(sema.symbols.directSupertypes(for: enumEntriesSymbol).contains(listSymbol))
                #expect(sema.types.directNominalSupertypes(for: enumEntriesSymbol).contains(listSymbol))
                #expect(sema.types.isNominalSubtypeSymbol(enumEntriesSymbol, of: listSymbol))
            }
        }
    }

    @Test
    func testEnumEntriesCompanionPropertyUsesKotlinEnumsEnumEntries() throws {

        let source = """
        enum class Color { RED, BLUE }
        fun noop() {}
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        let entriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("Color"),
            interner.intern("Companion"),
            interner.intern("entries"),
        ]))
        let entriesType = try #require(sema.symbols.propertyType(for: entriesSymbol))
        guard case let .classType(entriesClassType) = sema.types.kind(of: entriesType) else {
            Issue.record("Color.entries should have EnumEntries<Color> type"); return
        }
        #expect(entriesClassType.classSymbol == enumEntriesSymbol)
    }

// BUG: `EnumClass.values()` was completely unresolved ("No viable overload
    // found" / "Unresolved reference 'values'") because no Sema symbol was
    // ever registered for it — only the KIR/Lowering-phase synthesis existed,
    // which ran too late to help Sema's call resolution.

    @Test
    func testEnumValuesIsRegisteredDirectlyOnEnumClass() throws {

        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }
        fun noop() {}
        """
        let (sema, interner) = try makeSema(source: source)
        let directionSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("Direction"),
        ]))
        #expect(sema.symbols.symbol(directionSymbol)?.kind == .enumClass)

        // `values()` must be registered directly on the enum class (not the
        // companion): `Direction.values()` resolves via the class-name-receiver
        // static-method lookup, which only searches the class's own FQ name.
        let valuesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("Direction"),
            interner.intern("values"),
        ]))
        let valuesInfo = try #require(sema.symbols.symbol(valuesSymbol))
        #expect(valuesInfo.kind == .function)
        #expect(sema.symbols.parentSymbol(for: valuesSymbol) == directionSymbol)

        let signature = try #require(sema.symbols.functionSignature(for: valuesSymbol))
        #expect(signature.receiverType == nil, "values() must be receiver-less so it resolves as a static member")
        #expect(signature.parameterTypes.isEmpty)

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Direction.values() should return Array<Direction>"); return
        }
        let arraySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]))
        #expect(returnClassType.classSymbol == arraySymbol)
        guard let firstArg = returnClassType.args.first, case let .invariant(elementType) = firstArg else {
            Issue.record("Array<Direction> should carry Direction as its single invariant type argument"); return
        }
        guard case let .classType(elementClassType) = sema.types.kind(of: elementType) else {
            Issue.record("Array<Direction>'s element type should be the Direction class type"); return
        }
        #expect(elementClassType.classSymbol == directionSymbol)
    }

}
#endif
