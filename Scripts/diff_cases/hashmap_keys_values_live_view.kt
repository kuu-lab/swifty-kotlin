// A HashMap-statically-typed receiver dispatches keys/values through
// HashMap's own override, not the MutableMap interface residual, so it needs
// the same live-view fix independently. Also covers values.remove(v) picking
// the first matching entry (by iteration order) when the value is duplicated.
fun main() {
    val hm: HashMap<Int, String> = HashMap()
    hm[1] = "a"
    val ks = hm.keys
    val vs = hm.values
    hm[2] = "b"
    println(ks)
    println(vs)

    val dup = mutableMapOf(1 to "a", 2 to "a")
    dup.values.remove("a")
    println(dup)
}
