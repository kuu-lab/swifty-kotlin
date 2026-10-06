#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LocalExtensionFunctionTests {
    @Test
    func localInterfaceExtensionsResolveInRegularAndSuspendFunctions() throws {
        let ctx = makeContextFromSource("""
        interface Src {
            val size: Long
            val buffer: ByteArray
        }
        suspend fun outer(s: Src) {
            fun Src.helper(): Long = size
            suspend fun Src.suspHelper(): Boolean = size > 0
            suspend fun Src.bufferHelper(): Byte {
                fun read(): Byte = buffer[1]
                return read()
            }
            val x = s.helper()
            val y = s.suspHelper()
            val b = s.bufferHelper()
        }
        fun topLevel(s: Src) {
            fun Src.helper2(): Long = size
            val z = s.helper2()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        for name in ["helper", "suspHelper", "bufferHelper", "helper2"] {
            let localID = try #require(ast.arena.exprs.indices.first {
                if case let .localFunDecl(localName, _, _, _, _, _, _) = ast.arena.exprs[$0] {
                    return ctx.interner.resolve(localName) == name
                }
                return false
            })
            let symbol = try #require(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(localID))))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.receiverType != nil)
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == symbol })
            let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == symbol })
            #expect(function.params.contains {
                $0.symbol == SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            })
            #expect(signature.isSuspend == (name == "suspHelper" || name == "bufferHelper"))
            #expect(function.isSuspend == signature.isSuspend)
        }
        let read = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "read"
        })
        #expect(read.params.count == 1, "The nested function must capture the extension receiver")
    }

    @Test
    func nestedExtensionAndShadowedParameterDoNotCaptureOuterReceiver() throws {
        let ctx = makeContextFromSource("""
        interface Src { val size: Long }
        fun Src.outer(s: Src): Long {
            fun independent(s: Src): Long {
                fun Src.own(): Long = size
                return s.own()
            }
            return independent(s)
        }
        fun Src.shadowed(size: Long): Long {
            fun read(): Long = size
            return read()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let functions = findAllKIRFunctions(in: module)
        let independent = try #require(functions.first { ctx.interner.resolve($0.name) == "independent" })
        let signature = try #require(sema.symbols.functionSignature(for: independent.symbol))
        #expect(independent.params.map(\.symbol) == signature.valueParameterSymbols)
        let read = try #require(functions.first { ctx.interner.resolve($0.name) == "read" })
        #expect(read.params.count == 1)
        #expect(read.params.first?.type == sema.types.longType)
    }

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
    func localExtensionIsNotVisibleOutsideItsDeclarationScope() throws {
        let ctx = makeContextFromSource("""
        fun declare() {
            fun Int.localOnly(): Int = this
            println(2.localOnly())
        }
        fun probe(): Int = 3.localOnly()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0051" })
    }

    @Test
    func applicableMemberStillShadowsLocalExtension() throws {
        let ctx = makeContextFromSource("""
        class Choice { fun select(): Int = 30 }
        fun probe(): Int {
            fun Choice.select(): Int = 99
            return Choice().select()
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
        let local = try #require(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(localID))))
        #expect(!sema.bindings.callBindings.values.contains { $0.chosenCallee == local })
        #expect(sema.bindings.callBindings.values.contains {
            guard let parent = sema.symbols.parentSymbol(for: $0.chosenCallee),
                  let owner = sema.symbols.symbol(parent),
                  let function = sema.symbols.symbol($0.chosenCallee)
            else { return false }
            return ctx.interner.resolve(owner.name) == "Choice" && ctx.interner.resolve(function.name) == "select"
        })
    }

    @Test
    func localExtensionIsConsideredWhenMemberIsInapplicable() throws {
        let ctx = makeContextFromSource("""
        class Choice { fun select(text: String): Int = 40 }
        fun probe(): Int {
            fun Choice.select(n: Int): Int = n + 1
            return Choice().select(2)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localID = try #require(ast.arena.exprs.indices.first {
            if case .localFunDecl = ast.arena.exprs[$0] { return true }
            return false
        })
        let local = try #require(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(localID))))
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == local })
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
