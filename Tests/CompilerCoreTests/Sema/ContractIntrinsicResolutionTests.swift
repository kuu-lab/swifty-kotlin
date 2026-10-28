#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ContractIntrinsicResolutionTests {
    @Test
    func normalContractOverloadsUseTheirResolvedDeclarations() throws {
        let source = """
        package kuu2457

        open class Foo(open val x: Boolean)
        class Bar : Foo(false) { val y = "OK" }

        fun contract(value: Foo) = value
        fun contract(value: String) = value
        fun contract(value: String, suffix: Boolean) = value

        fun box(): String {
            val temp = if (true) contract(Bar()) else Bar()
            val oneArgumentResult: String = contract("OK")
            val twoArgumentResult: String = contract("OK", false)
            return (temp as Bar).y + if (oneArgumentResult == twoArgumentResult) "" else "FAIL"
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { $0.code + ": " + $0.message })")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let contractName = ctx.interner.intern("contract")
            let userContractSymbols = Set(sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kuu2457"), contractName,
            ]))
            let userContractCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      name == contractName,
                      let binding = sema.bindings.callBinding(for: exprID),
                      userContractSymbols.contains(binding.chosenCallee)
                else {
                    return nil
                }
                return exprID
            }
            #expect(userContractCalls.count == 3)
            #expect(userContractCalls.allSatisfy {
                sema.bindings.stdlibSpecialCallKind(for: $0) == nil
            })

        }
    }

    @Test
    func trueContractIntrinsicKeepsEffectAnalysisAndCompilerOnlyLowering() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        fun isText(value: Any?): Boolean {
            contract { returns(true) implies (value is String) }
            return value is String
        }

        fun probe(value: Any?) {
            if (isText(value)) println(value.length)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { $0.code + ": " + $0.message })")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let intrinsicCalls = sema.bindings.stdlibSpecialCallKinds.keys.filter { exprID in
                guard let range = ast.arena.exprRange(exprID) else { return false }
                return ctx.sourceManager.path(of: range.start.file) == path
                    && sema.bindings.stdlibSpecialCallKind(for: exprID) == .contract
            }
            let intrinsicCall = try #require(intrinsicCalls.first)
            let intrinsicCallee = try #require(sema.bindings.callBinding(for: intrinsicCall)?.chosenCallee)
            #expect(sema.symbols.symbol(intrinsicCallee)?.fqName.map(ctx.interner.resolve) == [
                "kotlin", "contracts", "contract",
            ])
        }
    }
}
#endif
