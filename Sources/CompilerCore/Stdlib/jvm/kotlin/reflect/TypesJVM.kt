package kotlin.reflect

import kotlin.jvm.internal.*

public val KType.javaType: java.lang.reflect.Type
    get() {
        val klass = classifier
        if (klass is ClassReference<*>) {
            // Nullable primitives box on the JVM, so `Int?` maps to
            // java.lang.Integer rather than int.class.
            if (isMarkedNullable && __jvmClassIsPrimitive(klass.jClass)) {
                val boxedName = when (__jvmClassName(klass.jClass)) {
                    "int" -> "java.lang.Integer"
                    "long" -> "java.lang.Long"
                    "byte" -> "java.lang.Byte"
                    "short" -> "java.lang.Short"
                    "char" -> "java.lang.Character"
                    "float" -> "java.lang.Float"
                    "double" -> "java.lang.Double"
                    "boolean" -> "java.lang.Boolean"
                    else -> null
                }
                if (boxedName != null) return __jvmLoadClass(boxedName, false, null) as java.lang.Class<*>
            }
            return klass.jClass
        }
        throw UnsupportedOperationException("No Java type is available for $this")
    }
