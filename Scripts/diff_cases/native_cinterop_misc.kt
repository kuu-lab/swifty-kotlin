// SKIP-DIFF (DEBT-DIFF-001): kotlinx.cinterop handle types and the kotlin.native
// identityHashCode surface are Kotlin/Native-only; JVM kotlinc cannot resolve them.
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
    println(identityHashCode(obj) == identityHashCode(obj))
    println(probeTypes(null, null, null, null))
}
