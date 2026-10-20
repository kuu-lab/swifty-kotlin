package java.lang
class Class<T> {
    val name: String get() = ""
    val simpleName: String get() = ""
    val isAnnotation: Boolean get() = false
    fun isInstance(value: Any?): Boolean = false
    fun <A: Annotation> getAnnotation(annotationClass: Class<A>): A? = null
    fun <A: Annotation> getAnnotationsByType(annotationClass: Class<A>): Array<A> = null!!
}