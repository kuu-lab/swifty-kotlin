@file:kotlin.jvm.JvmName("KAnnotatedElements")
package kotlin.reflect.full
import kotlin.reflect.*
import kotlin.reflect.jvm.internal.*
import kotlin.jvm.internal.*
fun <T: Annotation> findAnnotations(element: KAnnotatedElement, type: KClass<T>): List<T> {
    val klass = (type as ClassReference<T>).jClass
    val result = mutableListOf<T>()
    val repeatableType = __jvmLoadClass("java.lang.annotation.Repeatable", false, null)
    val repeatable = __jvmClassAnnotation(klass, repeatableType)
    val container = if (repeatable == null) null else __jvmRepeatableContainer(repeatable)
    for (annotation in element.annotations) {
        if (__jvmClassInstance(klass, annotation)) result.add(annotation as T)
        else if (container != null && __jvmClassInstance(container, annotation)) {
            for (method in __jvmDeclaredMethods(container)) if (__jvmMethodName(method) == "value") {
                val values = invokeMethod(method, annotation, arrayOf<Any?>()) as Array<*>
                for (value in values) result.add(value as T)
            }
        }
    }
    return result
}
