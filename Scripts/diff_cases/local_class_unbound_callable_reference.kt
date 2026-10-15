class Outer { fun foo(): String = "OUTER" }

fun box(): String {
    class Local { fun foo(): String = "OK" }
    val ref = Local::foo
    return ref(Local())
}

fun typed(): String {
    class Local { fun foo(): String = "TYPED" }
    val ref: (Local) -> String = Local::foo
    return ref(Local())
}

fun controls(): String {
    class Local { fun foo(): String = "BOUND" }
    val local = Local()
    val bound: () -> String = local::foo
    val direct = local.foo()
    val external: (Outer) -> String = Outer::foo
    return bound() + "|" + direct + "|" + external(Outer())
}

fun main() {
    println(box() + "|" + typed() + "|" + controls())
}
