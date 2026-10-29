// KUU-3746: `C().length` must select the member `length`, not the same-named
// member extension `Box.length` declared in `C`. The extension needs a `Box`
// receiver plus a `C` dispatch receiver, so it is never applicable through a
// plain member access — and it is private to `C` anyway. The same-named
// member must be picked before access checks run.
class Box(val size: Int)

class C {
    private val Box.length: Int
        get() = size
    val length: Int get() = 2
    fun read(b: Box) = b.length
}

val Box.tag: Int get() = size * 10

fun main() {
    println(C().length)
    println(C().read(Box(7)))
    println(Box(3).tag)
}
