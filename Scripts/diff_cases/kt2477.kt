// JetBrains compiler/testData/codegen/box/classes/kt2477.kt: private members
// — in a superclass and in a sibling interface — must not be selected as the
// runtime (itable) implementation of a same-named interface property.
interface A {
    val c: String
        get() = "OK"
}

interface B {
    private val c: String
        get() = "FAIL"
}

open class C {
    private val c: String = "FAIL"
}

class D : C(), A, B {
    val b = c
}

fun main() {
    println(D().c)
    println(D().b)
    val a: A = D()
    println(a.c)
}
