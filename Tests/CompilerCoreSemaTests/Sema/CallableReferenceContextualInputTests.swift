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

    /// `::topCtx` on a context function binds the context argument at the
    /// reference site, producing `() -> Boolean`; kotlinc reports it
    /// inapplicable to both `context(A) () -> Boolean` and `(A) -> Boolean`.
    @Test func contextFunctionReferenceIsRejectedForBothFunctionSpellings() throws {
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
        #expect(errors.count == 2, "Both `::topCtx` uses must be rejected like kotlinc: \(errors)")
    }

    // MARK: - KUU-3805 / KT-90169: composite generic results fix vararg reference inputs

    /// `make(::countG)` where `make` returns `(T) -> Int` must resolve `T`
    /// from the expected result `(Array<String>) -> Int` before shaping the
    /// reference, so `::countG` keeps its packed vararg-array input instead of
    /// degrading to scalar vararg adaptation (which would print `1` for a
    /// two-element array where kotlinc prints `2`).
    @Test func compositeGenericResultKeepsPackedVarargReferenceInput() throws {
        let ctx = makeContextFromSource("""
        fun <T> make(f: (T) -> Int): (T) -> Int = f
        fun <E> countG(vararg xs: E): Int = xs.size
        fun main() {
            val g: (Array<String>) -> Int = make(::countG)
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The adapted reference must type-check: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(firstExprID(in: ast) { _, expr in
            if case let .callableRef(_, member, _) = expr {
                return ctx.interner.resolve(member) == "countG"
            }
            return false
        })
        let referenceType = try #require(sema.bindings.exprType(for: reference))
        guard case let .functionType(functionType) = sema.types.kind(of: referenceType) else {
            Issue.record("Expected ::countG to keep a function type.")
            return
        }
        #expect(functionType.params.count == 1)
        guard let parameter = functionType.params.first,
              case let .classType(arrayType) = sema.types.kind(of: sema.types.makeNonNullable(parameter))
        else {
            Issue.record("Expected the packed vararg input Array<String>, got \(functionType.params).")
            return
        }
        #expect(
            sema.symbols.symbol(arrayType.classSymbol)?.fqName
                == ["kotlin", "Array"].map(ctx.interner.intern)
        )
        let binding = try #require(sema.bindings.callableReferenceBinding(for: reference))
        #expect(!binding.isCallableReferenceAdapter)
    }
}
#endif
