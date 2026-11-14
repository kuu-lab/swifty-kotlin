package java.lang
class Class<T> : java.lang.reflect.Type {
    val name: kotlin.String get() = ""
    val simpleName: kotlin.String get() = ""
    val isAnnotation: Boolean get() = false
    val enumConstants: Array<T>? get() = null
    fun isInstance(value: Any?): Boolean = false
    fun isAssignableFrom(type: Class<*>): Boolean = false
    fun getDeclaredField(name: kotlin.String): java.lang.reflect.Field = null!!
    fun <A: Annotation> getAnnotation(annotationClass: Class<A>): A? = null
    fun <A: Annotation> getAnnotationsByType(annotationClass: Class<A>): Array<A> = null!!
}
