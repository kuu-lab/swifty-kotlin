package kotlin.reflect.full
val <T> kotlin.reflect.KClass<T>.memberProperties: Collection<kotlin.reflect.KProperty1<T, *>> get() = null!!
val <T> kotlin.reflect.KClass<T>.memberFunctions: Collection<kotlin.reflect.KFunction<*>> get() = null!!
fun <T: Any> kotlin.reflect.KClass<T>.createInstance(): T = null!!
inline fun <reified T: Annotation> kotlin.reflect.KAnnotatedElement.findAnnotation(): T? = null
inline fun <reified T: Annotation> kotlin.reflect.KAnnotatedElement.findAnnotations(): List<T> = null!!