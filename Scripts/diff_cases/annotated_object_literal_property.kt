annotation class My

fun foo(): Int {
    val s = object { @My val bar: Int = 0 }
    return s.bar
}

fun inferredProperty(): Int {
    val s = object { @My val bar = 1 }
    return s.bar
}

fun unannotatedProperty(): Int {
    val s = object { val bar: Int = 2 }
    return s.bar
}

class Holder {
    @My val bar: Int = 3
}

fun annotatedClassProperty(): Int = Holder().bar

fun annotatedLocalProperty(): Int {
    @My val bar: Int = 4
    return bar
}

fun main() {
    println(foo())
    println(inferredProperty())
    println(unannotatedProperty())
    println(annotatedClassProperty())
    println(annotatedLocalProperty())
}
