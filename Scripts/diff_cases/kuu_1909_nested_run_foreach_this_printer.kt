interface Expr { fun <R> accept(v: Visitor<R>): R }
interface Visitor<R> { fun visit(e: Literal): R }
class Literal(val n: Int) : Expr { override fun <R> accept(v: Visitor<R>): R = v.visit(this) }

class Printer : Visitor<String> {
    override fun visit(e: Literal): String = e.n.toString()

    fun show(vararg exprs: Expr): String = StringBuilder().run {
        exprs.forEach { append(it.accept(this@Printer)) }
        toString()
    }

    fun showWithLocalPrinter(vararg exprs: Expr): String = StringBuilder().run {
        val printer = this@Printer
        exprs.forEach { append(it.accept(printer)) }
        toString()
    }
}

fun main() {
    val printer = Printer()
    val literal = Literal(3)
    println(literal.accept(printer))
    println(printer.showWithLocalPrinter(literal))
    println(printer.show(literal))
}
