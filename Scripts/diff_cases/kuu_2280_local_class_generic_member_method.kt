fun box(): String {
    class Local {
        fun <S : CharSequence> echo(value: S): S {
            val copy: S = value
            return copy
        }
    }
    val local = Local()
    val inferred: String = local.echo("OK")
    return local.echo<String>(inferred)
}

fun main() {
    println(box())
}
