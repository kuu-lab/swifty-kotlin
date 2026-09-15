// KSP-700: `List<E>.get(index)` is now declared in bundled Kotlin source
// (Stdlib/kotlin/collections/List.kt) as an external member backed by the
// existing __kk_list_get runtime bridge, instead of Swift-side synthetic Sema
// registration. Locks observable behavior for indexed access on List and
// MutableList receivers, including through a generic type parameter.
//
// Not covered here: a user class implementing List<T> (directly, or via
// AbstractList). Real kotlin-stdlib's List interface also requires
// indexOf/lastIndexOf/listIterator/listIterator(index)/subList overrides,
// which remain Swift-side residuals in this compiler (out of KSP-700 scope,
// see List.kt's header comment); AbstractList subclassing through this
// harness's precompiled stdlib artifact additionally hits the pre-existing
// BUG-200 gap (see ksp633_abstract_collections.kt).

fun <T> firstOf(list: List<T>): T = list[0]

fun main() {
    val list: List<Int> = listOf(10, 20, 30)
    println(list[0])
    println(list[1])
    println(list[list.size - 1])

    val mutable: MutableList<Int> = mutableListOf(1, 2, 3)
    mutable[1] = 99
    println(mutable[0])
    println(mutable[1])
    println(mutable[2])

    println(firstOf(listOf("a", "b", "c")))
    println(firstOf(mutable))

    val nested: List<List<Int>> = listOf(listOf(1, 2), listOf(3, 4, 5))
    println(nested[1][2])
}
