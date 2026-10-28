// KUU-3535 / KUU-3539: an erased `as T` cannot verify itself, so the
// checkcast belongs where the erased value is claimed at a concrete type —
// the generic call result and the FunctionN invoke bridge. A wrong-type
// value must throw a catchable ClassCastException naming both classes
// instead of trapping inside a later virtual dispatch. Message contents are
// asserted via contains() because the exact JVM/KSwiftK formats differ.
private fun <T> some(): T = Some1() as T

private class Some1
private class Some2(val s: String) {
    fun foo() = "Some2: $s"
}

private fun <T : Any> invokeIt(any: Any, extract: (T) -> String): String {
    @Suppress("UNCHECKED_CAST")
    return extract(any as T)
}

fun main() {
    try {
        val some2: Some2 = some<Some2>()
        println("no exception: " + some2.foo())
    } catch (cce: ClassCastException) {
        val m = cce.message ?: ""
        println("cce src=" + (m.contains("Some1") || m.contains("String")) +
            " tgt=" + m.contains("Some2") + " fmt=" + m.contains("cannot be cast"))
    } catch (t: Throwable) {
        println("wrong throwable: " + t::class.simpleName)
    }

    try {
        println("bridge: " + invokeIt<Some2>("x") { it.foo() })
    } catch (cce: ClassCastException) {
        val m = cce.message ?: ""
        println("bridge cce src=" + m.contains("String") +
            " tgt=" + m.contains("Some2") + " fmt=" + m.contains("cannot be cast"))
    } catch (t: Throwable) {
        println("wrong throwable: " + t::class.simpleName)
    }

    val s1: Some1 = some()
    println("generic ok: " + (s1 is Some1))
    println("bridge ok: " + invokeIt<Some2>(Some2("ok")) { it.foo() })
}
