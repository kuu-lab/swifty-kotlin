#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ParenthesizedReceiverSamTests {
    @Test(arguments: [
        ("(Int.() -> String)", true, 0, false),
        ("(() -> String)", false, 0, false),
        ("((Int) -> String)?", false, 1, true),
    ])
    func functionTypedReceiverIsAnAbstractMember(
        receiver: String, hasInnerReceiver: Bool, parameterCount: Int, nullable: Bool
    ) throws {
        let source = "fun interface S { fun \(receiver).accept(): String }"
        let (ast, astContext) = try buildASTModule(from: source, includeStdlib: false)
        let interface = try #require(firstInterfaceDecl(named: "S", in: ast, interner: astContext.interner))
        #expect(interface.memberFunctions.count == 1)
        let function = try #require(firstFunDecl(named: "accept", in: ast, interner: astContext.interner))
        let receiverType = try #require(function.receiverType)
        guard case let .functionType(_, innerReceiver, params, result, isSuspend, isNullable) = ast.arena.typeRef(receiverType) else {
            Issue.record("Expected a function-typed extension receiver")
            return
        }
        #expect((innerReceiver != nil) == hasInnerReceiver)
        #expect(params.count == parameterCount)
        #expect(!isSuspend)
        #expect(isNullable == nullable)
        if case let .named(path, _, _) = ast.arena.typeRef(result) {
            #expect(path.map(astContext.interner.resolve) == ["String"])
        } else {
            Issue.record("Expected String as the receiver function's return type")
        }
        #expect(function.valueParams.isEmpty)
        #expect(function.body == .unit)

        let context = makeBoundIdentityContext(source)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let method = try #require(sema.symbols.lookup(fqName: [context.interner.intern("S"), context.interner.intern("accept")]))
        #expect(sema.symbols.symbol(method)?.flags.contains(.abstractType) == true)
        #expect(sema.symbols.memberExtensionOwnerSymbol(for: method) != nil)
        #expect(sema.symbols.functionSignature(for: method)?.receiverType != nil)
    }

    @Test
    func namedAndAnonymousFunctionReceiversStayDistinctInBlocks() {
        let parsed = parse("""
        class Owner {
            fun (Int.() -> String).member(): String = this(1)
            fun <T> ((T) -> String).generic(value: T): String = this(value)
        }
        fun host() {
            val previous = 1
            fun (Int.() -> String).local(): String = this(1)
            val plain = { fun (): Int = 1 }
            val extension = { fun (() -> String).(): String = this() }
        }
        fun after() = 1
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty, "\(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 5)
    }

    @Test
    func twoAbstractMembersStillFailSamValidation() throws {
        let context = makeBoundIdentityContext("""
        fun interface S {
            fun (Int.() -> String).accept(): String
            fun other(): String
        }
        """)
        try runSema(context)
        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0406" })
    }

    @Test
    func samConstructorAndExtensionCallResolve() throws {
        let context = makeContextFromSource("""
        fun interface S { fun (Int.() -> String).accept(): String }
        fun makeS(): S = S { this(42) }
        fun callS(s: S): String {
            val receiver: Int.() -> String = { toString() }
            return with(s) { receiver.accept() }
        }
        """, allowDefaultStdlibLibrary: false)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
#endif
