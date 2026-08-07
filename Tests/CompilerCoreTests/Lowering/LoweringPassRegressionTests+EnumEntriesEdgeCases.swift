#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-023: kotlin.enums `entries` / `EnumEntries<T>` edge case coverage.
extension LoweringPassRegressionTests {

    // MARK: - Helpers

    private func makeEnumModule(
        enumName: String,
        entryNames: [String],
        interner: StringInterner,
        symbols: SymbolTable,
        sema: SemaModule,
        moduleName: String
    ) throws -> (module: KIRModule, enumSymbol: SymbolID, ctx: CompilationContext) {
        let packagePath: [InternedString] = [interner.intern("test")]
        let enumInternedName = interner.intern(enumName)
        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: enumInternedName,
            fqName: packagePath + [enumInternedName],
            declSite: nil,
            visibility: .public
        )
        for entryName in entryNames {
            _ = symbols.define(
                kind: .field,
                name: interner.intern(entryName),
                fqName: packagePath + [enumInternedName, interner.intern(entryName)],
                declSite: nil,
                visibility: .public
            )
        }

        let arena = KIRArena()
        let decl = arena.appendDecl(.nominalType(KIRNominalType(symbol: enumSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [decl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)
        return (module, enumSymbol, ctx)
    }

    // MARK: - STDLIB-023-01: entries$get is synthesized for a normal enum

    @Test
    func testEnumEntriesGetterIsSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Color",
            entryNames: ["RED", "GREEN", "BLUE"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesGetter"
        )

        let functionNames = findAllKIRFunctions(in: module).map { fn in
            interner.resolve(fn.name)
        }

        #expect(functionNames.contains("entries$get"),
                "entries$get should be synthesized; got: \(functionNames)")
    }

    // MARK: - STDLIB-023-02: entries$get body calls kk_array_new and kk_enum_make_entries_list

    @Test
    func testEnumEntriesGetterBodyUsesCorrectRuntimeCalls() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Direction",
            entryNames: ["NORTH", "SOUTH", "EAST", "WEST"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesRuntimeCalls"
        )

        let fn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let callees = extractCallees(from: fn.body, interner: interner)

