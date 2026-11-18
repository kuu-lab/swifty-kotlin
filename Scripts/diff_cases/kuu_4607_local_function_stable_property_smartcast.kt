class C {
    val p: String? = "ok"

    fun explicit(): String {
        if (p != null) {
            fun g(): String = p
            return g()
        }
        return "FAIL"
    }

    fun inferred(): String {
        if (p != null) {
            fun g() = p
            return g()
        }
        return "FAIL"
    }

    fun blockBody(): String {
        if (p != null) {
            fun g(): String { return p }
            return g()
        }
        return "FAIL"
    }
}

val top: String? = "top"

fun topLevel(): String {
    if (top != null) {
        fun g() = top
        return g()
    }
    return "FAIL"
}

fun main() {
    val c = C()
    println(c.explicit())
    println(c.inferred())
    println(c.blockBody())
    println(topLevel())
}
