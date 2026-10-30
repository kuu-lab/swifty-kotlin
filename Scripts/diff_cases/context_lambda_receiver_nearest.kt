// Regression: context receivers an anonymous `context(...) { }` lambda
// supplies must shadow the implicit receiver of an enclosing `with` and the
// enclosing class's `this` (KUU-3170, sameExtensionContextAndDispatchReceiver).
fun <A, R> context(context: A, block: context(A) () -> R): R = block(context)

class A(val a: String = "d ") {

    context(a: A)
    fun A.funMember(): String = a.a + this@A.a + this.a

    fun usage(): String {
        var temp = ""
        context(A("c ")) {
            @Suppress("RECEIVER_SHADOWED_BY_CONTEXT_PARAMETER")
            temp = A("e ").funMember()
        }
        return temp
    }
}

fun main() {
    // context receiver "c " -> a.a, dispatch receiver "d " -> this@A.a,
    // extension receiver "e " -> this.a
    println(A().usage())
}