        #expect(callees.contains("kk_array_new"),
                "entries$get should call kk_array_new; callees: \(callees)")
        #expect(callees.contains("kk_array_set"),
                "entries$get should call kk_array_set for each entry; callees: \(callees)")
        #expect(callees.contains("kk_enum_make_entries_list"),
                "entries$get should call kk_enum_make_entries_list; callees: \(callees)")
    }

    // MARK: - STDLIB-023-03: entries count matches declared enum cases

    @Test
    func testEnumEntriesCountMatchesDeclaredCases() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Planet",
            entryNames: ["MERCURY", "VENUS", "EARTH", "MARS", "JUPITER"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesCount"
        )

        // The count helper Planet$enumValuesCount must return 5.
        let countFn = try findKIRFunction(named: "Planet$enumValuesCount", in: module, interner: interner)
        let intConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(intConsts.contains(5),
                "Planet$enumValuesCount should embed count=5; got consts: \(intConsts)")

        // entries$get must embed 5 ordinal literals (one per entry set).
        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesConsts = entriesFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        // 5-entry enum: ordinals 0..4 appear as both index and entry payload.
        #expect(entriesConsts.contains(4),
                "entries$get should embed ordinal 4 (5th entry); got: \(entriesConsts)")
    }

    // MARK: - STDLIB-023-04: entries order matches declaration order

    @Test
    func testEnumEntriesOrderMatchesDeclaration() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Season",
            entryNames: ["SPRING", "SUMMER", "AUTUMN", "WINTER"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesOrder"
        )

        // Per-entry ordinal functions must return 0, 1, 2, 3 in declaration order.
        for (expectedOrdinal, name) in ["SPRING", "SUMMER", "AUTUMN", "WINTER"].enumerated() {
            let fn = try findKIRFunction(named: "\(name)$enumOrdinal", in: module, interner: interner)
            let consts = fn.body.compactMap { inst -> Int64? in
                guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
                return v
            }
            #expect(consts.contains(Int64(expectedOrdinal)),
                    "\(name)$enumOrdinal should be \(expectedOrdinal); got: \(consts)")
        }
    }

    // MARK: - STDLIB-023-05: empty enum synthesizes zero-count helpers

    @Test
    func testEmptyEnumSynthesizesZeroCount() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Empty",
            entryNames: [],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesEmpty"
        )

        let countFn = try findKIRFunction(named: "Empty$enumValuesCount", in: module, interner: interner)
        let intConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(intConsts.contains(0),
                "Empty enum should have count=0; got: \(intConsts)")

        // entries$get must NOT call kk_array_set (no entries to populate).
        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let callees = extractCallees(from: entriesFn.body, interner: interner)
        #expect(!callees.contains("kk_array_set"),
                "Empty enum entries$get must not call kk_array_set; callees: \(callees)")
        #expect(callees.contains("kk_enum_make_entries_list"),
                "Empty enum entries$get must still call kk_enum_make_entries_list; callees: \(callees)")
    }

    // MARK: - STDLIB-023-06: single-variant enum

    @Test
    func testSingleVariantEnumEntriesAndOrdinal() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Singleton",
            entryNames: ["ONLY"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesSingle"
        )

        let countFn = try findKIRFunction(named: "Singleton$enumValuesCount", in: module, interner: interner)
        let countConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(countConsts.contains(1), "Single-variant enum count should be 1; got: \(countConsts)")

        let ordinalFn = try findKIRFunction(named: "ONLY$enumOrdinal", in: module, interner: interner)
        let ordinalConsts = ordinalFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(ordinalConsts.contains(0), "ONLY ordinal should be 0; got: \(ordinalConsts)")

        let nameFn = try findKIRFunction(named: "ONLY$enumName", in: module, interner: interner)
        let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return s
        }
        #expect(nameConsts.contains(interner.intern("ONLY")),
                "ONLY$enumName should return \"ONLY\"")
    }

    // MARK: - STDLIB-023-07: values() synthesized separately from entries$get

    @Test
    func testEnumValuesAndEntriesGetterBothSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Side",
            entryNames: ["LEFT", "RIGHT"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumValuesAndEntries"
        )

        let functionNames = findAllKIRFunctions(in: module).map { fn in
            interner.resolve(fn.name)
        }
        #expect(functionNames.contains("values"),
                "values() must be synthesized; got: \(functionNames)")
        #expect(functionNames.contains("entries$get"),
                "entries$get must be synthesized; got: \(functionNames)")

        // values() uses kk_enum_make_values_array; entries$get uses kk_enum_make_entries_list.
        let valuesFn = try findKIRFunction(named: "values", in: module, interner: interner)
        let valuesCallees = extractCallees(from: valuesFn.body, interner: interner)
        #expect(valuesCallees.contains("kk_enum_make_values_array"),
                "values() should call kk_enum_make_values_array; callees: \(valuesCallees)")
        #expect(!valuesCallees.contains("kk_enum_make_entries_list"),
                "values() must NOT call kk_enum_make_entries_list; callees: \(valuesCallees)")

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesCallees = extractCallees(from: entriesFn.body, interner: interner)
        #expect(entriesCallees.contains("kk_enum_make_entries_list"),
                "entries$get should call kk_enum_make_entries_list; callees: \(entriesCallees)")
        #expect(!entriesCallees.contains("kk_enum_make_values_array"),
                "entries$get must NOT call kk_enum_make_values_array; callees: \(entriesCallees)")
    }

    // MARK: - STDLIB-023-08: valueOf is synthesized and calls kk_string_equals_flat + kk_enum_valueOf_throw

    @Test
    func testEnumValueOfSynthesizedWithStringComparisonAndThrow() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Status",
            entryNames: ["ACTIVE", "INACTIVE", "PENDING"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumValueOf"
        )

        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        let callees = extractCallees(from: valueOfFn.body, interner: interner)

        #expect(callees.contains("kk_string_equals_flat"),
                "valueOf should call kk_string_equals_flat; callees: \(callees)")
        #expect(callees.contains("kk_enum_valueOf_throw"),
                "valueOf should call kk_enum_valueOf_throw; callees: \(callees)")
    }

    // MARK: - STDLIB-023-09: values() uses kk_enum_make_values_array (fresh array each call)

    @Test
    func testEnumValuesFunctionCallsValueArrayRuntime() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Coin",
            entryNames: ["HEADS", "TAILS"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumValuesFreshArray"
        )

        let valuesFn = try findKIRFunction(named: "values", in: module, interner: interner)
        let callees = extractCallees(from: valuesFn.body, interner: interner)

        // values() should always produce a fresh array via kk_enum_make_values_array.
        #expect(callees.contains("kk_array_new"),
                "values() should allocate a new array via kk_array_new; callees: \(callees)")
        #expect(callees.contains("kk_enum_make_values_array"),
                "values() should wrap the array via kk_enum_make_values_array; callees: \(callees)")
    }

    // MARK: - STDLIB-023-10: all per-entry name/ordinal helpers are present

    @Test
    func testAllPerEntryHelpersPresent() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let entryNames = ["ALPHA", "BETA", "GAMMA"]
        let (module, _, _) = try makeEnumModule(
            enumName: "Greek",
            entryNames: entryNames,
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumPerEntryHelpers"
        )

        let functionNames = findAllKIRFunctions(in: module).map { fn in
            interner.resolve(fn.name)
        }

        for name in entryNames {
            #expect(functionNames.contains("\(name)$enumOrdinal"),
                    "Missing \(name)$enumOrdinal; got: \(functionNames)")
            #expect(functionNames.contains("\(name)$enumName"),
                    "Missing \(name)$enumName; got: \(functionNames)")
        }

        // Verify per-entry name strings are correct.
        for name in entryNames {
            let nameFn = try findKIRFunction(named: "\(name)$enumName", in: module, interner: interner)
            let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
                guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
                return s
            }
            #expect(nameConsts.contains(interner.intern(name)),
                    "\(name)$enumName should return \"\(name)\"")
        }
    }

    // MARK: - STDLIB-023-11: valueOf body embeds enum class name prefix for error messages

    @Test
    func testValueOfEmbedClassNamePrefixForError() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Fruit",
            entryNames: ["APPLE", "BANANA"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumValueOfErrorPrefix"
        )

        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        let stringLiterals = valueOfFn.body.compactMap { inst -> String? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return interner.resolve(s)
        }
        // Kotlin error message format: "No enum constant Fruit.UNKNOWN"
        #expect(stringLiterals.contains("Fruit."),
                "valueOf should embed \"Fruit.\" prefix for error messages; got: \(stringLiterals)")
    }

    // MARK: - STDLIB-023-12: entries$get takes no parameters (zero-param getter)

    @Test
    func testEntriesGetterHasZeroParameters() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Flag",
            entryNames: ["ON", "OFF"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesZeroParams"
        )

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        // entries is a property getter (no value parameters).
        #expect(entriesFn.params.count == 0,
                "entries$get should have 0 parameters (property getter)")
    }

    @Test
    func testTopLevelEnumEntriesCallUsesEntriesRuntime() throws {
        let source = """
        enum class Color { RED, GREEN }

        fun useEntries() = enumEntries<Color>()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "enumEntries<Color>() should compile without diagnostics")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "useEntries", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_enum_make_entries_list"),
                    "enumEntries<Color>() should call kk_enum_make_entries_list; callees: \(callees)")
            #expect(!callees.contains("kk_enum_make_values_array"),
                    "enumEntries<Color>() must not call kk_enum_make_values_array; callees: \(callees)")
        }
    }

    // MARK: - STDLIB-023-13: `Direction.values()` (member-call-on-class-name
    // syntax, not the top-level `enumValues<T>()`) resolves at Sema time and
    // links to the exact same symbol as the KIR function synthesized by
    // DataEnumSealedSynthesisPass. Before the fix, Sema had no symbol for
    // `values()` at all ("Unresolved reference 'values'"); after registering
    // one, a naive Lowering-side re-`.define()` would have minted a *second*
    // disconnected SymbolID (functions may coexist as overloads), silently
    // orphaning the call site from the synthesized body.

    @Test
    func testDirectEnumValuesCallLinksToSynthesizedFunction() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            val v = Direction.values()
            println(v.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "Direction.values() should compile without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let valuesFunction = try findKIRFunction(named: "values", in: module, interner: ctx.interner)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            var foundValuesCall = false
            var valuesCallSymbol: SymbolID?
            for instruction in mainBody {
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "values"
                else { continue }
                foundValuesCall = true
                valuesCallSymbol = symbol
                break
            }

            #expect(foundValuesCall, "main() should contain a call to `values`")
            #expect(
                valuesCallSymbol == valuesFunction.symbol,
                """
                Direction.values() call site must resolve to the same symbol as the synthesized \
                `values` KIR function, otherwise the call is bound but silently unlinked at codegen
                """
            )
        }
    }

    // MARK: - STDLIB-023-14: `Direction.entries.forEach { }` / `.size` resolve.
    // Before the fix, `EnumEntries<T>` had no registered supertype at all, so
    // neither ordinary member-call resolution nor the collection member-call
    // fallback could discover List's members (forEach, size, ...) on an
    // EnumEntries-typed receiver ("Unresolved member function").
    //
    // Note on scope: this test only runs the pipeline through Lowering (no
    // Codegen/Link), so it verifies Sema resolution + KIR synthesis linkage
    // only. `d.name` inside the forEach lambda is included in the source to
    // mirror the real-world call shape, but its full runtime correctness is
    // NOT covered here: a full CLI compile+run confirmed that accessing
    // `.name` (or even a bare `println(d)`) on a collection-HOF lambda
    // parameter of enum type currently mis-lowers regardless of the
    // receiver collection (reproduced independently with a plain
    // `listOf(Direction.NORTH).forEach { d -> println(d.name) }`, with no
    // EnumEntries/values() involved at all) — a separate, pre-existing bug
    // in how enum-typed HOF lambda parameters are tracked, out of scope for
    // this member-resolution fix. `Direction.values().size` and
    // `Direction.entries.size` (see `Scripts/diff_cases/enum_values_and_entries.kt`)
    // are confirmed fully working end-to-end (compiled, linked, and run).
    @Test
    func testDirectionEntriesForEachAndSizeResolveWithoutDiagnostics() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            Direction.entries.forEach { d -> println(d.name) }
            println(Direction.entries.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "Direction.entries.forEach{}/.size should compile without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // `main()` calls the `entries$get` accessor directly (once for the
            // forEach receiver, once for .size's receiver); `entries$get`'s own
            // body is what calls kk_enum_make_entries_list (already covered by
            // testEnumEntriesGetterBodyUsesCorrectRuntimeCalls above), so it does
            // not appear in main's own callee list.
            #expect(callees.contains("entries$get"),
                    "Direction.entries should call the entries$get accessor; callees: \(callees)")
            #expect(callees.contains("kk_list_forEach"),
                    "Direction.entries.forEach should dispatch to the real List forEach runtime; callees: \(callees)")
            #expect(callees.contains("__kk_list_size"),
                    "Direction.entries.size should dispatch to the real List size runtime; callees: \(callees)")
        }
    }

    // MARK: - BUG-178: `Direction.entries[i]` / `enumEntries<T>()[i]` must
    // dispatch to the List `get` runtime. `EnumEntries<T>` is backed by a
    // `RuntimeListBox` (`kk_enum_make_entries_list`), but while the interface
    // had no registered `List<T>` supertype the indexing operator fell back to
    // the array bridge `kk_array_get`, which read the list handle as a
    // `RuntimeArrayBox`, threw ArrayIndexOutOfBounds and aborted the program
    // with `KSWIFTK-LINK-0003: Unhandled top-level exception`.
    @Test
    func testEnumEntriesIndexAccessUsesListGetNotArrayGet() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[0])
            println(enumEntries<Direction>()[1])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "entries[0]/enumEntries<T>()[1] should compile without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("__kk_list_get"),
                    "EnumEntries indexing should dispatch to the List get runtime; callees: \(callees)")
            #expect(!callees.contains("kk_array_get"),
                    "EnumEntries indexing must not fall back to the array bridge; callees: \(callees)")
        }
    }

    // MARK: - STDLIB-023-15: `Outer.Direction.values()`, a nested enum class
    // accessed through a class-name-receiver qualifier chain, resolves at Sema
    // time and links to the exact same symbol as the KIR function synthesized
    // by DataEnumSealedSynthesisPass -- mirroring
    // testDirectEnumValuesCallLinksToSynthesizedFunction above, but with the
    // added nesting hop that exposed a KIR-lowering bug:
    // `tryLowerClassNameMemberValueExpr` (CallLowerer+MemberPropertyReads.swift)
    // only special-cased class-name-receiver members of kind .property/.field/
    // .object, so a *further* nested-type qualifier segment like the `Direction`
    // in `Outer.Direction.values()` (kind .enumClass) fell through to a generic
    // fallback that lowered the `Outer.Direction` receiver as if it needed a
    // runtime value, emitting an unresolved 0-arg call literally named
    // "Direction" -- undefined at link time, since no such accessor exists for
    // a plain (non-object) nested class.

    @Test
    func testNestedEnumValuesCallLinksToSynthesizedFunctionWithoutSpuriousReceiverCall() throws {
        let source = """
        class Outer {
            enum class Direction { NORTH, SOUTH, EAST, WEST }
        }

        fun main() {
            val v = Outer.Direction.values()
            println(v.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "Outer.Direction.values() should compile without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let valuesFunction = try findKIRFunction(named: "values", in: module, interner: ctx.interner)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            var foundValuesCall = false
            var valuesCallSymbol: SymbolID?
            for instruction in mainBody {
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "values"
                else { continue }
                foundValuesCall = true
                valuesCallSymbol = symbol
                break
            }

            #expect(foundValuesCall, "main() should contain a call to `values`")
            #expect(
                valuesCallSymbol == valuesFunction.symbol,
                """
                Outer.Direction.values() call site must resolve to the same symbol as the synthesized \
                `values` KIR function, otherwise the call is bound but silently unlinked at codegen
                """
            )

            let spuriousReceiverCalls = mainBody.filter { instruction in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return false }
                return symbol == nil && ctx.interner.resolve(callee) == "Direction"
            }
            #expect(spuriousReceiverCalls.isEmpty,
                    "main() must not call the nested enum class's bare short name as if it were a 0-arg accessor; found: \(spuriousReceiverCalls)")
        }
    }

    // MARK: - STDLIB-023-16: `Outer.Direction.entries.forEach { }` / `.size`
    // resolve for a nested enum class, mirroring
    // testDirectionEntriesForEachAndSizeResolveWithoutDiagnostics above. Same
    // scope note applies: this only runs the pipeline through Lowering (no
    // Codegen/Link), so it verifies Sema resolution + KIR synthesis linkage
    // only, not full runtime correctness of `d.name` inside the forEach lambda
    // (a separate, pre-existing, unrelated bug in enum-typed HOF lambda
    // parameters -- see the top-level test's note).
    @Test
    func testNestedEnumEntriesForEachAndSizeResolveWithoutDiagnostics() throws {
        let source = """
        class Outer {
            enum class Direction { NORTH, SOUTH, EAST, WEST }
        }

        fun main() {
            Outer.Direction.entries.forEach { d -> println(d.name) }
            println(Outer.Direction.entries.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(!ctx.diagnostics.hasError,
                    "Outer.Direction.entries.forEach{}/.size should compile without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("entries$get"),
                    "Outer.Direction.entries should call the entries$get accessor; callees: \(callees)")
            #expect(callees.contains("kk_list_forEach"),
                    "Outer.Direction.entries.forEach should dispatch to the real List forEach runtime; callees: \(callees)")
            #expect(callees.contains("__kk_list_size"),
                    "Outer.Direction.entries.size should dispatch to the real List size runtime; callees: \(callees)")
        }
    }
}
#endif
