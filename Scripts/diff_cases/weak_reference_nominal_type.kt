// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: weak_reference_nominal_type.expected.stdout
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.ref.WeakReference
import kotlin.native.ref.clear

private class Payload
private fun erase(value: Any): Any = value

fun main() {
    val payload = Payload()
    val typed = WeakReference(payload)
    val erased = erase(typed)
    println(erased is WeakReference<*>)
    val reference = erased as WeakReference<*>
    println(reference.value === payload)
    typed.clear()
    println(reference.value == null)
    println(erased is String)
}
