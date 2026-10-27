// KUU-3566: `KotlinReflectionNotSupportedError` must resolve in a catch clause
// (previously KSWIFTK-SEMA-0085, "Unresolved exception type"). With no
// kotlin-reflect implementation, `KProperty0.getDelegate()` throws it
// (JetBrains delegatedProperty/getDelegateWithoutReflection.kt); the JVM
// reference throws its own reflective-access failure instead, so the
// delegated-property probe only pins that a Throwable escapes.
val foo: String by Delegate

object Delegate {
    operator fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): String = ""
}

fun main() {
    try {
        throw KotlinReflectionNotSupportedError("boom")
    } catch (e: KotlinReflectionNotSupportedError) {
        println("OK")
    }
    try {
        throw KotlinReflectionNotSupportedError()
    } catch (e: OutOfMemoryError) {
        println("sibling-caught")
    } catch (e: Error) {
        println("parent-caught")
    }
    try {
        ::foo.getDelegate()
        println("no-throw")
    } catch (e: Throwable) {
        println("delegate-threw")
    }
}
