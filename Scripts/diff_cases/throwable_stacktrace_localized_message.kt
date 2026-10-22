fun main() {
    val t = Throwable("boom")
    println(t.stackTrace.size > 0)
    println(t.stackTrace.joinToString("\n").length > 0)
    println(Exception("x").localizedMessage)
    println(RuntimeException().localizedMessage)
    println(RuntimeException("y").fillInStackTrace() is RuntimeException)
    val e = IllegalStateException("z")
    println(e.fillInStackTrace() === e)
}
