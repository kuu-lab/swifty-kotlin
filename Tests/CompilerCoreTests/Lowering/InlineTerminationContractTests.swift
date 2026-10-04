#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Termination contracts for the inline pass (RF-LOWER-INLINE-010): calls
/// to bodyless callees -- `isInlineOnly` declarations and imported inline
/// symbols whose bodies never reach an object file -- must not be left for
/// the linker. The pass stops with a deterministic `KSWIFTK-INL-0001`
/// diagnostic on recursion or an exhausted expansion budget, while calls to
/// regular `inline` functions may legally remain as calls.
struct InlineTerminationContractTests {
    private func makeFunction(
        _ name: String,
        symbol: Int32,
        interner: StringInterner,
        types: TypeSystem,
        body: [KIRInstruction] = [.returnUnit],
        isInline: Bool = false,
        isInlineOnly: Bool = false,
        params: [KIRParameter] = []
    ) -> KIRFunction {
        KIRFunction(
            symbol: SymbolID(rawValue: symbol), name: interner.intern(name),
            params: params, returnType: types.unitType,
            body: body, isSuspend: false, isInline: isInline,
            isInlineOnly: isInlineOnly
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
        interner: StringInterner,
        arguments: [KIRExprID] = []
    ) -> KIRInstruction {
        .call(
            symbol: symbol, callee: interner.intern(callee),
            arguments: arguments, result: nil, canThrow: false, thrownResult: nil
        )
    }

    private func makeContext(
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> KIRContext {
        let context = makeCompilationContext(inputs: [], includeStdlib: false)
        return KIRContext(
            diagnostics: diagnostics, options: context.options, interner: interner
        )
    }

    private func callTargets(
        of function: KIRFunction, interner: StringInterner
    ) -> [(symbol: SymbolID?, callee: String)] {
        function.body.compactMap { instruction in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                return nil
            }
            return (symbol, interner.resolve(callee))
        }
    }

    // MARK: - Bodyless-snapshot dependency scheduling

    /// Caller-first names exceed both the former four snapshot rounds and
    /// the eight caller rescans. Each side effect must appear exactly once.
    @Test(arguments: [(5, false), (80, false), (80, true)])
    func testBodylessChainConverges(depth: Int, imported: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let leaf = makeFunction("leaf", symbol: 100, interner: interner, types: types)
        var chain: [KIRFunction] = []
        for i in 1 ... depth {
            let next = i == depth
                ? (leaf.symbol, "leaf")
                : (SymbolID(rawValue: Int32(i + 1)), String(format: "f%03d", i + 1))
            chain.append(makeFunction(
                String(format: "f%03d", i), symbol: Int32(i), interner: interner,
                types: types,
                body: [
                    call(to: nil, callee: "effect\(i)", interner: interner),
                    call(to: next.0, callee: next.1, interner: interner),
                    .returnUnit,
                ],
                isInline: true, isInlineOnly: true
            ))
        }
        let main = makeFunction(
            "main", symbol: 1000, interner: interner, types: types,
            body: [call(to: chain[0].symbol, callee: "f001", interner: interner)]
        )
        let module = makeModule((imported ? [] : chain) + [leaf, main])
        let index = InlineExpansionIndex(
            module: module, importedInlineFunctions: ImportedInlineFunctionStore(
                functions: imported ? Dictionary(uniqueKeysWithValues: chain.map { ($0.symbol, $0) }) : [:]
            )
        )
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(
            index: index, module: module, ctx: ctx, unitType: nil
        )

        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
        let expected = (1 ... depth).map { "effect\($0)" } + ["leaf"]
        let first = try #require(index.inlineFunctionsBySymbol[chain[0].symbol])
        #expect(callTargets(of: first, interner: interner).map(\.callee) == expected)
        let caller = try #require(index.allFunctionsBySymbol[main.symbol])
        #expect(callTargets(of: caller, interner: interner).map(\.callee) == expected)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test(arguments: [false, true])
    func testDiamondExpansionIsDeterministicAndDoesNotRepeatOriginals(reverse: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let marker = module.arena.appendExpr(.intLiteral(7), type: types.intType)
        let shared = makeFunction(
            "zShared", symbol: 4, interner: interner, types: types,
            body: [.constValue(result: marker, value: .intLiteral(7)), .returnUnit],
            isInline: true, isInlineOnly: true
        )
        let branches = ["bLeft", "cRight"].enumerated().map { offset, name in
            makeFunction(
                name, symbol: Int32(offset + 2), interner: interner, types: types,
                body: [call(to: shared.symbol, callee: "zShared", interner: interner), .returnUnit],
                isInline: true, isInlineOnly: true
            )
        }
        let root = makeFunction(
            "aRoot", symbol: 1, interner: interner, types: types,
            body: branches.map { call(to: $0.symbol, callee: interner.resolve($0.name), interner: interner) },
            isInline: true, isInlineOnly: true
        )
        let functions = [root] + branches + [shared]
        for function in reverse ? functions.reversed() : functions {
            _ = module.arena.appendDecl(.function(function))
        }
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(index: index, module: module, ctx: ctx, unitType: nil)

        // One clone per branch, two in root: revisiting an original would
        // allocate additional expressions even if the final body looked right.
        #expect(module.arena.expressions.count == 5)
        let body = try #require(index.inlineFunctionsBySymbol[root.symbol]).body
        let results = body.compactMap { instruction -> Int32? in
            guard case let .constValue(result, .intLiteral(7)) = instruction else { return nil }
            return result.rawValue
        }
        #expect(results == [3, 4])
        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test(arguments: [false, true])
    func testDeepDependenciesInsideLambdasArePreparedFirst(useTemporary: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let depth = 48
        var functions: [KIRFunction] = []
        for i in 1 ... depth {
            let lambdaSymbol = SymbolID(rawValue: Int32(100 + i))
            let lambdaRef = useTemporary
                ? module.arena.appendTemporary(type: types.anyType)
                : module.arena.appendExpr(.symbolRef(lambdaSymbol), type: types.anyType)
            let prefix: [KIRInstruction] = useTemporary
                ? [.constValue(result: lambdaRef, value: .symbolRef(lambdaSymbol))] : []
            functions.append(makeFunction(
                String(format: "f%03d", i), symbol: Int32(i), interner: interner, types: types,
                body: prefix + [
                    call(to: nil, callee: "kk_function_invoke", interner: interner, arguments: [lambdaRef]),
                    .returnUnit,
                ], isInline: true, isInlineOnly: true
            ))
            let next = i == depth ? "leaf" : String(format: "f%03d", i + 1)
            functions.append(makeFunction(
                "zLambda\(i)", symbol: lambdaSymbol.rawValue, interner: interner, types: types,
                body: [
                    call(to: nil, callee: "effect\(i)", interner: interner),
                    call(to: i == depth ? nil : SymbolID(rawValue: Int32(i + 1)), callee: next, interner: interner),
                    .returnUnit,
                ]
            ))
        }
        for function in functions {
            _ = module.arena.appendDecl(.function(function))
        }
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(index: index, module: module, ctx: ctx, unitType: nil)

        let first = try #require(index.inlineFunctionsBySymbol[SymbolID(rawValue: 1)])
        #expect(callTargets(of: first, interner: interner).map(\.callee) == (1 ... depth).map { "effect\($0)" } + ["leaf"])
        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test
    func testDeferredImportedChainIsDiscoveredWithoutParsingUnusedBodies() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ImportedInlineFunctionStore()
        let depth = 80
        let symbols = Dictionary(uniqueKeysWithValues: (1 ... depth).map { ("f\($0)", SymbolID(rawValue: Int32($0))) })
        store.bindParseContext(
            types: types, interner: interner, diagnostics: diagnostics,
            externalLinkNameToSymbol: symbols, importedSymbolByFQName: [:]
        )
        for i in 1 ... depth {
            let name = "f\(i)"
            let next = i == depth ? "leaf" : "f\(i + 1)"
            let path = directory.appendingPathComponent("\(name).kirbin")
            let contents = """
            version=2
            nameB64=\(Data(name.utf8).base64EncodedString())
            params=0
            body:
            call calleeB64=\(Data(next.utf8).base64EncodedString()) linkB64=\(Data(next.utf8).base64EncodedString()) args=[] canThrow=false
            returnUnit
            """
            try contents.write(to: path, atomically: true, encoding: .utf8)
            store.register(.init(path: path.path, signature: nil, name: interner.intern(name)), for: symbols[name]!)
        }
        let unused = SymbolID(rawValue: 900)
        store.register(
            .init(path: directory.appendingPathComponent("unused.kirbin").path, signature: nil, name: interner.intern("unused")),
            for: unused
        )
        let main = makeFunction(
            "main", symbol: 1000, interner: interner, types: types,
            // Exercise the unique-name fallback as well as resolved imported edges.
            body: [call(to: nil, callee: "f1", interner: interner)]
        )
        let module = makeModule([main])
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: store)
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(index: index, module: module, ctx: ctx, unitType: nil)

        #expect(store.functions.count == depth)
        #expect(Set(store.descriptors.keys) == [unused])
        #expect(store.failedSymbols.isEmpty)
        let caller = try #require(index.allFunctionsBySymbol[main.symbol])
        #expect(callTargets(of: caller, interner: interner).map(\.callee) == ["leaf"])
        #expect(diagnostics.diagnostics.isEmpty)
    }

    /// A bodyless mutual-recursion pair can never satisfy the pending set:
    /// one finite visit leaves mandatory residue rather than retrying the
    /// cycle indefinitely.
    @Test
    func testMutuallyRecursiveBodylessCalleesStayPendingAndLeaveResidue() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let even = SymbolID(rawValue: 1)
        let odd = SymbolID(rawValue: 2)
        let evenDecl = makeFunction(
            "even", symbol: even.rawValue, interner: interner, types: types,
            body: [call(to: odd, callee: "odd", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let oddDecl = makeFunction(
            "odd", symbol: odd.rawValue, interner: interner, types: types,
            body: [call(to: even, callee: "even", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let module = makeModule([evenDecl, oddDecl])
        let index = InlineExpansionIndex(
            module: module, importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(
            index: index, module: module, ctx: ctx, unitType: nil
        )

        #expect(!index.pendingBodylessCallers(interner: interner).isEmpty)
        for symbol in [even, odd] {
            let body = try #require(index.allFunctionsBySymbol[symbol]?.body)
            #expect(body.contains { instruction in
                guard case let .call(callSymbol, _, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return callSymbol == even || callSymbol == odd
            })
        }
        #expect(!ctx.diagnostics.hasError)
    }

    /// The full pass over a bodyless mutual-recursion module diagnoses every
    /// leftover mandatory call -- inside both cycle members and the outside
    /// caller -- with the recursion cause, instead of leaving dangling
    /// symbols for the linker.
    @Test
    func testMutuallyRecursiveBodylessModuleEmitsRecursionDiagnostics() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let even = SymbolID(rawValue: 1)
        let odd = SymbolID(rawValue: 2)
        let evenDecl = makeFunction(
            "even", symbol: even.rawValue, interner: interner, types: types,
            body: [call(to: odd, callee: "odd", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let oddDecl = makeFunction(
            "odd", symbol: odd.rawValue, interner: interner, types: types,
            body: [call(to: even, callee: "even", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let main = makeFunction(
            "main", symbol: 3, interner: interner, types: types,
            body: [call(to: even, callee: "even", interner: interner)]
        )
        let module = makeModule([evenDecl, oddDecl, main])
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        try InlineLoweringPass().run(module: module, ctx: ctx)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3)
        for error in errors {
            #expect(error.code == "KSWIFTK-INL-0001")
            #expect(error.message.contains("recursive"))
        }
    }

    /// A bodyless self-call is a one-node cycle: `bodylessCallees` keeps it
    /// out of the pending set, but the residue diagnostic still reports it
    /// (in the recursive declaration itself and in its callers).
    @Test
    func testSelfRecursiveBodylessCalleeIsDiagnosed() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let selfCall = SymbolID(rawValue: 1)
        let selfCallDecl = makeFunction(
            "selfCall", symbol: selfCall.rawValue, interner: interner, types: types,
            body: [call(to: selfCall, callee: "selfCall", interner: interner)],
            isInline: true, isInlineOnly: true
        )
        let main = makeFunction(
            "main", symbol: 2, interner: interner, types: types,
            body: [call(to: selfCall, callee: "selfCall", interner: interner)]
        )
        let module = makeModule([selfCallDecl, main])
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        try InlineLoweringPass().run(module: module, ctx: ctx)

        let errors = diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-INL-0001"
        }
        // One residue in `selfCall` itself, one in `main`.
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.message.contains("recursive") })
        #expect(errors.allSatisfy { $0.message.contains("selfCall") })
    }

    /// A mandatory call that fails expansion for a non-cycle reason (here a
    /// parameter/argument count mismatch) is still diagnosed -- the cause
    /// falls back to the expansion budget rather than recursion.
    @Test
    func testFailedMandatoryExpansionReportsBudgetExhaustion() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let gone = SymbolID(rawValue: 1)
        let goneDecl = makeFunction(
            "gone", symbol: gone.rawValue, interner: interner, types: types,
            isInline: true, isInlineOnly: true,
            params: [KIRParameter(symbol: SymbolID(rawValue: 10), type: types.intType)]
        )
        // Zero-argument call to a one-parameter callee: expansion fails and
        // the call is kept verbatim -- residue for the residue scan.
        let main = makeFunction(
            "main", symbol: 2, interner: interner, types: types,
            body: [call(to: gone, callee: "gone", interner: interner)]
        )
        let module = makeModule([goneDecl, main])
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        try InlineLoweringPass().run(module: module, ctx: ctx)

        let errors = diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-INL-0001"
        }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("reached its limit") == true)
    }

    // MARK: - Caller rescan boundary (8 rounds)

    /// A regular `inline` delegation chain converges after one rescan per
    /// level. At exactly the limit (a chain of eight) every inline call is
    /// gone; one level deeper the leftover call is legal residue -- regular
    /// inline bodies are emitted, so no diagnostic is raised.
    @Test(arguments: [(8, false), (9, true)])
    func testRegularInlineChainAtAndBeyondRescanLimit(
        depth: Int,
        leavesResidue: Bool
    ) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let leaf = makeFunction("leaf", symbol: 500, interner: interner, types: types)
        var decls: [KIRFunction] = []
        for i in 1 ... depth {
            let next = i == depth
                ? (leaf.symbol, "leaf")
                : (SymbolID(rawValue: Int32(i + 1)), "g\(i + 1)")
            decls.append(makeFunction(
                "g\(i)", symbol: Int32(i), interner: interner, types: types,
                body: [call(to: next.0, callee: next.1, interner: interner)],
                isInline: true
            ))
        }
        let main = makeFunction(
            "main", symbol: 1000, interner: interner, types: types,
            body: [call(to: SymbolID(rawValue: 1), callee: "g1", interner: interner)]
        )
        decls.append(main)
        decls.append(leaf)
        let module = makeModule(decls)
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        try InlineLoweringPass().run(module: module, ctx: ctx)

        // Non-mandatory residue must never become an error.
        #expect(!diagnostics.hasError)
        let mainDecl = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl, function.symbol == main.symbol else {
                return nil
            }
            return function
        }.first
        let targets = try #require(mainDecl).body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return nil
            }
            return interner.resolve(callee)
        }
        if leavesResidue {
            // Beyond the limit the call to the regular inline `g9` remains --
            // emitted normally, legal to leave behind.
            #expect(targets == ["g\(depth)"])
        } else {
            #expect(targets == ["leaf"])
        }
    }

