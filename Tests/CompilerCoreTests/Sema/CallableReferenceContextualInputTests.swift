#if canImport(Testing)
@testable import CompilerCore
import Testing

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
}
#endif
