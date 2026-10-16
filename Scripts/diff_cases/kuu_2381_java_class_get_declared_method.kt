class DeclaredMethodProbe {
    fun nothingReturning() = null

    fun choose(value: Int): String = value.toString()

    fun choose(value: String): Int = value.length
}

fun main() {
    val type = DeclaredMethodProbe::class.java
    val noArgumentMethod = type.getDeclaredMethod("nothingReturning")
    val intOverload = type.getDeclaredMethod("choose", Int::class.java)
    val stringOverload = type.getDeclaredMethod("choose", String::class.java)
    val assertionsEnabled = type.desiredAssertionStatus()

    if (noArgumentMethod.returnType.name == "java.lang.Void"
        && intOverload.returnType.name == "java.lang.String"
        && stringOverload.returnType.name == "int"
        && (assertionsEnabled || !assertionsEnabled)
    ) {
        println("OK")
    } else {
        println("FAIL")
    }
}
