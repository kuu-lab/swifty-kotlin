// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3827: touching any enum-API surface (`entries` here) must trigger the
// full enum <clinit> — entries first, then the `companion {}` block
// initializers — even when the enum has no named `companion object`.

var initOrder = ""

enum class Foo(val f: String) {
    Alpha(run { initOrder += "1"; "alpha" });

    companion {
        val blockProp: String = run { initOrder += "2"; "block" }
    }
}

fun main() {
    println(Foo.entries)
    println(initOrder)
}
