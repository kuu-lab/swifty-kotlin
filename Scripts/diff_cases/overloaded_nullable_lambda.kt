// KUU-2005: Lambda control for the callable-reference reproducer.
class Expr
class Stmt
class Resolver {
    private fun resolve(expr: Expr) { println("expr") }
    private fun resolve(stmt: Stmt) { println("stmt") }
    fun run(expr: Expr?, stmt: Stmt?) {
        expr?.let { resolve(it) }
        stmt?.let { resolve(it) }
    }
}
fun main() { Resolver().run(Expr(), Stmt()) }
