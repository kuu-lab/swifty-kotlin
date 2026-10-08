// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: native_cinterop_misc.expected.stdout
@file:OptIn(kotlin.native.ExperimentalNativeApi::class)

import kotlinx.cinterop.CPointed
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.NativePlacement
import kotlinx.cinterop.NativeFreeablePlacement
import kotlin.native.identityHashCode

fun probeTypes(p: CPointed?, f: CFunction<*>?, pl: NativePlacement?, fpl: NativeFreeablePlacement?): Boolean =
    (p == null) && (f == null) && (pl == null) && (fpl == null)

fun main() {
    val obj = Any()
    println(obj.identityHashCode() == obj.identityHashCode())
    println(probeTypes(null, null, null, null))
}
