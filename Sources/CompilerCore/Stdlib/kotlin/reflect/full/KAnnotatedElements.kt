package kotlin.reflect.full

import kotlin.reflect.KAnnotatedElement

@SinceKotlin("1.1")
public inline fun <reified T : Annotation> KAnnotatedElement.findAnnotation(): T? {
    for (annotation in annotations) {
        if (annotation is T) return annotation
    }
    return null
}
