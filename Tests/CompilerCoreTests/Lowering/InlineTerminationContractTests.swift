#if canImport(Testing)
@testable import CompilerCore
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

    // MARK: - Bodyless-snapshot round boundary (4 rounds)

    /// A bodyless delegation chain whose depth fits the bounded
    /// re-expansion converges: no pending callers remain.
    @Test
    func testBodylessChainWithinRoundLimitConverges() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let leaf = makeFunction("leaf", symbol: 100, interner: interner, types: types)
        var chain: [KIRFunction] = []
        for i in 1 ... 5 {
            let next = i == 5
                ? (leaf.symbol, "leaf")
                : (SymbolID(rawValue: Int32(i + 1)), String(format: "f%02d", i + 1))
            chain.append(makeFunction(
                String(format: "f%02d", i), symbol: Int32(i), interner: interner,
                types: types,
                body: [call(to: next.0, callee: next.1, interner: interner)],
                isInline: true, isInlineOnly: true
            ))
        }
        let module = makeModule(chain + [leaf])
        let index = InlineExpansionIndex(
            module: module, importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let ctx = makeContext(diagnostics: DiagnosticEngine(), interner: interner)

        InlineLoweringPass().expandNestedBodylessInlineCalls(
            index: index, module: module, ctx: ctx, unitType: nil
        )

        #expect(index.pendingBodylessCallers(interner: interner).isEmpty)
        #expect(!ctx.diagnostics.hasError)
    }

    /// A bodyless mutual-recursion pair can never satisfy the pending set:
    /// expanding one side lands on a self-call while the other keeps
    /// pointing back into the cycle, so the pending set stays occupied for
    /// all four rounds and residue remains in both snapshots.
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

        // Beyond the boundary: `odd`'s snapshot still calls into the cycle
        // through `even`, so it never leaves the pending set, while both
        // snapshots keep a bodyless call as residue.
        #expect(index.pendingBodylessCallers(interner: interner) == [odd])
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

    @Test(arguments: ["work", "instructions", "expressions"])
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
