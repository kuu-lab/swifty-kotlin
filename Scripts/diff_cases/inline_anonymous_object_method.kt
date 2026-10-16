inline fun foo(noinline a: Int.() -> Unit) {
    a
}

inline fun bar(crossinline a: Int.() -> Unit) {
    val s = object {
        fun run() {
            a(1)
        }
    }
    s.run()
}

inline fun baz(a: Int.() -> Unit) {
    a(1)
}

fun box(): String {
    foo { }
    bar { }
    baz {
        return "OK"
    }
    return "FAIL"
}

fun driveNonInline(block: Int.() -> Unit) {
    val worker = object {
        fun run() {
            block(1)
        }
    }
    worker.run()
}

fun main() {
    driveNonInline { }
    println(box())
}
