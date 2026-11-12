// DIFF_JVM
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.PROPERTY_GETTER)
annotation class GetterMark
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.PROPERTY_SETTER)
annotation class SetterMark

class Box {
    val value: Int @GetterMark get() = 42
    var mutable: Int = 1
    @SetterMark set(v) { field = v }
}

fun main() {
    val box = Box()
    println(box.value)
    box.mutable = 42
    println(box.mutable)
}
