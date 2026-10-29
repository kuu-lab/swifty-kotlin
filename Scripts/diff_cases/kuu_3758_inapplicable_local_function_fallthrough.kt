// KUU-3758: an inapplicable local function must not hide an outer overload.
// kotlinc 2.4.20 resolves `pick(true)` to the top-level `pick(Boolean)`
// because the local `pick(Long)` is not applicable for a Boolean argument —
// the call tower continues past scope tiers that offer no applicable
// candidate, for locals just as for implicit-receiver members.
interface S { fun pick(value: Long): Int }

class Source : S {
    override fun pick(value: Long): Int = 1
}

fun pick(value: Boolean): String = "outer"

fun S.read(): String {
    fun pick(value: Long): Int = 7
    return pick(true)
}

fun main() {
    println(Source().read())
}
