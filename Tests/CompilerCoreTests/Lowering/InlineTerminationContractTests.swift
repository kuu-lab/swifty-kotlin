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

    @Test(arguments: [false, true])
    func testSnapshotPreparationPreservesNestedNonLocalReturn(returnsValue: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let blockSymbol = SymbolID(rawValue: 10)
        let blockRef = module.arena.appendExpr(.symbolRef(blockSymbol), type: types.anyType)
        let innerRef = module.arena.appendExpr(.symbolRef(SymbolID(rawValue: 3)), type: types.anyType)
        let outerRef = module.arena.appendExpr(.symbolRef(SymbolID(rawValue: 4)), type: types.anyType)
        let value = module.arena.appendExpr(.intLiteral(42), type: types.intType)
        let invoke = makeFunction(
            "invoke", symbol: 1, interner: interner, types: types,
            body: [.constValue(result: blockRef, value: .symbolRef(blockSymbol)),
                   call(to: nil, callee: "kk_function_invoke_0", interner: interner, arguments: [blockRef]), .returnUnit],
            isInline: true, params: [KIRParameter(symbol: blockSymbol, type: types.anyType)]
        )
        let mandatory = makeFunction(
            "mandatory", symbol: 2, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        )
        let inner = makeFunction(
            "inner", symbol: 3, interner: interner, types: types,
            body: [
                .constValue(result: value, value: .intLiteral(42)),
                call(to: mandatory.symbol, callee: "mandatory", interner: interner),
                .nonLocalReturn(returnsValue ? value : nil),
            ]
        )
        let outer = makeFunction(
            "outer", symbol: 4, interner: interner, types: types,
            body: [call(to: invoke.symbol, callee: "invoke", interner: interner, arguments: [innerRef]), .returnUnit]
        )
        let main = makeFunction(
            "main", symbol: 5, interner: interner, types: types,
            body: [call(to: invoke.symbol, callee: "invoke", interner: interner, arguments: [outerRef]),
                   call(to: nil, callee: "after", interner: interner), .returnUnit]
        )
        for function in [invoke, mandatory, inner, outer, main] {
            _ = module.arena.appendDecl(.function(function))
        }
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let pass = InlineLoweringPass()

        pass.expandNestedBodylessInlineCalls(index: index, module: module, ctx: ctx, unitType: nil)

        let prepared = try #require(index.allFunctionsBySymbol[outer.symbol])
        #expect(prepared.body.contains { if case .nonLocalReturn = $0 { return true }; return false })
        try pass.run(module: module, ctx: ctx)
        let lowered = try #require(module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl, function.symbol == main.symbol else { return nil }
            return function
        }.first)
        let afterOffset = try #require(lowered.body.firstIndex {
            guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
            return interner.resolve(callee) == "after"
        })
        #expect(lowered.body[..<afterOffset].contains {
            if returnsValue, case .returnValue = $0 { return true }
            if !returnsValue, case .returnUnit = $0 { return true }
            return false
        })
        #expect(!lowered.body.contains { if case .nonLocalReturn = $0 { return true }; return false })
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

    // MARK: - Progress-driven caller expansion

    /// Deep acyclic delegation is limited by work, not an arbitrary round count.
    @Test(arguments: [8, 9, 32, 128])
    func testRegularInlineChainBeyondFormerRescanLimit(depth: Int) throws {
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
        decls.append(makeFunction(
            "unusedBodyless", symbol: 600, interner: interner, types: types,
            isInline: true, isInlineOnly: true
        ))
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
        #expect(targets == ["leaf"])
        let firstBody = try #require(mainDecl).body
        let repeatedModule = makeModule(decls)
        let repeatedDiagnostics = DiagnosticEngine()
        try InlineLoweringPass().run(
            module: repeatedModule,
            ctx: makeContext(diagnostics: repeatedDiagnostics, interner: interner)
        )
        let repeatedMain = repeatedModule.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration, function.symbol == main.symbol else { return nil }
            return function
        }.first
        #expect(try #require(repeatedMain).body == firstBody)
        #expect(!repeatedDiagnostics.hasError)
    }

    // MARK: - Residue scope

    @Test
    func testCallerExpandsAlternatingInlineAndLambdaStages() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let depth = 24
        for stage in 1 ... depth {
            let lambdaSymbol = SymbolID(rawValue: Int32(100 + stage))
            let callable = module.arena.appendExpr(.symbolRef(lambdaSymbol))
            let wrapper = makeFunction(
                "stage\(stage)", symbol: Int32(stage), interner: interner, types: types,
                body: [call(to: nil, callee: "kk_function_invoke_0", interner: interner, arguments: [callable])],
                isInline: true
            )
            let lambda = makeFunction(
                "lambda\(stage)", symbol: lambdaSymbol.rawValue, interner: interner, types: types,
                body: stage == depth ? [.nop, .returnUnit] : [
                    call(to: SymbolID(rawValue: Int32(stage + 1)), callee: "stage\(stage + 1)", interner: interner),
                ]
            )
            _ = module.arena.appendDecl(.function(wrapper))
            _ = module.arena.appendDecl(.function(lambda))
        }
        let caller = makeFunction(
            "caller", symbol: 1000, interner: interner, types: types,
            body: [call(to: SymbolID(rawValue: 1), callee: "stage1", interner: interner)]
        )
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let diagnostics = DiagnosticEngine()
        let expanded = InlineLoweringPass().inlineTransform(
            function: caller, index: index, inlineFunctionsByName: index.inlineFunctionsByName,
            module: module, ctx: makeContext(diagnostics: diagnostics, interner: interner), unitType: types.unitType
        )
        #expect(!diagnostics.hasError)
        #expect(callTargets(of: expanded, interner: interner).isEmpty)
        #expect(expanded.body == [.nop])
    }

    @Test
    func testCallerCycleGuardIsPerExpansionPath() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let a = makeFunction("a", symbol: 1, interner: interner, types: types, body: [
            .nop, call(to: SymbolID(rawValue: 2), callee: "b", interner: interner),
        ], isInline: true)
        let b = makeFunction("b", symbol: 2, interner: interner, types: types, body: [
            call(to: a.symbol, callee: "a", interner: interner),
        ], isInline: true)
        let caller = makeFunction("caller", symbol: 3, interner: interner, types: types, body: [
            call(to: a.symbol, callee: "a", interner: interner),
            call(to: a.symbol, callee: "a", interner: interner),
        ])
        let module = makeModule([a, b, caller])
        let diagnostics = DiagnosticEngine()
        try InlineLoweringPass().run(module: module, ctx: makeContext(diagnostics: diagnostics, interner: interner))
        let expanded = try #require(module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl, function.symbol == caller.symbol else { return nil }
            return function
        }.first)
        #expect(!diagnostics.hasError)
        #expect(expanded.body.count == 4)
        #expect(callTargets(of: expanded, interner: interner).map(\.callee) == ["a", "a"])
    }

    @Test(arguments: [false, true])
    func testCallerSuppliedLambdaCanNestTheSameInlineFunction(imported: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let parameter = SymbolID(rawValue: 10)
        let parameterExpr = module.arena.appendExpr(.symbolRef(parameter), type: nil)
        let innerExpr = module.arena.appendExpr(.symbolRef(SymbolID(rawValue: 3)), type: nil)
        let outerExpr = module.arena.appendExpr(.symbolRef(SymbolID(rawValue: 2)), type: nil)
        let value = module.arena.appendExpr(.intLiteral(42), type: types.intType)
        let once = makeFunction("once", symbol: 1, interner: interner, types: types, body: [
            .constValue(result: parameterExpr, value: .symbolRef(parameter)),
            call(to: nil, callee: "kk_function_invoke_0", interner: interner, arguments: [parameterExpr]),
            .returnUnit,
        ], isInline: true, params: [KIRParameter(symbol: parameter, type: types.unitType)])
        let outer = makeFunction("outer", symbol: 2, interner: interner, types: types, body: [
            call(to: once.symbol, callee: "once", interner: interner, arguments: [innerExpr]), .returnUnit,
        ])
        let inner = makeFunction("inner", symbol: 3, interner: interner, types: types, body: [
            .constValue(result: value, value: .intLiteral(42)), .nonLocalReturn(value),
        ])
        for function in (imported ? [outer, inner] : [once, outer, inner]) {
            _ = module.arena.appendDecl(.function(function))
        }
        let caller = makeFunction("caller", symbol: 4, interner: interner, types: types, body: [
            call(to: once.symbol, callee: "once", interner: interner, arguments: [outerExpr]), .returnUnit,
        ])
        let index = InlineExpansionIndex(
            module: module,
            importedInlineFunctions: ImportedInlineFunctionStore(functions: imported ? [once.symbol: once] : [:])
        )
        let expanded = InlineLoweringPass().inlineTransform(
            function: caller, index: index, inlineFunctionsByName: index.inlineFunctionsByName,
            module: module, ctx: makeContext(diagnostics: DiagnosticEngine(), interner: interner), unitType: types.unitType
        )
        #expect(callTargets(of: expanded, interner: interner).isEmpty)
        #expect(expanded.body.contains { if case .returnValue = $0 { return true }; return false })
        #expect(!expanded.body.contains { if case .nonLocalReturn = $0 { return true }; return false })
    }

    @Test
    func testRecursiveLambdaInvocationStopsWithoutGrowingArena() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let symbol = SymbolID(rawValue: 1)
        let callable = module.arena.appendExpr(.symbolRef(symbol))
        let lambda = makeFunction("recursiveLambda", symbol: 1, interner: interner, types: types, body: [
            call(to: nil, callee: "kk_function_invoke_0", interner: interner, arguments: [callable]),
        ])
        _ = module.arena.appendDecl(.function(lambda))
        let caller = makeFunction("caller", symbol: 2, interner: interner, types: types, body: lambda.body)
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let diagnostics = DiagnosticEngine()
        let expanded = InlineLoweringPass().inlineTransform(
            function: caller, index: index, inlineFunctionsByName: index.inlineFunctionsByName,
            module: module, ctx: makeContext(diagnostics: diagnostics, interner: interner), unitType: types.unitType
        )
        #expect(expanded.body.count == 1)
        #expect(module.arena.expressions.count <= 3)
        #expect(!diagnostics.hasError)
    }

    @Test
    func testAncestryChecksConsumeTheWorkBudget() {
        let arena = KIRArena()
        var limits = InlineExpansionBudget.Limits()
        limits.work = 16
        let budget = InlineExpansionBudget(arena: arena, limits: limits)
        budget.ancestry = (0 ..< 17).map { SymbolID(rawValue: Int32($0)) }
        let function = makeFunction(
            "empty", symbol: 100, interner: StringInterner(), types: TypeSystem(), body: []
        )
        #expect(!budget.enter(function, arena: arena))
        #expect(budget.work <= limits.work)
    }

    @Test
    func testErasedArgumentBoxingIsAdmittedBeforeAllocating() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let diagnostics = DiagnosticEngine()
        let importedSymbol = symbols.define(
            kind: .function, name: interner.intern("importedHOF"), fqName: [interner.intern("importedHOF")],
            declSite: nil, visibility: .public, flags: [.inlineFunction, .importedLibrary]
        )
        let callbackType = types.make(.functionType(FunctionType(params: [], returnType: types.unitType)))
        let module = makeModule([])
        let arguments = (0 ..< 64).map { module.arena.appendExpr(.intLiteral(Int64($0)), type: types.intType) }
            + [module.arena.appendTemporary(type: callbackType)]
        let params = (0 ..< 64).map { KIRParameter(symbol: SymbolID(rawValue: Int32(100 + $0)), type: types.anyType) }
            + [KIRParameter(symbol: SymbolID(rawValue: 200), type: callbackType)]
        let target = KIRFunction(
            symbol: importedSymbol, name: interner.intern("importedHOF"), params: params,
            returnType: types.unitType, body: [.returnUnit], isSuspend: false, isInline: true
        )
        _ = module.arena.appendDecl(.function(target))
        let caller = makeFunction("caller", symbol: 300, interner: interner, types: types, body: [
            call(to: importedSymbol, callee: "importedHOF", interner: interner, arguments: arguments), .returnUnit,
        ])
        let sema = makeSemaModule(symbols: symbols, types: types, diagnostics: diagnostics).ctx
        let ctx = makeKIRContext(moduleName: "budget", interner: interner, sema: sema, diagnostics: diagnostics)
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        let initialExpressions = module.arena.expressions.count
        var limits = InlineExpansionBudget.Limits()
        limits.expressions = 0
        let expanded = InlineLoweringPass().inlineTransform(
            function: caller, index: index, inlineFunctionsByName: index.inlineFunctionsByName,
            module: module, ctx: ctx, unitType: types.unitType, expansionLimits: limits
        )
        #expect(expanded.body == caller.body)
        #expect(module.arena.expressions.count == initialExpressions)
    }

    @Test(arguments: ["work", "instructions", "expressions", "nesting"])
    func testCallerBudgetsLeaveDiagnosableMandatoryResidue(resource: String) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let module = makeModule([])
        let value = module.arena.appendTemporary(type: types.intType)
        let target = makeFunction("mandatory", symbol: 1, interner: interner, types: types, body: [
            .constValue(result: value, value: .intLiteral(42)),
            .constValue(result: value, value: .intLiteral(43)),
            .returnUnit,
        ], isInline: true, isInlineOnly: true)
        _ = module.arena.appendDecl(.function(target))
        let caller = makeFunction("caller", symbol: 2, interner: interner, types: types, body: [
            call(to: target.symbol, callee: "mandatory", interner: interner),
        ])
        let index = InlineExpansionIndex(module: module, importedInlineFunctions: ImportedInlineFunctionStore())
        var limits = InlineExpansionBudget.Limits()
        switch resource {
        case "work": limits.work = 1
        case "instructions": limits.instructions = 1
        case "nesting": limits.nesting = 0
        default: limits.expressions = 0
        }
        let diagnostics = DiagnosticEngine()
        let ctx = makeContext(diagnostics: diagnostics, interner: interner)
        let expanded = InlineLoweringPass().inlineTransform(
            function: caller, index: index, inlineFunctionsByName: index.inlineFunctionsByName,
            module: module, ctx: ctx, unitType: types.unitType, expansionLimits: limits
        )
        #expect(expanded.body == caller.body)
        #expect(module.arena.expressions.count <= 2)
        _ = module.arena.appendDecl(.function(expanded))
        InlineLoweringPass().diagnoseMandatoryInlineResidue(module: module, index: index, ctx: ctx)
        #expect(diagnostics.diagnostics.count == 1)
        #expect(diagnostics.diagnostics.first?.code == "KSWIFTK-INL-0001")
        #expect(diagnostics.diagnostics.first?.message.contains("reached its limit") == true)
    }

    @Test
    func testCallerWorkBudgetBoundsEmptyExpansionChain() {
        let module = makeModule([])
        let interner = StringInterner()
        let types = TypeSystem()
        let budget = InlineExpansionBudget(arena: module.arena, limits: .init(work: 2))
        let empty = makeFunction("empty", symbol: 1, interner: interner, types: types, body: [])
        #expect(budget.enter(empty, arena: module.arena))
        budget.leave()
        #expect(budget.enter(empty, arena: module.arena))
        budget.leave()
        #expect(!budget.enter(empty, arena: module.arena))
    }

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
