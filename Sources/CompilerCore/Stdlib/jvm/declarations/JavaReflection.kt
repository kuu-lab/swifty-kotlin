package java.lang
class Class<T> : java.lang.reflect.Type {
    val name: kotlin.String get() = ""
    val simpleName: kotlin.String get() = ""
    val isAnnotation: Boolean get() = false
    fun isInstance(value: Any?): Boolean = false
    fun <A: Annotation> getAnnotation(annotationClass: Class<A>): A? = null
    fun <A: Annotation> getAnnotationsByType(annotationClass: Class<A>): Array<A> = null!!
}