    // MARK: - Residue scope

    /// A leftover call to a non-bodyless expansion target or to a function
    /// outside the index entirely is legal: it resolves to an emitted body
    /// at link time, so the residue scan must not flag it.
    @Test
    func testNonMandatoryLeftoverCallsAreNotDiagnosed() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let regular = SymbolID(rawValue: 1)
        let plain = SymbolID(rawValue: 2)
        // A regular inline function is an expansion target but its body is
        // emitted; a call that fails expansion is legal residue.
        let regularDecl = makeFunction(
            "regular", symbol: regular.rawValue, interner: interner, types: types,
            isInline: true,
            params: [KIRParameter(symbol: SymbolID(rawValue: 10), type: types.intType)]
        )
        let plainDecl = makeFunction("plain", symbol: plain.rawValue, interner: interner, types: types)
        let main = makeFunction(
            "main", symbol: 3, interner: interner, types: types,
            body: [
                call(to: regular, callee: "regular", interner: interner),
                call(to: plain, callee: "plain", interner: interner),
            ]
        )
        let module = makeModule([regularDecl, plainDecl, main])
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)

        try InlineLoweringPass().run(module: module, ctx: ctx)

        #expect(!diagnostics.hasError)
        let targets = callTargets(of: try #require(
            module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl, function.symbol == main.symbol else {
                    return nil
                }
                return function
            }.first
        ), interner: interner).map(\.callee)
        #expect(targets == ["regular", "plain"])
    }
}
#endif
