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

fun main() {
    println(DoubledOnRead().x)
    val acc = LazyAccumulator()
    println(acc.cache)
    println(acc.cache)
    println(acc.cache)
}
