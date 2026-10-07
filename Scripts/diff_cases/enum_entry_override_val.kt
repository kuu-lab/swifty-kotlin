// Entry bodies can override properties; interface properties implemented by
// enum constructor properties dispatch through the interface type.
enum class Op {
    PLUS { override val sym = "+" },
    MINUS { override val sym = "-" };
    abstract val sym: String
}

interface HasCode { val code: Int }
enum class St(override val code: Int) : HasCode { OK(200), NF(404) }

fun main() {
    println(Op.PLUS.sym + Op.MINUS.sym)
    for (op in Op.entries) println(op.sym)
    val h: HasCode = St.NF
    println(h.code)
    val ok: HasCode = St.OK
    println(ok.code + h.code)
}
