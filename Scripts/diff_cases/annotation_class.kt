import kotlin.jvm.annotationClass

annotation class A(val v: Int = 1)
annotation class B
@A
class Tagged

fun show(annotation: Annotation) {
    println(annotation.annotationClass)
    println(annotation.annotationClass.simpleName)
}

fun main() {
    println(A().annotationClass)
    show(A())
    show(B())
    val annotation: Annotation? = B()
    println(annotation?.annotationClass?.simpleName)
    println(Tagged::class.annotations[0].annotationClass)
}
