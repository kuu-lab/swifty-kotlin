package kotlin.reflect

import kotlin.jvm.internal.ClassReference

public val KType.javaType: java.lang.reflect.Type
    get() {
        val klass = classifier
        if (klass is ClassReference<*>) return klass.jClass
        throw UnsupportedOperationException("No Java type is available for $this")
    }
