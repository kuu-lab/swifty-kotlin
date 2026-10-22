package kotlin.reflect.jvm.internal
import kotlin.jvm.internal.*
import kotlin.reflect.KClass
import kotlin.jvm.getJavaClass
internal fun constructAnnotation(type: Any, arguments: Map<String, Any?>): Any {
    val values = mutableMapOf<String, Any?>()
    for (method in __jvmDeclaredMethods(type)) {
        val name = __jvmMethodName(method)
        val value = if (arguments.containsKey(name)) arguments[name] else __jvmMethodDefault(method)
        if (value == null) throw IllegalArgumentException("Missing annotation argument: $name")
        val resultType = __jvmMethodReturn(method)
        values[name] = if (value is KClass<*>) getJavaClass(value)
        else if (value is Array<*> && __jvmClassIsArray(resultType) && __jvmClassName(__jvmComponentType(resultType)) == "java.lang.Class") {
            // Annotation methods expose Class[], including empty/default arrays.
            val classes = arrayOfNulls<java.lang.Class<*>>(value.size)
            var index = 0
            while (index < value.size) {
                val element = value[index]
                classes[index] = if (element is KClass<*>) getJavaClass(element) else element as java.lang.Class<*>
                index++
            }
            classes
        } else value
    }
    return __jvmProxy(__jvmClassLoader(type), arrayOf(type as java.lang.Class<*>), AnnotationHandler(type, values))
}
private class AnnotationHandler(private val type: Any, private val values: Map<String, Any?>): java.lang.reflect.InvocationHandler {
    override fun invoke(proxy: Any, method: java.lang.reflect.Method, args: Array<Any?>?): Any? {
        val name = __jvmMethodName(method)
        if (name == "annotationType") return type
        if (name == "equals") {
            val other = args!![0]
            if (other == null || !__jvmClassInstance(type, other)) return false
            for (member in __jvmDeclaredMethods(type)) {
                __jvmSetAccessible(member, true)
                if (!__jvmDeepEquals(values[__jvmMethodName(member)], invokeMethod(member, other, arrayOf<Any?>()))) return false
            }
            return true
        }
        if (name == "hashCode") {
            var hash = 0
            for (member in __jvmDeclaredMethods(type)) {
                val memberName = __jvmMethodName(member)
                hash += (127 * memberName.hashCode()) xor (__jvmDeepHash(arrayOf(values[memberName])) - 31)
            }
            return hash
        }
        if (name == "toString") {
            val result = StringBuilder("@" + __jvmClassName(type) + "(")
            var first = true
            for (member in __jvmDeclaredMethods(type)) {
                if (!first) result.append(", ")
                first = false
                val memberName = __jvmMethodName(member)
                result.append(memberName); result.append("=")
                val value = values[memberName]
                if (value is String) { result.append('"'); result.append(value); result.append('"') }
                else {
                    val rendered = __jvmDeepString(arrayOf(value))
                    result.append(rendered.substring(1, rendered.length - 1))
                }
            }
            result.append(")")
            return result.toString()
        }
        return values[name]
    }
}
