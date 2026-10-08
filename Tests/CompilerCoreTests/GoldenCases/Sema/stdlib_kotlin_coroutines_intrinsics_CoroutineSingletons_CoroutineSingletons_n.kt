@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
import kotlin.coroutines.intrinsics.CoroutineSingletons

// KUU-1597 Sema owner: pin CoroutineSingletons enum values/entries/name/valueOf resolution; enum ordering and lookup behavior stay in Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt.
fun main() {
    val values: Array<CoroutineSingletons> = CoroutineSingletons.values()
    val entries = CoroutineSingletons.entries
    val firstName: String = values[0].name
    val suspended: CoroutineSingletons = CoroutineSingletons.COROUTINE_SUSPENDED
    val undecided: CoroutineSingletons = CoroutineSingletons.UNDECIDED
    val resumed: CoroutineSingletons = CoroutineSingletons.RESUMED
    val lookup: CoroutineSingletons = CoroutineSingletons.valueOf("RESUMED")
}
