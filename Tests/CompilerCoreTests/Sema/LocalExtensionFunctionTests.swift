#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LocalExtensionFunctionTests {
    @Test
    func receiverSurvivesParsingAndBindsThis() throws {
        let ctx = makeContextFromSource("""
        fun probe(): Int {
            fun Int.twice(): Int = this * 2
            return 3.twice()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localID = try #require(ast.arena.exprs.indices.first {
            if case .localFunDecl = ast.arena.exprs[$0] { return true }
            return false
        })
        guard case let .localFunDecl(name, receiver, params, _, _, _, _) = ast.arena.exprs[localID] else {
            Issue.record("Expected local function")
            return
        }
        #expect(ctx.interner.resolve(name) == "twice")
        #expect(receiver != nil)
        #expect(params.isEmpty)
        let symbol = try #require(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(localID))))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.receiverType == sema.types.intType)
        #expect(signature.parameterTypes.isEmpty)
        let thisID = try #require(ast.arena.exprs.indices.first {
            if case .thisRef = ast.arena.exprs[$0] { return true }
            return false
        })
        #expect(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(thisID))) ==
            SyntheticSymbolScheme.receiverParameterSymbol(for: symbol))
    }

    @Test(arguments: [
        """
        fun probe(): String {
            fun String.decorate(): String { return this + "!" }
            return "ok".decorate()
        }
        """,
        """
        fun probe(n: Int?): Int {
            fun Int?.orZero(): Int = this ?: 0
            return n.orZero()
        }
        """,
        """
        fun Int.probe(): Int {
            val bonus = 10
            fun Int.combine(extra: Int = 1): Int = this + this@probe + bonus + extra
            return 3.combine()
        }
        """,
        """
        fun probe(): Int {
            fun Int.nested(): Int {
                fun read(): Int = this
                return read()
            }
            return 3.nested()
        }
        """,
        """
        fun probe(): Int {
            fun Int.nested(): Int = with("abc") { this.length + this@nested }
            return 3.nested()
        }
        """,
    ])
    func acceptsLocalExtensionReceivers(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func liftedCallPassesCaptureBeforeReceiverAndValueParameters() throws {
        let ctx = makeContextFromSource("""
        fun probe(base: Int): Int {
            fun Int.add(extra: Int): Int = base + this + extra
            return 3.add(4)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let function = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "add"
        })
        #expect(function.params.count == 3)
        let sema = try #require(ctx.sema)
        #expect(function.params[1].symbol == SyntheticSymbolScheme.receiverParameterSymbol(for: function.symbol))
        #expect(function.params[2].symbol == sema.symbols.functionSignature(for: function.symbol)?.valueParameterSymbols.first)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let arguments = try #require(body.compactMap { instruction -> [KIRExprID]? in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
               symbol == function.symbol { return arguments }
            return nil
        }.first)
        #expect(arguments.count == 3)
    }

    @Test
    func ordinaryLocalFunctionStillRejectsThisOutsideReceiverScope() throws {
        let ctx = makeContextFromSource("fun probe() { fun invalid(): Int = this }")
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0051" })
    }

    @Test
    func bareLocalExtensionReferenceIsRejectedWithoutThisDiagnostic() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            fun Int.twice(): Int = this * 2
            val reference = ::twice
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0051" })
    }
}
#endif
