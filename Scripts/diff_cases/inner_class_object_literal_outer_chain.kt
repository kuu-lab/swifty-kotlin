// BUG-inner-outer: an object literal nested two `inner class` levels deep
// capturing/calling/assigning the outermost class's members -- by bare name,
// by `this@Label`, as a method call with arguments, as an assignment target,
// a compound assignment, and a callable reference. Each of these needs the
// full `$outer` chain, not just the immediate enclosing class.
//
// Excluded on purpose: a BARE (unqualified) read of `counter` from inside
// the object literal. That is a separate, still-open bug (a mutable
// property can't be captured by value like an immutable one, and there is
// currently no live-receiver path for a bare nameRef the way there is for
// `this@Outer.counter` or a bare call) -- tracked separately, not part of
// this fix.
class Outer(val tag: String) {
    var counter: Int = 0
    fun greet(extra: Int): String = "$tag:$extra"

    inner class Inner(val itag: String) {
        inner class Deep(val dtag: String) {
            fun make(): String {
                val obj = object {
                    fun show(): String {
                        val g = this@Outer.greet(5)
                        this@Outer.counter = 10
                        this@Outer.counter += 1
                        val bare = greet(7)
                        val qualifiedCounterRead = this@Outer.counter
                        val ref = this@Outer::greet
                        val refResult = ref(3)
                        return "$tag/$itag/$dtag/$g/$bare/$qualifiedCounterRead/$refResult"
                    }
                }
                return obj.show()
            }
        }
    }
}

fun main() {
    val o = Outer("hello")
    val i = o.Inner("in")
    val d = i.Deep("deep")
    println(d.make())
}
