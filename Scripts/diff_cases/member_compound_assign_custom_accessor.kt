class Clamped {
    var value: Int = 0
        set(v) { field = if (v < 0) 0 else v }
}

class Doubled(var raw: Int) {
    var value: Int
        get() = raw * 2
        set(v) { raw = v }
}

class Both(var raw: Int) {
    var value: Int
        get() = raw * 10
        set(v) { raw = v + 1 }
}

fun main() {
    // Compound assignment through an explicit receiver must call a custom
    // setter body (not write the backing field directly), so its logic runs.
    val c = Clamped()
    c.value = 10
    println(c.value)
    c.value += -100
    println(c.value)

    // ++ / -- desugar to the same load -> compute -> store path.
    c.value++
    println(c.value)

    // Custom getter + setter that redirect through a different property.
    val d = Doubled(0)
    d.value = 5
    println(d.value)
    d.value += 3
    println(d.value)
    println(d.raw)

    // Both sides custom: load must call the getter, store must call the setter.
    val b = Both(1)
    println(b.value)
    b.value += 5
    println(b.value)
    println(b.raw)
}
