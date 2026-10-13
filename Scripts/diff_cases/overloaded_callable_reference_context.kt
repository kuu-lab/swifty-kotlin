// KUU-2005: Receiver and known arguments specialize reference inputs, not outputs.
class Expr
class Stmt
class Branch(val elseBranch: Stmt?)
class Variable(val initializer: Expr?)
class Resolver {
    // Reverse the reproducer's declaration order and include the original list overload.
    private fun resolve(stmt: Stmt) { println("stmt") }
    private fun resolve(stmts: List<Stmt>) { println("list:" + stmts.size) }
    private fun resolve(expr: Expr) { println("expr") }
    fun run(expr: Expr?, stmt: Stmt?, stmts: List<Stmt>?) {
        expr?.let(::resolve)
        stmt?.let(::resolve)
        stmts?.let(::resolve)
    }
    fun resolveBranch(stmt: Branch) { stmt.elseBranch?.let(::resolve) }
    fun resolveVariable(stmt: Variable) { stmt.initializer?.let(::resolve) }
}
fun describe(expr: Expr): String = "expr-result"
fun describe(stmt: Stmt): String = "stmt-result"
fun <T, R> consume(value: T, block: (T) -> R): R = block(value)
fun <T, R> consumeNamed(block: (T) -> R, value: T): R = block(value)
fun main() {
    val resolver = Resolver()
    resolver.run(Expr(), Stmt(), listOf(Stmt()))
    resolver.run(null, null, null)
    resolver.resolveBranch(Branch(Stmt()))
    resolver.resolveVariable(Variable(Expr()))
    resolver.resolveBranch(Branch(null))
    resolver.resolveVariable(Variable(null))
    val expr: Expr? = Expr()
    val stmt: Stmt? = Stmt()
    println(expr?.let(::describe))
    println(stmt?.let(::describe))
    println(consume(Stmt(), ::describe))
    println(consume(block = ::describe, value = Stmt()))
    println(consumeNamed(block = ::describe, value = Stmt()))
}
