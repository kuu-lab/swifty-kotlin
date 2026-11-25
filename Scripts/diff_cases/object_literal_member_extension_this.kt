// KUU-4606 follow-up: inside a member extension, an object literal that
// captures `this@Outer` must capture the dispatch receiver (`this@Outer`),
// not the extension receiver (`this`). kotlinc prints "dispatch".
class Outer(val tag: String) {
    fun Outer.memberExt(): Outer {
        val o = object {
            fun capture(): Outer = this@Outer
        }
        return o.capture()
    }

    fun run(other: Outer): String {
        return other.memberExt().tag
    }
}

fun main() {
    val dispatch = Outer("dispatch")
    val ext = Outer("extension")
    println(dispatch.run(ext))
}
