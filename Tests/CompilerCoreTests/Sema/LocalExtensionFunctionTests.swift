#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LocalExtensionFunctionTests {
    private func localFunctionSymbol(
        named name: InternedString,
        in ast: ASTModule,
        sema: SemaModule
    ) -> SymbolID? {
        guard let index = ast.arena.exprs.indices.first(where: {
            guard case let .localFunDecl(localName, _, _, _, _, _, _, _, _) = ast.arena.exprs[$0] else {
                return false
            }
            return localName == name
        }) else { return nil }
        return sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
    }

    @Test
    func genericLocalFunctionAcceptsExplicitTypeArgumentsAndShadowsEnumIntrinsic() throws {
        let ctx = makeContextFromSource("""
        enum class Color { RED, GREEN, BLUE }
        fun main() {
            fun <T : Enum<T>> enumValueOf(name: String): String = "LOCAL:$name"
            println(enumValueOf<Color>("BLUE"))
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let symbol = try #require(localFunctionSymbol(
            named: ctx.interner.intern("enumValueOf"),
            in: ast,
            sema: sema
        ))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(!sema.symbols.typeParameterUpperBounds(for: signature.typeParameterSymbols[0]).isEmpty)

        let binding = try #require(sema.bindings.callBindings.values.first {
            $0.chosenCallee == symbol
        })
        let colorSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Color")]))
        let colorType = sema.types.make(.classType(ClassType(
            classSymbol: colorSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(binding.substitutedTypeArguments == [colorType])
    }

    @Test
    func localFunctionParametersRequireExplicitTypes() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            fun foo(x) {
                fun bar(y) {
                    fun baz(z) {}
                }
            }
        }
        """)
        try runSema(ctx)

        let missingTypeDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0033"
        }
        #expect(missingTypeDiagnostics.count == 3, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func anonymousFunctionParametersCanUseTheExpectedFunctionType() throws {
        let ctx = makeContextFromSource("""
        fun probe(): (Int) -> Int {
            return fun(value) = value + 1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

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
        for (name, isSuspend) in [("helper", false), ("suspHelper", true), ("bufferHelper", true), ("helper2", false)] {
            let symbol = try #require(localFunctionSymbol(named: ctx.interner.intern(name), in: ast, sema: sema))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.receiverType != nil)
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == symbol })
            let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == symbol })
            #expect(function.params.contains {
                $0.symbol == SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            })
            #expect(signature.isSuspend == isSuspend)
            #expect(function.isSuspend == signature.isSuspend)
        }
        let readSymbol = try #require(localFunctionSymbol(named: ctx.interner.intern("read"), in: ast, sema: sema))
        let read = try #require(findAllKIRFunctions(in: module).first { $0.symbol == readSymbol })
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
        let ast = try #require(ctx.ast)
        let functions = findAllKIRFunctions(in: module)
        let independentSymbol = try #require(localFunctionSymbol(named: ctx.interner.intern("independent"), in: ast, sema: sema))
        let independent = try #require(functions.first { $0.symbol == independentSymbol })
        let signature = try #require(sema.symbols.functionSignature(for: independent.symbol))
        #expect(independent.params.map(\.symbol) == signature.valueParameterSymbols)
        let readSymbol = try #require(localFunctionSymbol(named: ctx.interner.intern("read"), in: ast, sema: sema))
        let read = try #require(functions.first { $0.symbol == readSymbol })
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
        guard case let .localFunDecl(name, receiver, params, _, _, _, _, _, _) = ast.arena.exprs[localID] else {
            Issue.record("Expected local function")
            return
        }
        #expect(name == ctx.interner.intern("twice"))
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
    func localNullablePrimitiveOperatorWinsInsideImplicitLambda() throws {
        try withTemporaryFile(contents: """
        infix operator fun Int?.plus(a: Int): Int = -100
        fun foo(f: (Int?) -> Int): Int = f(0)
        fun box(): Int {
            infix operator fun Int?.plus(a: Int): Int = a!! + 2
            if (foo { it + 1 } != 3) return -1
            if (foo { it plus 1 } != 3) return -2
            return 0
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let localPlus = try #require(localFunctionSymbol(
                named: ctx.interner.intern("plus"),
                in: ast,
                sema: sema
            ))
            let localPlusCalls = sema.bindings.callBindings.values.filter { $0.chosenCallee == localPlus }
            #expect(localPlusCalls.count == 2, "Both operator and infix syntax should bind the local plus: \(localPlusCalls)")
        }
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
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let names = KnownCompilerNames(interner: ctx.interner)
        let symbol = try #require(localFunctionSymbol(named: names.add, in: ast, sema: sema))
        let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == symbol })
        #expect(function.params.count == 3)
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
        let choice = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Choice")]))
        let member = try #require(sema.symbols.lookup(fqName: ["Choice", "select"].map(ctx.interner.intern)))
        #expect(sema.symbols.parentSymbol(for: member) == choice)
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == member })
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
    func localExtensionOnClassReceiverInvokesThroughLexicalCallee() throws {
        let ctx = makeContextFromSource("""
        class OuterDelegate
        fun ordinaryLocalCall() {
            fun OuterDelegate.read(): Int = 4
            println(OuterDelegate().read())
            OuterDelegate().read()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let symbol = try #require(localFunctionSymbol(
            named: ctx.interner.intern("read"),
            in: ast,
            sema: sema
        ))
        #expect(sema.bindings.callableTargets.values.contains { $0 == .symbol(symbol) })
    }

    @Test
    func localExtensionInvocationPreservesBareNameRejection() throws {
        let ctx = makeContextFromSource("""
        class OuterDelegate
        fun probe() {
            fun OuterDelegate.read(): Int = 4
            val reference = OuterDelegate().read
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0309" })
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

    @Test(arguments: [
        ("unaryPlus", """
        fun box(): String {
            val sb = StringBuilder()
            operator fun String.unaryPlus() { sb.append(this) }
            +"OK"
            return sb.toString()!!
        }
        fun main() { println(box()) }
        """),
        ("unaryMinus", """
        fun box(): String {
            val sb = StringBuilder()
            operator fun String.unaryMinus() { sb.append(this) }
            -"OK"
            return sb.toString()!!
        }
        fun main() { println(box()) }
        """),
    ])
    func statementPrefixUnaryAfterLocalFunctionDispatchesToLocalOperator(
        operatorName: String,
        source: String
    ) throws {
        // A `+x`/`-x` statement on the line after a block-bodied local
        // function is a new statement, not a continuation of the function
        // body (`f() { } + x` continues only on the same line). The parser used
        // to swallow the newline `+x`/`-x` into the preceding declaration, so
        // no unary expression was built and the local `operator fun` never ran.
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localSymbol = try #require(localFunctionSymbol(
            named: ctx.interner.intern(operatorName),
            in: ast,
            sema: sema
        ))
        let boundToLocal = sema.bindings.callBindings.contains { exprID, binding in
            guard binding.chosenCallee == localSymbol,
                  case .unaryExpr = ast.arena.expr(exprID)
            else {
                return false
            }
            return true
        }
        #expect(boundToLocal, "The prefix-unary statement must bind to the local \(operatorName) operator")
    }
}
#endif
