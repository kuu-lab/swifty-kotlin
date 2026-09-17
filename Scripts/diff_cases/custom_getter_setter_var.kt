// KUU-595: a mutable property with both custom accessors must call its getter
// on reads. The setter is not evidence that reads can bypass the getter.
class T1 {
    var c = 0.0; var f: Double get() = c * 2; set(v) { c = v / 2 }
}

class T2 {
    var c = 0.0; val f: Double get() = c * 9 / 5 + 32
}

class T3 {
    var c = 0.0; var f: Double get() = c * 9 / 5 + 32; set(v) { c = (v - 32) * 5 / 9 }
}

class T4 {
    var c = 0; var f: Int get() = c * 2; set(v) { c = v / 2 }
}

fun main() {
    val t1 = T1()
    t1.c = 3.0
    println(t1.f)
    t1.f = 10.0
    println(t1.c)
    println(t1.f)

    val t2 = T2()
    t2.c = 37.0
    println(t2.f)

    val t3 = T3()
    t3.c = 37.0
    println(t3.f)
    t3.f = 212.0
    println(t3.c)
    println(t3.f)

    val t4 = T4()
    t4.c = 3
    println(t4.f)
    t4.f = 10
    println(t4.c)
    println(t4.f)
}
