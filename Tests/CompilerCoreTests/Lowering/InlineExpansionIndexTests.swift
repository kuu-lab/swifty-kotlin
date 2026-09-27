#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineExpansionIndexTests {
    private func makeFunction(
        _ name: String,
        symbol: Int32,
        interner: StringInterner,
        types: TypeSystem,
        body: [KIRInstruction] = [.returnUnit],
        isInline: Bool = false,
        isInlineOnly: Bool = false,
        params: [KIRParameter] = [],
        sourceRange: SourceRange? = nil
    ) -> KIRFunction {
        KIRFunction(
            symbol: SymbolID(rawValue: symbol), name: interner.intern(name),
            params: params, returnType: types.unitType,
            body: body, isSuspend: false, isInline: isInline,
            isInlineOnly: isInlineOnly, sourceRange: sourceRange
        )
    }

    private func makeModule(_ functions: [KIRFunction]) -> KIRModule {
        let arena = KIRArena()
        for function in functions {
            _ = arena.appendDecl(.function(function))
        }
        return KIRModule(files: [], arena: arena)
    }

    private func call(
        to symbol: SymbolID?,
        callee: String,
        interner: StringInterner
    ) -> KIRInstruction {
        .call(
            symbol: symbol, callee: interner.intern(callee),
            arguments: [], result: nil, canThrow: false, thrownResult: nil
        )
    }

    // MARK: - Classification

    @Test
    func testIndexClassifiesModuleImportedLambdaAndBodylessEntries() {
        let interner = StringInterner()
        let types = TypeSystem()
        let inlineDecl = makeFunction(
            "regularInline", symbol: 1, interner: interner, types: types, isInline: true
        )
        let bodylessDecl = makeFunction(
            "autoInline", symbol: 2, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        // A lambda body is just a module function that is not `inline`: it
        // lives in the module table but never becomes an expansion target.
        let lambdaBody = makeFunction("caller$lambda", symbol: 3, interner: interner, types: types)
        let regularDecl = makeFunction("helper", symbol: 4, interner: interner, types: types)
        let imported = makeFunction("libInline", symbol: 5, interner: interner, types: types)

        let index = InlineExpansionIndex(
            module: makeModule([inlineDecl, bodylessDecl, lambdaBody, regularDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore(functions: [imported.symbol: imported])
        )

        // Module `inline` declaration: expansion target, module origin, not bodyless.
        #expect(index.origin(of: inlineDecl.symbol) == .module)
        #expect(index.isExpansionTarget(inlineDecl.symbol))
        #expect(!index.isBodyless(inlineDecl.symbol))

        // Module `isInlineOnly`: expansion target, module origin, bodyless.
        #expect(index.origin(of: bodylessDecl.symbol) == .module)
        #expect(index.isBodyless(bodylessDecl.symbol))

        // Imported inline body: expansion target, imported origin, bodyless.
        #expect(index.origin(of: imported.symbol) == .imported)
        #expect(index.isExpansionTarget(imported.symbol))
        #expect(index.isBodyless(imported.symbol))
        // ...but never enters the module-declared table used by lambda resolution.
        #expect(index.allFunctionsBySymbol[imported.symbol] == nil)

        // Lambda body and regular module functions: module-declared, resolvable
        // for lambda expansion, never expansion targets and never bodyless.
        for function in [lambdaBody, regularDecl] {
            #expect(index.allFunctionsBySymbol[function.symbol]?.symbol == function.symbol)
            #expect(!index.isExpansionTarget(function.symbol))
            #expect(index.origin(of: function.symbol) == nil)
            #expect(!index.isBodyless(function.symbol))
        }
    }

    @Test
    func testImportedBodyDoesNotShadowAModuleDeclarationWithTheSameSymbol() {
        let interner = StringInterner()
        let types = TypeSystem()
        // A module declares symbol 9 non-inline; imported metadata carries an
        // inline body for the same symbol. The two tables keep their own
        // bodies: the target table gets the imported body while the module
        // table keeps the declaration.
        let moduleDecl = makeFunction("shared", symbol: 9, interner: interner, types: types)
        let imported = makeFunction(
            "shared", symbol: 9, interner: interner, types: types, isInline: true
        )

        let index = InlineExpansionIndex(
            module: makeModule([moduleDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore(functions: [imported.symbol: imported])
        )

        // The target table holds the imported body; the module table keeps
        // the module's own declaration.
        #expect(index.inlineFunctionsBySymbol[SymbolID(rawValue: 9)]?.isInline == true)
        #expect(index.allFunctionsBySymbol[SymbolID(rawValue: 9)]?.isInline == false)
        #expect(index.origin(of: SymbolID(rawValue: 9)) == .imported)
        #expect(index.isBodyless(SymbolID(rawValue: 9)))
        // The frozen original for scheduling is the module declaration.
        #expect(index.originalBodies[SymbolID(rawValue: 9)]?.isInline == false)
    }

    // MARK: - Call-site target resolution

    @Test
    func testKnownSymbolCallBindsOnlyToItsOwnSnapshot() {
        let interner = StringInterner()
        let types = TypeSystem()
        let inlineDecl = makeFunction(
            "withLock", symbol: 1, interner: interner, types: types, isInline: true
        )
        let index = InlineExpansionIndex(
            module: makeModule([inlineDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let byName = index.inlineFunctionsByName

        // A call whose known symbol is the inline declaration binds to it.
        #expect(index.inlineTarget(
            callSymbol: inlineDecl.symbol,
            callee: interner.intern("withLock"),
            inlineFunctionsByName: byName
        )?.symbol == inlineDecl.symbol)
    }

    @Test
    func testKnownSymbolCallIsNeverRedirectedToSameNamedFallback() {
        let interner = StringInterner()
        let types = TypeSystem()
        // `Mutex.withLock` (inline target) and `Lock.withLock` (different
        // symbol, not in the module's inline table) share a name (KSP-1011).
        let mutexWithLock = makeFunction(
            "withLock", symbol: 1, interner: interner, types: types, isInline: true
        )
        let index = InlineExpansionIndex(
            module: makeModule([mutexWithLock]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let byName = index.inlineFunctionsByName
        let unrelatedSymbol = SymbolID(rawValue: 99)

        // The by-name table does contain a unique `withLock` candidate, but a
        // call whose symbol is *known* and not an expansion target must not
        // take it.
        #expect(byName[interner.intern("withLock")] == [mutexWithLock.symbol])
        #expect(index.inlineTarget(
            callSymbol: unrelatedSymbol,
            callee: interner.intern("withLock"),
            inlineFunctionsByName: byName
        ) == nil)
    }

    @Test
    func testSymbolUnknownCallUsesOnlyAUniqueNameCandidate() {
        let interner = StringInterner()
        let types = TypeSystem()
        let only = makeFunction(
            "unique", symbol: 1, interner: interner, types: types, isInline: true
        )
        let first = makeFunction(
            "overloaded", symbol: 2, interner: interner, types: types, isInline: true
        )
        let second = makeFunction(
            "overloaded", symbol: 3, interner: interner, types: types, isInline: true,
            params: [KIRParameter(symbol: SymbolID(rawValue: 30), type: types.intType)]
        )
        let index = InlineExpansionIndex(
            module: makeModule([only, first, second]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let byName = index.inlineFunctionsByName

        #expect(index.inlineTarget(
            callSymbol: nil,
            callee: interner.intern("unique"),
            inlineFunctionsByName: byName
        )?.symbol == only.symbol)
        // Two candidates under one name is ambiguous: no fallback.
        #expect(index.inlineTarget(
            callSymbol: nil,
            callee: interner.intern("overloaded"),
            inlineFunctionsByName: byName
        ) == nil)
        // No candidates at all: no fallback.
        #expect(index.inlineTarget(
            callSymbol: nil,
            callee: interner.intern("missing"),
            inlineFunctionsByName: byName
        ) == nil)
    }

    // MARK: - Bodyless dependency edges

    @Test
    func testBodylessCalleesTracksResolvedSymbolEdgesOnly() {
        let interner = StringInterner()
        let types = TypeSystem()
        let bodyless = SymbolID(rawValue: 10)
        let bodylessDecl = makeFunction(
            "gone", symbol: 10, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let regular = SymbolID(rawValue: 11)
        let caller = makeFunction(
            "caller", symbol: 12, interner: interner, types: types,
            body: [
                call(to: bodyless, callee: "gone", interner: interner),
                // A symbol-unknown call to the same name is a call-site
                // fallback concern, not a dependency edge.
                call(to: nil, callee: "gone", interner: interner),
                // A resolved call to a non-bodyless callee is no edge either.
                call(to: regular, callee: "helper", interner: interner),
            ]
        )
        let index = InlineExpansionIndex(
            module: makeModule([bodylessDecl, caller]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )

        #expect(index.bodylessCallees(of: caller.symbol) == [bodyless])
        #expect(index.pendingBodylessCallers(interner: interner) == [caller.symbol])
    }

    @Test
    func testBodylessCalleesIgnoresSelfCalls() {
        let interner = StringInterner()
        let types = TypeSystem()
        let recursive = makeFunction(
            "selfCall", symbol: 10, interner: interner, types: types,
            body: [call(to: SymbolID(rawValue: 10), callee: "selfCall", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let index = InlineExpansionIndex(
            module: makeModule([recursive]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )

        #expect(index.bodylessCallees(of: recursive.symbol).isEmpty)
        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
    }

    @Test
    func testPendingEdgesFollowTheCurrentSnapshotAfterWriteBack() {
        let interner = StringInterner()
        let types = TypeSystem()
        let bodyless = SymbolID(rawValue: 10)
        let bodylessDecl = makeFunction(
            "gone", symbol: 10, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let caller = makeFunction(
            "caller", symbol: 12, interner: interner, types: types,
            body: [call(to: bodyless, callee: "gone", interner: interner)]
        )
        var index = InlineExpansionIndex(
            module: makeModule([bodylessDecl, caller]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        #expect(index.pendingBodylessCallers(interner: interner) == [caller.symbol])

        // Simulates one scheduling round: the recorded expansion replaced the
        // bodyless call, so the symbol drops out of the pending set even
        // though its frozen original still contains it.
        var expanded = caller
        expanded.replaceBody([.returnUnit], locations: [nil])
        index.recordExpansion(of: caller.symbol, to: expanded)
        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
        #expect(index.bodylessCallees(of: caller.symbol).isEmpty)
        #expect(index.originalBodies[caller.symbol]?.body != expanded.body)
    }

    // MARK: - Deterministic ordering

    @Test
    func testPendingOrderIsIndependentOfDeclarationAndInsertionOrder() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let bodyless = SymbolID(rawValue: 90)
        // Symbol raw values deliberately disagree with the name order so the
        // sorted output proves ordering came from the comparator, not the
        // dictionary's storage order.
        let spec: [(name: String, symbol: Int32, params: Int)] = [
            ("zeta", 30, 0),
            ("alpha", 20, 1),
            ("alpha", 10, 0),
            ("mid", 40, 0),
        ]
        func caller(_ name: String, _ symbol: Int32, _ paramCount: Int) -> KIRFunction {
            makeFunction(
                name, symbol: symbol, interner: interner, types: types,
                body: [call(to: bodyless, callee: "gone", interner: interner)],
                params: (0 ..< paramCount).map {
                    KIRParameter(symbol: SymbolID(rawValue: Int32(1000 + $0)), type: types.intType)
                }
            )
        }
        let orderedDecls = spec.map { caller($0.name, $0.symbol, $0.params) }
        let reversedDecls = spec.reversed().map { caller($0.name, $0.symbol, $0.params) }
        let bodylessDecl = makeFunction(
            "gone", symbol: 90, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )

        let forwardIndex = InlineExpansionIndex(
            module: makeModule(orderedDecls + [bodylessDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let reversedIndex = InlineExpansionIndex(
            module: makeModule(reversedDecls + [bodylessDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )

        // Expected order: "alpha" 0-param (sym 10), "alpha" 1-param (sym 20),
        // "mid" (sym 40), "zeta" (sym 30) -- name, then param count, then
        // source range, then symbol.
        let expected = [
            SymbolID(rawValue: 10), SymbolID(rawValue: 20),
            SymbolID(rawValue: 40), SymbolID(rawValue: 30),
        ]
        #expect(forwardIndex.pendingBodylessCallers(interner: interner) == expected)
        #expect(reversedIndex.pendingBodylessCallers(interner: interner) == expected)
    }

    @Test
    func testSnapshotExpansionOrderUsesSymbolAsFinalTiebreaker() {
        let interner = StringInterner()
        let types = TypeSystem()
        // Same name, same param count, no source range: only the symbol
        // distinguishes them, so the order is total regardless of input.
        let high = makeFunction("same", symbol: 50, interner: interner, types: types)
        let low = makeFunction("same", symbol: 40, interner: interner, types: types)

        #expect(InlineExpansionIndex.snapshotExpansionOrder(low, high, interner: interner))
        #expect(!InlineExpansionIndex.snapshotExpansionOrder(high, low, interner: interner))

        // With name and param count tied, a range-less function sorts before
        // a ranged one (the comparator prefers the body carrying no range).
        let ranged = makeFunction(
            "same", symbol: 60, interner: interner, types: types,
            sourceRange: SourceRange(
                start: SourceLocation(file: FileID(rawValue: 0), offset: 0),
                end: SourceLocation(file: FileID(rawValue: 0), offset: 5)
            )
        )
        #expect(InlineExpansionIndex.snapshotExpansionOrder(low, ranged, interner: interner))
        #expect(!InlineExpansionIndex.snapshotExpansionOrder(ranged, low, interner: interner))
    }

    // MARK: - Mandatory-expansion contract

    @Test
    func testMandatoryExpansionCallRequiresABodylessBinding() {
        let interner = StringInterner()
        let types = TypeSystem()
        let bodyless = makeFunction(
            "autoInline", symbol: 10, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let regularInline = makeFunction(
            "explicitInline", symbol: 11, interner: interner, types: types, isInline: true
        )
        let plainDecl = makeFunction("helper", symbol: 12, interner: interner, types: types)
        let index = InlineExpansionIndex(
            module: makeModule([bodyless, regularInline, plainDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let byName = index.inlineFunctionsByName

        // A symbol-known call is mandatory iff its symbol is bodyless.
        #expect(index.isMandatoryExpansionCall(
            callSymbol: bodyless.symbol, callee: interner.intern("autoInline"),
            inlineFunctionsByName: byName
        ))
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: regularInline.symbol, callee: interner.intern("explicitInline"),
            inlineFunctionsByName: byName
        ))
        // A regular `inline` body is emitted, so leaving its call behind is
        // legal -- the same goes for calls that never were expansion targets.
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: plainDecl.symbol, callee: interner.intern("helper"),
            inlineFunctionsByName: byName
        ))
        // A known non-target symbol is never redirected to the by-name
        // table, even when a same-named bodyless candidate exists
        // (KSP-1011): the call below names a non-bodyless `autoInline`.
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: SymbolID(rawValue: 99), callee: interner.intern("autoInline"),
            inlineFunctionsByName: byName
        ))
    }

    @Test
    func testSymbolUnknownMandatoryCallUsesOnlyAUniqueBodylessCandidate() {
        let interner = StringInterner()
        let types = TypeSystem()
        let bodyless = makeFunction(
            "unique", symbol: 10, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let regularInline = makeFunction(
            "regular", symbol: 11, interner: interner, types: types, isInline: true
        )
        let overloadA = makeFunction(
            "overloaded", symbol: 12, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let overloadB = makeFunction(
            "overloaded", symbol: 13, interner: interner, types: types,
            isInline: true, isInlineOnly: true,
            params: [KIRParameter(symbol: SymbolID(rawValue: 130), type: types.intType)]
        )
        let index = InlineExpansionIndex(
            module: makeModule([bodyless, regularInline, overloadA, overloadB]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let byName = index.inlineFunctionsByName

        #expect(index.isMandatoryExpansionCall(
            callSymbol: nil, callee: interner.intern("unique"),
            inlineFunctionsByName: byName
        ))
        // The unique candidate is a regular inline function: not bodyless.
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: nil, callee: interner.intern("regular"),
            inlineFunctionsByName: byName
        ))
        // Both `overloaded` candidates are bodyless, but the call cannot
        // name either uniquely, so no residue verdict is possible.
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: nil, callee: interner.intern("overloaded"),
            inlineFunctionsByName: byName
        ))
        #expect(!index.isMandatoryExpansionCall(
            callSymbol: nil, callee: interner.intern("missing"),
            inlineFunctionsByName: byName
        ))
    }

    @Test
    func testRecursiveBodylessCalleesFindsSelfLoopMutualAndCycleEntry() {
        let interner = StringInterner()
        let types = TypeSystem()
        let selfCall = SymbolID(rawValue: 10)
        let even = SymbolID(rawValue: 11)
        let odd = SymbolID(rawValue: 12)
        let entry = SymbolID(rawValue: 13)
        let acyclic = SymbolID(rawValue: 14)
        let leaf = SymbolID(rawValue: 15)
        func bodylessDecl(
            _ name: String, _ symbol: SymbolID, calls: [(SymbolID, String)]
        ) -> KIRFunction {
            makeFunction(
                name, symbol: symbol.rawValue, interner: interner, types: types,
                body: calls.map { call(to: $0.0, callee: $0.1, interner: interner) },
                isInline: true, isInlineOnly: true
            )
        }
        let decls = [
            // Self-loop: a one-node cycle.
            bodylessDecl("selfCall", selfCall, calls: [(selfCall, "selfCall")]),
            // Mutual recursion: a two-node cycle.
            bodylessDecl("even", even, calls: [(odd, "odd")]),
            bodylessDecl("odd", odd, calls: [(even, "even")]),
            // Not on a cycle itself, but every expansion lands in one.
            bodylessDecl("entry", entry, calls: [(even, "even")]),
            // Acyclic: reaches a plain leaf, never a cycle.
            bodylessDecl("acyclic", acyclic, calls: [(leaf, "leaf")]),
            makeFunction("leaf", symbol: leaf.rawValue, interner: interner, types: types),
        ]
        let index = InlineExpansionIndex(
            module: makeModule(decls),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )

        let recursive = index.recursiveBodylessCallees()
        #expect(recursive == [selfCall, even, odd, entry])
    }

    @Test
    func testRecursiveBodylessCalleesIsEmptyWhenAcyclic() {
        let interner = StringInterner()
        let types = TypeSystem()
        let inner = SymbolID(rawValue: 10)
        let outer = SymbolID(rawValue: 11)
        let innerDecl = makeFunction(
            "inner", symbol: inner.rawValue, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let outerDecl = makeFunction(
            "outer", symbol: outer.rawValue, interner: interner, types: types,
            body: [call(to: inner, callee: "inner", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let index = InlineExpansionIndex(
            module: makeModule([innerDecl, outerDecl]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )

        #expect(index.recursiveBodylessCallees().isEmpty)
    }

    @Test
    func testRecursiveBodylessCalleesTracksTheCurrentSnapshot() {
        let interner = StringInterner()
        let types = TypeSystem()
        let selfCall = SymbolID(rawValue: 10)
        let recursive = makeFunction(
            "selfCall", symbol: selfCall.rawValue, interner: interner, types: types,
            body: [call(to: selfCall, callee: "selfCall", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let index = InlineExpansionIndex(
            module: makeModule([recursive]),
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        #expect(index.recursiveBodylessCallees() == [selfCall])

        // Once a recorded expansion removes the self-call edge, the callee
        // is no longer recursive.
        var expanded = recursive
        expanded.replaceBody([.returnUnit], locations: [nil])
        index.recordExpansion(of: recursive.symbol, to: expanded)
        #expect(index.recursiveBodylessCallees().isEmpty)
    }
}
#endif
