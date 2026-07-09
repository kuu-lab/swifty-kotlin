// A property whose only customized accessor is the getter (no explicit
// `set(value) { ... }` block) still has a backing field once the getter
// references `field`. Its initializer, and any `field = ...` write inside
// the getter itself, must both land in the real per-instance storage rather
// than being silently dropped or routed through a setter accessor that was
// never emitted for this property.
class DoubledOnRead {
    var x: Int = 5
        get() = field * 2
}

class LazyAccumulator {
    var cache: Int = 5
        get() {
            field = field + 100
            return field
        }
}

// A property with BOTH a custom getter and a custom setter: the initializer
// must land directly in backing storage, bypassing the setter — `field`
// starts at 2 (the initializer value), not 2*3=6 (what running it through
// the setter's transform would produce).
class BothAccessors {
    var y: Int = 2
        get() = field + 100
        set(value) { field = value * 3 }
}

fun main() {
    println(DoubledOnRead().x)
    val acc = LazyAccumulator()
    println(acc.cache)
    println(acc.cache)
    println(acc.cache)

    println(BothAccessors().y)
}
