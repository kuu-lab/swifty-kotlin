// KUU-3566: `KotlinReflectionNotSupportedError` must resolve in a catch clause
// (previously KSWIFTK-SEMA-0085, "Unresolved exception type"). The former
// `::foo.getDelegate()` probe was dropped: KUU-3694 (#12067) deliberately
// answers the delegate on native while the JVM throws a reflective-access
// failure, and that divergence is pinned by kuu_3694_kproperty_getdelegate.kt.
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
}
