fun main() {
    try {
        throw TypeCastException("bad type cast")
    } catch (e: TypeCastException) {
        println(e.message)
    }

    val t: Throwable = TypeCastException("cast")
    println(t is ClassCastException)
    println(t is TypeCastException)
    val c = t as ClassCastException
    println(c.message)
}
