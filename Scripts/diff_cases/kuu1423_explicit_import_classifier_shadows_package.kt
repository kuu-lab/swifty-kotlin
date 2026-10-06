// KUU-1423: an explicit single-type import ranks above same-package
// declarations in Kotlin's classifier namespace, so `Pair` in type position
// must resolve to the imported kotlin.Pair even though the root package
// declares its own Pair. Pre-fix the type annotation bound to the package
// Pair, which rejected the kotlin.Pair initializer.
import kotlin.Pair

class Pair(val x: Int)

fun main() {
    val p: Pair<Int, Int> = kotlin.Pair(1, 2)
    println(p)
}
