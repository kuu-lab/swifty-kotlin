#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {

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
            let entrySymbol = symbols.define(
                kind: .field,
                name: interner.intern(entryName),
                fqName: packagePath + [enumInternedName, interner.intern(entryName)],
                declSite: nil,
                visibility: .public
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        let arena = KIRArena()
        let decl = arena.appendDecl(.nominalType(KIRNominalType(symbol: enumSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [decl])], arena: arena)

        let ctx = try runLowering(module: module, interner: interner, moduleName: moduleName, sema: sema)
        return (module, enumSymbol, ctx)
    }

    @Test
    func testEnumEntriesGetterIsSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

    @Test
    func testEnumEntriesGetterBodyUsesCorrectRuntimeCalls() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

        #expect(callees.contains(RuntimeCall.arrayNew.name),
                "entries$get should call kk_array_new; callees: \(callees)")
        #expect(callees.contains(RuntimeCall.arraySet.name),
                "entries$get should call kk_array_set for each entry; callees: \(callees)")
        #expect(callees.contains(RuntimeCall.enumMakeEntriesListCached.name),
                "entries$get should call kk_enum_make_entries_list_cached; callees: \(callees)")
    }

    @Test
    func testEnumEntriesCountMatchesDeclaredCases() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Planet",
            entryNames: ["MERCURY", "VENUS", "EARTH", "MARS", "JUPITER"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesCount"
        )

        let countFn = try findKIRFunction(named: "Planet$enumValuesCount", in: module, interner: interner)
        let intConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(intConsts.contains(5),
                "Planet$enumValuesCount should embed count=5; got consts: \(intConsts)")

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesConsts = entriesFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(entriesConsts.contains(4),
                "entries$get should embed ordinal 4 (5th entry); got: \(entriesConsts)")
    }

    @Test
    func testEnumEntriesOrderMatchesDeclaration() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Season",
            entryNames: ["SPRING", "SUMMER", "AUTUMN", "WINTER"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesOrder"
        )

        let enumName = interner.intern("Season")
        let classSuffix = NameMangler.enumClassNameSuffix(for: [interner.intern("test"), enumName], interner: interner)

        for (expectedOrdinal, name) in ["SPRING", "SUMMER", "AUTUMN", "WINTER"].enumerated() {
            let fn = try findKIRFunction(named: "\(name)$enumOrdinal$\(classSuffix)", in: module, interner: interner)
            let consts = fn.body.compactMap { inst -> Int64? in
                guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
                return v
            }
            #expect(consts.contains(Int64(expectedOrdinal)),
                    "\(name)$enumOrdinal$\(classSuffix) should be \(expectedOrdinal); got: \(consts)")
        }
    }

    @Test
    func testEmptyEnumSynthesizesZeroCount() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let callees = extractCallees(from: entriesFn.body, interner: interner)
        #expect(!callees.contains(RuntimeCall.arraySet.name),
                "Empty enum entries$get must not call kk_array_set; callees: \(callees)")
        #expect(callees.contains(RuntimeCall.enumMakeEntriesListCached.name),
                "Empty enum entries$get must still call kk_enum_make_entries_list_cached; callees: \(callees)")
    }

    @Test
    func testSingleVariantEnumEntriesAndOrdinal() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Singleton",
            entryNames: ["ONLY"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesSingle"
        )

        let singletonSuffix = NameMangler.enumClassNameSuffix(for: [interner.intern("test"), interner.intern("Singleton")], interner: interner)

        let countFn = try findKIRFunction(named: "Singleton$enumValuesCount", in: module, interner: interner)
        let countConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(countConsts.contains(1), "Single-variant enum count should be 1; got: \(countConsts)")

        let ordinalFn = try findKIRFunction(named: "ONLY$enumOrdinal$\(singletonSuffix)", in: module, interner: interner)
        let ordinalConsts = ordinalFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        #expect(ordinalConsts.contains(0), "ONLY$enumOrdinal$\(singletonSuffix) should be 0; got: \(ordinalConsts)")

        let nameFn = try findKIRFunction(named: "ONLY$enumName$\(singletonSuffix)", in: module, interner: interner)
        let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return s
        }
        #expect(nameConsts.contains(interner.intern("ONLY")),
                "ONLY$enumName$\(singletonSuffix) should return \"ONLY\"")
    }

    @Test
    func testEnumValuesAndEntriesGetterBothSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

        let valuesFn = try findKIRFunction(named: "values", in: module, interner: interner)
        let valuesCallees = extractCallees(from: valuesFn.body, interner: interner)
        #expect(valuesCallees.contains(RuntimeCall.enumMakeValuesArray.name),
                "values() should call kk_enum_make_values_array; callees: \(valuesCallees)")
        #expect(!valuesCallees.contains(RuntimeCall.enumMakeEntriesListCached.name),
                "values() must NOT call kk_enum_make_entries_list_cached; callees: \(valuesCallees)")

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesCallees = extractCallees(from: entriesFn.body, interner: interner)
        #expect(entriesCallees.contains(RuntimeCall.enumMakeEntriesListCached.name),
                "entries$get should call kk_enum_make_entries_list_cached; callees: \(entriesCallees)")
        #expect(!entriesCallees.contains(RuntimeCall.enumMakeValuesArray.name),
                "entries$get must NOT call kk_enum_make_values_array; callees: \(entriesCallees)")
    }

    @Test
    func testEnumValueOfSynthesizedWithStringComparisonAndThrow() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

        #expect(callees.contains(RuntimeCall.stringEqualsFlat.name),
                "valueOf should call __kk_string_equals_flat; callees: \(callees)")
        #expect(callees.contains(RuntimeCall.enumValueOfThrow.name),
                "valueOf should call kk_enum_valueOf_throw; callees: \(callees)")
    }

    @Test
    func testEnumValuesFunctionCallsValueArrayRuntime() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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

        #expect(callees.contains(RuntimeCall.arrayNew.name),
                "values() should allocate a new array via kk_array_new; callees: \(callees)")
        #expect(callees.contains(RuntimeCall.enumMakeValuesArray.name),
                "values() should wrap the array via kk_enum_make_values_array; callees: \(callees)")
    }

    @Test
    func testAllPerEntryHelpersPresent() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

        let entryNames = ["ALPHA", "BETA", "GAMMA"]
        let (module, _, _) = try makeEnumModule(
            enumName: "Greek",
            entryNames: entryNames,
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumPerEntryHelpers"
        )

        let greekSuffix = NameMangler.enumClassNameSuffix(for: [interner.intern("test"), interner.intern("Greek")], interner: interner)

        let functionNames = findAllKIRFunctions(in: module).map { fn in
            interner.resolve(fn.name)
        }

        for name in entryNames {
            #expect(functionNames.contains("\(name)$enumOrdinal$\(greekSuffix)"),
                    "Missing \(name)$enumOrdinal$\(greekSuffix); got: \(functionNames)")
            #expect(functionNames.contains("\(name)$enumName$\(greekSuffix)"),
                    "Missing \(name)$enumName$\(greekSuffix); got: \(functionNames)")
        }

        for name in entryNames {
            let nameFn = try findKIRFunction(named: "\(name)$enumName$\(greekSuffix)", in: module, interner: interner)
            let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
                guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
                return s
            }
            #expect(nameConsts.contains(interner.intern(name)),
                    "\(name)$enumName$\(greekSuffix) should return \"\(name)\"")
        }
    }

    @Test
    func testValueOfEmbedClassNamePrefixForError() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

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
        #expect(stringLiterals.contains("test.Fruit."),
                "valueOf should embed \"test.Fruit.\" prefix for error messages; got: \(stringLiterals)")
    }

    @Test
    func testEntriesGetterHasZeroParameters() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: symbols, types: types).ctx

        let (module, _, _) = try makeEnumModule(
            enumName: "Flag",
            entryNames: ["ON", "OFF"],
            interner: interner,
            symbols: symbols,
            sema: sema,
            moduleName: "EnumEntriesZeroParams"
        )

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        #expect(entriesFn.params.count == 0,
                "entries$get should have 0 parameters (property getter)")
    }

    @Test
    func testTopLevelEnumEntriesCallUsesEntriesRuntime() throws {
        let source = """
        import kotlin.enums.enumEntries

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

            #expect(callees.contains(RuntimeCall.enumMakeEntriesListCached.name),
                    "enumEntries<Color>() should call kk_enum_make_entries_list_cached; callees: \(callees)")
            #expect(!callees.contains(RuntimeCall.enumMakeValuesArray.name),
                    "enumEntries<Color>() must not call kk_enum_make_values_array; callees: \(callees)")
        }
    }

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
                      callee == ctx.interner.intern("values")
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

            #expect(callees.contains("entries$get"),
                    "Direction.entries should call the entries$get accessor; callees: \(callees)")
            #expect(callees.contains(RuntimeCall.listForEach.name),
                    "Direction.entries.forEach should dispatch to the real List forEach runtime; callees: \(callees)")
            #expect(callees.contains(RuntimeCall.listSize.name),
                    "Direction.entries.size should dispatch to the real List size runtime; callees: \(callees)")
        }
    }

    @Test
    func testEnumEntriesIndexAccessUsesListGetNotArrayGet() throws {
        let source = """
        import kotlin.enums.enumEntries

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

            #expect(callees.contains(RuntimeCall.enumEntriesGet.name),
                    "EnumEntries indexing should dispatch to the List get runtime; callees: \(callees)")
            #expect(!callees.contains(RuntimeCall.arrayGet.name),
                    "EnumEntries indexing must not fall back to the array bridge; callees: \(callees)")
        }
    }

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
                      callee == ctx.interner.intern("values")
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
                return symbol == nil && callee == ctx.interner.intern("Direction")
            }
            #expect(spuriousReceiverCalls.isEmpty,
                    "main() must not call the nested enum class's bare short name as if it were a 0-arg accessor; found: \(spuriousReceiverCalls)")
        }
    }

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
            #expect(callees.contains(RuntimeCall.listForEach.name),
                    "Outer.Direction.entries.forEach should dispatch to the real List forEach runtime; callees: \(callees)")
            #expect(callees.contains(RuntimeCall.listSize.name),
                    "Outer.Direction.entries.size should dispatch to the real List size runtime; callees: \(callees)")
        }
    }
}
#endif
