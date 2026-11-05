// KUU-4082: `this += x` inside a receiver lambda whose receiver is a
// parenthesized elvis expression — the protobuf Builder merge pattern
// `(x ?: Builder()).apply { this += v }`. `this` is never assignable, so
// `+=` resolves only via `plusAssign` on the lambda receiver.
class Builder {
    val items = mutableListOf<String>()
    operator fun plusAssign(s: String) {
        items.add(s)
    }
}

fun merge(dst: Builder, src: Builder?) {
    (src ?: Builder()).apply {
        this += "a"
        this += "b"
    }
    dst.items.addAll((src ?: Builder()).items)
}

fun main() {
    val b = Builder()
    merge(b, Builder().apply { this += "x" })
    println(b.items)

    val c = (null as Builder?).let { (it ?: Builder()).apply { this += "y" } }
    println(c.items)

    val d = Builder()
    d.apply { this@apply += "z" }
    println(d.items)
}
