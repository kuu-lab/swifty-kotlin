@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExtensionCallablePropertyTests {
    @Test
    func interfaceMemberExtensionPropertyResolvesFromImplicitDispatchReceiver() throws {
        let ctx = makeContextFromSource("""
        interface I { val Int.x: String }
        class C : I { override val Int.x: String get() = "OK" }
        fun box(): String = with(C()) { 1.x }
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let errorCodes = ctx.diagnostics.diagnostics.map(\.code)
        guard errorCodes.isEmpty else {
            Issue.record("Unexpected Sema diagnostics: \(errorCodes)")
            return
        }

        guard let getterCall = sema.bindings.extensionPropertyGetterCalls.values.first(where: { call in
            guard let property = sema.symbols.parentSymbol(for: call.chosenCallee) else { return false }
            return sema.symbols.symbol(property)?.name == ctx.interner.intern("x")
        }) else {
            Issue.record("Expected an extension property getter call binding for x")
            return
        }
        guard let dispatchOwner = sema.symbols.memberExtensionOwnerSymbol(for: getterCall.chosenCallee) else {
            Issue.record("Expected the chosen getter to be a member extension")
            return
        }
        let ownerName = try #require(sema.symbols.symbol(dispatchOwner)?.name)
        #expect(ctx.interner.resolve(ownerName) == "C")
    }

    @Test
    func implicitMemberExtensionPropertyKeepsVisibilityChecks() throws {
        let inside = makeContextFromSource("""
        class C {
            private val Int.secret: String get() = "OK"
            fun read(): String = with(this) { 1.secret }
        }
        """)
        try runToKIR(inside)
        let insideErrorCodes = inside.diagnostics.diagnostics.map(\.code)
        guard insideErrorCodes.isEmpty else {
            Issue.record("Private access from the declaring class emitted diagnostics: \(insideErrorCodes)")
            return
        }

        let outside = makeContextFromSource("""
        class C { private val Int.secret: String get() = "OK" }
        fun read(): String = with(C()) { 1.secret }
        """)
        try runSema(outside)
        let outsideErrorCodes = outside.diagnostics.diagnostics.map(\.code)
        #expect(outsideErrorCodes.contains("KSWIFTK-SEMA-0040"), "Expected an inaccessible member-property diagnostic, got \(outsideErrorCodes)")
    }

    /// KUU-3776: an explicitly imported member extension property stays a
    /// `recv.name` candidate even when an unrelated member of the enclosing
    /// class shares its name — the member shadows only unqualified access.
    @Test
    func importedMemberExtensionPropertySurvivesSameNamedClassMember() throws {
        let ctx = makeContextFromSource("""
        import Box.Companion.foo
        class Box { companion object { val Long.foo: String get() = "ext" } }
        class T(val foo: Int) {
            fun bar(x: Long) = x.foo
            fun baz() = foo
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let getterCall = try #require(sema.bindings.extensionPropertyGetterCalls.values.first(where: { call in
            guard let property = sema.symbols.parentSymbol(for: call.chosenCallee) else { return false }
            return sema.symbols.symbol(property)?.name == ctx.interner.intern("foo")
        }), "Expected an extension property getter call binding for foo")
        let dispatchOwner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: getterCall.chosenCallee))
        let ownerName = try #require(sema.symbols.symbol(dispatchOwner)?.name)
        #expect(ctx.interner.resolve(ownerName) == "Companion")
    }

    @Test
    func memberPropertiesKeepDispatchAndExtensionReceiversSeparate() throws {
        let ctx = makeContextFromSource("""
        class D(private val convertTo: Int.() -> String, private val convert: String.() -> Int) {
            fun f(i: Int): String = i.convertTo()
            fun g(s: String): Int = s.convert()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let bindings = sema.bindings.callableValueCalls.compactMap { exprID, binding in
            isUserSourceExpr(exprID, in: ctx) && binding.extensionCallableExpr != nil ? binding : nil
        }
        #expect(bindings.count == 2)
        for binding in bindings {
            let calleeExpr = try #require(binding.extensionCallableExpr)
            guard case .nameRef = ast.arena.expr(calleeExpr) else {
                Issue.record("Expected a lexical property read, not a read on Int/String")
                continue
            }
            let symbol = try #require(sema.bindings.identifierSymbol(for: calleeExpr))
            #expect(sema.symbols.symbol(symbol)?.kind == .property)
        }
        let module = try #require(ctx.kir)
        for name in ["f", "g"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains(runtimeABIName(.functionInvoke)))
            #expect(!callees.contains("convertTo"))
            #expect(!callees.contains("convert"))
        }
    }

    @Test
    func genericMemberPropertyInsideMapIsAccepted() throws {
        let ctx = makeContextFromSource("""
        class Converter<From, To>(private val convert: From.() -> To) {
            fun one(element: From): To = element.convert()
            fun all(elements: List<From>): List<To> = elements.map { it.convert() }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func stringLengthPropertyCannotBeInvoked() throws {
        let propertyRead = makeContextFromSource("""
        fun readLength(): Int = "x".length
        """)
        try runSema(propertyRead)
        #expect(!propertyRead.diagnostics.hasError, "Property access should remain valid: \(propertyRead.diagnostics.diagnostics)")

        let propertyCall = makeContextFromSource("""
        fun callLength(): Int = "x".length()
        """)
        try runSema(propertyCall)
        #expect(propertyCall.diagnostics.hasError, "A non-callable Int property must not be accepted as a function call")
    }

    @Test
    func moreSpecificExtensionPropertyReceiverWinsBeforeInvokeResolution() throws {
        let ctx = makeContextFromSource("""
        open class A { fun invoke(f: A.() -> Unit) = 1 }
        class B { operator fun invoke(f: B.() -> Unit) = 2 }
        open class C
        val C.attr: A get() = A()
        open class D : C()
        val D.attr: B get() = B()
        fun use(): Int = D().attr {}
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "The D.attr overload should be selected: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let getterCall = try #require(sema.bindings.extensionPropertyGetterCalls.values.first { call in
            guard let property = sema.symbols.parentSymbol(for: call.chosenCallee) else { return false }
            return sema.symbols.symbol(property)?.name == ctx.interner.intern("attr")
        })
        let property = try #require(sema.symbols.parentSymbol(for: getterCall.chosenCallee))
        let receiverType = try #require(sema.symbols.extensionPropertyReceiverType(for: property))
        guard case let .classType(receiver) = sema.types.kind(of: receiverType) else {
            Issue.record("Expected D.attr's extension receiver to be nominal")
            return
        }
        let receiverName = try #require(sema.symbols.symbol(receiver.classSymbol)?.name)
        #expect(ctx.interner.resolve(receiverName) == "D")
    }

    @Test
    func memberExtensionWithSameNameAsGenericPropertyIsAccepted() throws {
        let ctx = makeContextFromSource("""
        class Converter<From, To>(private val convert: To.() -> From) {
            fun Collection<To>.convert(): List<From> = map { it.convert() }
            fun all(elements: Collection<To>): List<From> = elements.convert()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let memberExtensionCalls = sema.bindings.callBindings.filter { exprID, binding in
            isUserSourceExpr(exprID, in: ctx)
                && sema.symbols.symbol(binding.chosenCallee).map { ctx.interner.resolve($0.name) } == "convert"
        }
        #expect(memberExtensionCalls.count == 1)
    }

    @Test
    func genericMemberExtensionDoesNotConstrainItsReceiverToTheOwner() throws {
        let ctx = makeContextFromSource("""
        class Reader<T> {
            fun String.echo(value: T): T = value
            fun read(text: String, value: T): T = text.echo(value)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func receiverLambdaPropertyInitializerMaterializesCaptures() throws {
        let ctx = makeContextFromSource("""
        class Owner(private val offset: Int) {
            private val action: Int.(Int) -> Int = { n -> this + n + offset }
            fun use(i: Int): Int = i.action(3)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "Owner", in: module, interner: ctx.interner)
        #expect(extractCallees(from: body, interner: ctx.interner).contains(runtimeABIName(.functionCreate2)))
    }

    @Test(arguments: [
        ("Int", "2"),
        ("Owner<T>", "this"),
        ("Collection<T>", "listOf(value)")
    ])
    func genericMemberExtensionUsesExtensionReceiverConstraints(receiver: String, expression: String) throws {
        let ctx = makeContextFromSource("""
        class Owner<T>(private val value: T) {
            fun \(receiver).read(): T = value
            fun run(): T = \(expression).read()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func localParameterAndNullableReceiverFunctionValuesAreAccepted() throws {
        let ctx = makeContextFromSource("""
        fun local(i: Int, action: Int.(Int) -> Int): Int = i.action(2)
        fun localTwoParams(i: Int, action: Int.(Int, Int) -> Int): Int = i.action(2, 3)
        fun nullable(s: String?, action: String?.() -> Int): Int = s.action()
        fun safe(s: String?, action: String.() -> Int): Int? = s?.action()
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test
    func bareReceiverFunctionCallsUseImplicitReceiverScope() throws {
        let ctx = makeContextFromSource("""
        fun scoped(action: Int.(Int) -> Int): Int = with(1) { action(2) }
        fun nested(action: Int.(Int) -> Int): Int = with(1) { with("s") { action(2) } }
        fun Int.extensionReceiver(action: Int.(Int) -> Int): Int = action(1)
        class Owner {
            fun memberThis(action: Owner.(Int) -> Int): Int = action(1)
            fun Int.memberExtension(action: Owner.(Int) -> Int): Int = action(1)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun bad(action: Int.() -> Int): Int = \"x\".action()",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action()",
        "fun bad(action: Int.(Int, Int) -> Int): Int = 1.action(2)",
        "fun bad(action: Int.() -> Int): Int = 1.action(2)",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action(\"x\")",
        "fun bad(action: (Int.() -> Int)?): Int = 1.action()",
        "fun bad(s: String?, action: String.() -> Int): Int = s.action()",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action(value = 2)",
        "fun bad(action: Int.() -> Int): Int = 1.action<Int>()",
        // A bare `f(...)` call must draw the receiver from an implicit
        // receiver scope; without one it is an arity error like kotlinc's
        // "no value passed for parameter" (KUU-3878).
        "fun bad(action: Int.(Int) -> Int): Int = action(1)",
        "fun bad(action: Int.(Int) -> Int): Int = with(\"x\") { action(2) }",
        "fun bad(f: Int.(Int) -> Int): Int = f.invoke(4)",
        "context(i: Int) fun bad(action: Int.(Int) -> Int): Int = action(1)"
    ])
    func invalidReceiverFunctionValueCallsAreRejected(_ source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Invalid receiver-function invocation was accepted: \(source)")
    }
}
