#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringPassRegressionTests {
    // KUU-1431: lambdas inlined into the enclosing instruction stream (the
    // array-constructor init lambda, `repeat`'s action) never register their
    // parameter in `lambdaParamNameToSymbol`, so a nested implicit `it` used
    // to resolve through the enclosing lambda's same-named registration and
    // read the outer parameter instead of the index Sema bound it to.

    /// The generated lambda that `main`'s `forEach` call receives — the
    //  enclosing lambda — resolved through the call's `symbolRef` argument
    //  rather than name matching (the module also carries every
    //  bundled-stdlib `kk_lambda_*` body).
    private func forEachLambda(
        in module: KIRModule,
        interner: StringInterner
    ) throws -> KIRFunction {
        let main = try findKIRFunction(named: "main", in: module, interner: interner)
        let lambdaSymbol = try #require(main.body.lazy.compactMap { instruction -> SymbolID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == interner.intern("forEach"),
                  let lambdaExpr = arguments.last,
                  case let .symbolRef(symbol) = module.arena.expr(lambdaExpr)
            else { return nil }
            return symbol
        }.first)
        return try #require(findAllKIRFunctions(in: module).first { $0.symbol == lambdaSymbol })
    }

    /// Every KIRExprID the enclosing lambda materializes for its last
    /// (value) param — capture propagation can emit the `symbolRef` more
    /// than once, and reads may use any of them.
    private func enclosingLambdaParamExprs(
        in function: KIRFunction
    ) throws -> Set<KIRExprID> {
        let valueParam = try #require(function.params.last)
        var exprs = Set(function.body.compactMap { instruction -> KIRExprID? in
            guard case let .constValue(result, value) = instruction,
                  case let .symbolRef(symbol) = value,
                  symbol == valueParam.symbol
            else { return nil }
            return result
        })
        // Reads may consume a `copy` of the parameter register — follow the
        // copy chain so the set covers every register carrying `it`.
        var grew = true
        while grew {
            grew = false
            for case let .copy(from, to) in function.body where exprs.contains(from) && !exprs.contains(to) {
                exprs.insert(to)
                grew = true
            }
        }
        return try #require(exprs.isEmpty ? nil : exprs)
    }

    /// Every expr an instruction consumes — a read of the outer `it` can
    /// surface as a call/virtualCall argument, a primitive `binary` operand
    /// (unboxed `Int` arithmetic does not go through `kk_op_*` calls in this
    /// pipeline), a branch condition, or a stored/returned value.
    private func readExprIDs(in function: KIRFunction) -> [KIRExprID] {
        function.body.flatMap { instruction -> [KIRExprID] in
            switch instruction {
            case let .jumpIfEqual(lhs, rhs, _):
                return [lhs, rhs]
            case let .binary(_, lhs, rhs, _):
                return [lhs, rhs]
            case let .unary(_, operand, _):
                return [operand]
            case let .nullAssert(operand, _):
                return [operand]
            case let .call(_, _, arguments, _, _, _, _, _):
                return arguments
            case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
                return [receiver] + arguments
            case let .jumpIfNotNull(value, _):
                return [value]
            case let .storeGlobal(value, _):
                return [value]
            case let .rethrow(value):
                return [value]
            case let .returnIfEqual(lhs, rhs):
                return [lhs, rhs]
            case let .returnValue(value):
                return [value]
            case let .nonLocalReturn(value, _):
                return value.map { [$0] } ?? []
            case let .beginNonLocalReturnScope(value, _, _):
                return [value]
            case let .resumeNonLocalReturn(value):
                return [value]
            case .beginBlock, .endBlock, .label, .jump, .constValue, .copy,
                 .loadGlobal, .returnUnit, .endNonLocalReturnScope, .nop,
                 .beginFinallyCleanup, .endFinallyCleanup,
                 .beginFinallyGuard, .endFinallyGuard:
                return []
            }
        }
    }

    @Test
    func nestedImplicitItInsideInlinedArrayInitReadsInnerIndex() throws {
        // Printed [7, 7, 7, 7] instead of [0, 7, 14, 21] before the fix: the
        // init lambda's `it` read the forEach element (1) four times.
        let source = """
        fun main() {
            listOf(1).forEach {
                println(ByteArray(4) { (it * 7).toByte() }.toList())
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let lambda = try forEachLambda(in: module, interner: ctx.interner)
            // kk_array_new_checked + kk_array_set mark the inlined init loop.
            let callees = Set(extractCallees(from: lambda.body, interner: ctx.interner))
            #expect(callees.isSuperset(of: [RuntimeCall.arrayNewChecked.name, RuntimeCall.arraySet.name]))
            let outerParamExprs = try enclosingLambdaParamExprs(in: lambda)
            // The outer `it` is never used by this program, so no instruction
            // in the lambda body may read the parameter's register; the
            // inlined init body must read the loop index instead.
            #expect(readExprIDs(in: lambda).allSatisfy { !outerParamExprs.contains($0) })
        }
    }

    @Test
    func nestedImplicitItInsideInlinedRepeatReadsInnerIndex() throws {
        // `repeat`'s action lambda is inlined the same way; `println(it)` must
        // print the iteration index, not the enclosing forEach element.
        let source = """
        fun main() {
            listOf("x").forEach {
                repeat(3) { println(it) }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let lambda = try forEachLambda(in: module, interner: ctx.interner)
            #expect(extractCallees(from: lambda.body, interner: ctx.interner).contains("println"))
            let outerParamExprs = try enclosingLambdaParamExprs(in: lambda)
            #expect(readExprIDs(in: lambda).allSatisfy { !outerParamExprs.contains($0) })
        }
    }

    @Test
    func explicitInnerParamKeepsOuterImplicitItReachable() throws {
        // When the inner lambda declares its own parameter, a bare `it`
        // inside still means the OUTER lambda's implicit parameter — the
        // fix must not sever that legitimate binding.
        let source = """
        fun main() {
            listOf(5).forEach {
                println(IntArray(3) { idx -> idx + it }.toList())
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let lambda = try forEachLambda(in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: lambda.body, interner: ctx.interner))
            #expect(callees.isSuperset(of: [RuntimeCall.arrayNewChecked.name, RuntimeCall.arraySet.name]))
            let outerParamExprs = try enclosingLambdaParamExprs(in: lambda)
            #expect(readExprIDs(in: lambda).contains { outerParamExprs.contains($0) })
        }
    }
}
#endif
