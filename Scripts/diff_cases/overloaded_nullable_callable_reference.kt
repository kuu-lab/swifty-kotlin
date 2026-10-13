// KUU-2005: Preserve the exact nullable-receiver reproducer.
class Expr
class Stmt
class Resolver {
    private fun resolve(expr: Expr) { println("expr") }
    private fun resolve(stmt: Stmt) { println("stmt") }
    fun run(expr: Expr?, stmt: Stmt?) {
        expr?.let(::resolve)
        stmt?.let(::resolve)
    }
}
fun main() { Resolver().run(Expr(), Stmt()) }
