// KUU-2439 / KT-44496: no normally constructed instance reaches these properties.
class C {
    val todo: String = TODO()
    val uninitializedVal: String
    var uninitializedVar: String
}

class Foo {
    init { TODO() }
    val uninitializedVal: String
    var uninitializedVar: String
}

class Bar {
    val initializedVal = 43
    init { TODO() }
    val uninitializedVal: String
    var uninitializedVar: String
}

class ThrowingInit {
    init { throw IllegalStateException("stop") }
    val uninitialized: String
}

fun main() {
    try { C(); println("C:FAIL") } catch (e: NotImplementedError) { println("C:OK") }
    try { Foo(); println("Foo:FAIL") } catch (e: NotImplementedError) { println("Foo:OK") }
    try { Bar(); println("Bar:FAIL") } catch (e: NotImplementedError) { println("Bar:OK") }
    try { ThrowingInit(); println("ThrowingInit:FAIL") } catch (e: IllegalStateException) { println("ThrowingInit:OK") }
}
