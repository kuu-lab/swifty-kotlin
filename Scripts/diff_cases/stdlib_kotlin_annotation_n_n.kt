@Target(AnnotationTarget.CLASS)
@Retention
annotation class RuntimeDefaultRetention

fun main() {
    println(AnnotationTarget.CLASS)
    println(AnnotationTarget.ANNOTATION_CLASS)
    println(AnnotationTarget.TYPEALIAS)
    println(AnnotationRetention.SOURCE)
    println(AnnotationRetention.BINARY)
    println(AnnotationRetention.RUNTIME)
    println(AnnotationRetention.RUNTIME == AnnotationRetention.RUNTIME)
}
