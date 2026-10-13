package kotlin.reflect.full

import kotlin.reflect.KAnnotatedElement

/** Returns the first annotation of the given type on this element, or null. */
@SinceKotlin("1.1")
public inline fun <reified T : Annotation> KAnnotatedElement.findAnnotation(): T? {
    for (annotation in annotations) {
        if (annotation is T) return annotation
    }
    return null
}
