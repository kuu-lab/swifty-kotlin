#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceContextualInputTests {
    @Test(arguments: [false, true])
    func receiverAndKnownArgumentsSelectOverloads(stmtFirst: Bool) throws {
        let exprOverload = "private fun resolve(expr: Expr) {}"
        let stmtOverload = "private fun resolve(stmt: Stmt) {}"
        _ = try SemaFixture(surface: "receiver-specialized overloaded references").make(source: """
        class Expr
        class Stmt
        class Branch(val elseBranch: Stmt?)
        class Variable(val initializer: Expr?)
        class Resolver {
            \(stmtFirst ? stmtOverload : exprOverload)
            \(stmtFirst ? exprOverload : stmtOverload)
            private fun resolve(stmts: List<Stmt>) {}
            fun run(expr: Expr?, stmt: Stmt?, stmts: List<Stmt>?) {
                expr?.let(::resolve)
                stmt?.let(::resolve)
                stmts?.let(::resolve)
                expr?.let { resolve(it) }
                stmt?.let { resolve(it) }
            }
            fun branch(stmt: Branch) { stmt.elseBranch?.let(::resolve) }
            fun variable(stmt: Variable) { stmt.initializer?.let(::resolve) }
        }
        fun describe(expr: Expr): String = "expr"
        fun describe(stmt: Stmt): String = "stmt"
        fun <T, R> consume(value: T, block: (T) -> R): R = block(value)
        fun <T, R> named(block: (T) -> R, value: T): R = block(value)
        fun check(stmt: Stmt?): String? = stmt?.let(::describe)
        fun checkArgument(): String = consume(Stmt(), ::describe)
        fun checkReordered(): String = consume(block = ::describe, value = Stmt())
        fun checkNamed(): String = named(block = ::describe, value = Stmt())
        fun unique(stmt: Stmt) {}
        fun <T> unknown(block: (T) -> Unit) {}
        fun checkUnique() { unknown(::unique) }
        """)
    }

    @Test func originalReturnTypeConstraintsRemainPreferred() throws {
        _ = try SemaFixture(surface: "rigid and structured reference outputs").make(source: """
        class Box<T>(val value: T) {
            fun select(x: Int): Int = x
            fun select(x: Any): T = value
            fun check(): (Int) -> T = ::select
            fun nestedSelect(x: Int): Int = x
            fun nestedSelect(x: Any): List<T> = listOf(value)
            fun nestedCheck(): (Int) -> List<T> = ::nestedSelect
        }
        """)
    }

    @Test func nullableReceiverWithoutSafeCallKeepsNullableInput() throws {
        _ = try SemaFixture(surface: "nullable direct let input").make(source: """
        class Expr
        class Stmt
        fun resolve(expr: Expr?): String = "expr"
        fun resolve(stmt: Stmt): String = "stmt"
        fun check(expr: Expr?): String = expr.let(::resolve)
        """)
    }

    @Test(arguments: [
        "fun check(value: Boolean?) { value?.let(::resolve) }",
        "fun check(value: Expr?) { value.let(::resolve) }",
        "fun check(value: Expr?) { value?.let(::wrongArity) }",
        "fun check() { unknown(::resolve) }",
    ])
    func incompatibleOrUnresolvedInputsAreRejected(use: String) throws {
        let ctx = makeContextFromSource("""
        class Expr
        class Stmt
        fun resolve(expr: Expr) {}
        fun resolve(stmt: Stmt) {}
        fun wrongArity(expr: Expr, stmt: Stmt) {}
        fun <T> unknown(block: (T) -> Unit) {}
        \(use)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Invalid reference must be rejected: \(use)")
    }

    @Test func reduceSelectsPrimitiveOperatorReferenceFromElementType() throws {
        let ctx = makeContextFromSource("""
        fun listProduct(values: List<Long>): Long = values.reduce(Long::times)
        fun iterableProduct(values: Iterable<Long>): Long = values.reduce(Long::times)
        fun listSum(values: List<Long>): Long = values.reduce(Long::plus)
        fun explicitIterableProduct(values: Iterable<Long>): Long = values.reduce<Long, Long>(Long::times)
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let operations = ast.arena.exprs.indices.compactMap { index -> BinaryOp? in
            let id = ExprID(rawValue: Int32(index))
            guard case .callableRef = ast.arena.expr(id) else { return nil }
            return sema.bindings.primitiveOperatorCallableRef(for: id)
        }
        #expect(operations == [.multiply, .multiply, .add, .multiply])
    }

    @Test func reduceRejectsPrimitiveOperatorReferenceForWrongElementType() throws {
        let ctx = makeContextFromSource("""
        fun invalid(values: List<Int>): Int = values.reduce(Long::times)
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "A Long operator must not satisfy an Int reducer.")
    }

    @Test func contextualPropertyReferenceIsRejected() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.ExperimentalContextParameters::class)

        class A(val tag: String) {
            context(c: String)
            val prop: String get() = tag + c
            val y by A::prop
        }

        class B(val tag: String) {
            val prop: String get() = tag
            val y by B::prop
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Expected one contextual property-reference diagnostic: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-TYPE-0001")
        #expect(errors.first?.message == "Callable references to properties with context parameters are not supported.")
    }

    // MARK: - KUU-3753: callable references vs context-parameter expected types

    /// An expected `context(A) () -> T` is `(A) -> T`: an unbound
    /// member/extension/property reference whose receiver is `A` must
    /// type-check, and the value must invoke as `f(receiver)` — kotlinc
    /// accepts every one of these.
    @Test func unboundReferencesMatchContextParameterExpectedType() throws {
        let ctx = makeContextFromSource("""
        class A { fun instance() = true; val p = true }
        fun A.ext() = true
        val A.extp: Boolean get() = true
        fun take(f: context(A) () -> Boolean) { }
        fun callContext(f: context(A) () -> Boolean, receiver: A) = f(receiver)
        fun main() {
            val a = A()
            take(A::instance)
            take(A::ext)
            take(A::p)
            take(A::extp)
            callContext(A::instance, a)
            callContext(A::ext, a)
            callContext(A::p, a)
            callContext(A::extp, a)
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Unbound references must satisfy a context-parameter expected type like kotlinc: \(errors)"
        )
    }

    /// A bound reference types as `() -> T`, so kotlinc rejects it for
    /// `context(A) () -> T` — the bound receiver is not re-bound as the
    /// context argument.
    @Test(arguments: [
        "take(a::instance)",
        "take(a::ext)",
        "take(a::p)",
        "take(a::extp)",
    ])
    func boundReferencesAreRejectedForContextParameterExpectedType(use: String) throws {
        let ctx = makeContextFromSource("""
        class A { fun instance() = true; val p = true }
        fun A.ext() = true
        val A.extp: Boolean get() = true
        fun take(f: context(A) () -> Boolean) { }
        fun main() {
            val a = A()
            \(use)
        }
        """)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.hasError,
            "`\(use)` must be rejected for a context-parameter expected type like kotlinc"
        )
    }

    /// kotlinc does not widen the reference receiver into a supertype context
    /// parameter: `A::instance` is `(A) -> Boolean`, which is inapplicable
    /// where `context(Any) () -> Boolean` is expected.
    @Test func unrelatedContextParameterTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        class A { fun instance() = true }
        fun takeAny(f: context(Any) () -> Boolean) { }
        fun main() {
            takeAny(A::instance)
        }
        """)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.hasError,
            "`A::instance` must not satisfy `context(Any) () -> Boolean` like kotlinc"
        )
    }

    /// `::topCtx` keeps its `context(A) () -> Boolean` type even inside
    /// `with(a)` — ambient receivers never force reference-site binding.
    /// It therefore satisfies `take(f: context(A) () -> Boolean)` directly
    /// (invocation supplies the context; verified end-to-end the ambient `a`
    /// is not captured). kotlinc rejects both uses because its context
    /// references always bind at the reference site; KSwiftK deliberately
    /// accepts the contextual spelling per KUU-3355/KUU-3770 semantics.
    /// `takePlain(f: (A) -> Boolean)` still rejects: `topCtx`'s `A` is a
    /// context parameter, not a value parameter, so no `(A) -> Boolean`
    /// adaptation exists.
    @Test func contextFunctionReferenceMatchesContextualButNotPlainSpelling() throws {
        let ctx = makeContextFromSource("""
        class A { fun instance() = true }
        context(a: A) fun topCtx() = true
        fun take(f: context(A) () -> Boolean) { }
        fun takePlain(f: (A) -> Boolean) { }
        fun main() {
            val a = A()
            with(a) {
                take(::topCtx)
                takePlain(::topCtx)
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Only the `(A) -> Boolean` use must be rejected: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-TYPE-0001")
    }

    // MARK: - KUU-3770: context-function references vs contextual expected types

    /// A callable reference to a context-parameter function keeps its
    /// `context(X) (...) -> R` type and satisfies a `context(X) (...) -> T`
    /// expected type directly — through a generic `T` return, a concrete
    /// return, and with value parameters following the context slots.
    /// (kotlinc 2.4.20 rejects these adaptations; KSwiftK accepts them per
    /// KUU-3355 semantics — regression coverage for the TYPE-0001 rejection
    /// that returned between 04d99b7c33 and 34adf47f8b.)
    @Test func contextFunctionReferencesMatchContextualExpectedType() throws {
        let ctx = makeContextFromSource("""
        context(c: String) fun ctxLen(): Int = c.length
        class Foo { val x = "OK" }
        context(f: Foo) fun readX(): String = f.x
        context(c: String) fun greet(name: String): String = "$c:$name"
        fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
        fun <T> withFoo(f: Foo, b: context(Foo) () -> T): T = with(f) { b() }
        fun directCtx(v: String, f: context(String) () -> Int): Int = with(v) { f() }
        fun applyCtx(v: String, f: context(String) (String) -> String): String = with(v) { f("N") }
        fun main() {
            println(withCtx("hi", ::ctxLen))
            println(withFoo(Foo(), ::readX))
            println(directCtx("hey", ::ctxLen))
            println(applyCtx("hi", ::greet))
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Context function references must satisfy contextual expected types: \(errors)"
        )
    }

    /// An anonymous context function with two same-typed context parameters
    /// type-checks against `context(S, S) () -> Unit` (KUU-3770 reproduction
    /// that regressed to "Type constraint could not be satisfied").
    @Test func sameTypedContextAnonymousFunctionMatchesContextualType() throws {
        let ctx = makeContextFromSource("""
        interface S { fun foo(c: Int) }
        fun main() {
            val f: context(S, S) () -> Unit = context(s1: S, s2: S) fun() { s1.foo(2); s2.foo(3) }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "A same-typed multi-context anonymous function must satisfy `context(S, S) () -> Unit`: \(errors)"
        )
    }
}
#endif
