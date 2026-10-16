fun box(): String {
    var s = ""
    var foo = "O"
    fun foo(x: String) {
        s += x
    }
    fun foo() {
        foo("K")
    }
    run {
        foo(foo)
        foo()
    }
    return s
}

fun probe(): String {
    var s = ""
    var foo = "O"
    fun foo(value: String) {
        s += value
    }
    fun foo() {
        foo("K")
    }
    foo(foo)
    foo()
    return s
}

fun control(): String {
    fun foo(value: String): String = value
    return foo("OK")
}

fun main() {
    println(box())
    println(probe())
    println(control())
}
