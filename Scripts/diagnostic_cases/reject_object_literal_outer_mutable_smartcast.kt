// EXPECT-REJECT
// KUU-4606: a mutable outer property is not a stable smart-cast root, so the
// object literal member keeps the nullable type and both compilers reject the
// typed assignment.
class Outer {
    var mutable: String? = "ok"

    fun f() {
        if (mutable != null) {
            val o = object {
                fun read() = mutable
            }
            val s: String = o.read()
        }
    }
}

fun main() {
    Outer().f()
}
