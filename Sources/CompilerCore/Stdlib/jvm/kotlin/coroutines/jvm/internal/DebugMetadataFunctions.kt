@file:kotlin.jvm.JvmName("DebugMetadataKt")
package kotlin.coroutines.jvm.internal
import kotlin.jvm.internal.*
import kotlin.jvm.java
fun stackTraceElement(frame: BaseContinuationImpl): java.lang.StackTraceElement? {
    val type = __jvmClassOf(frame)
    val metadata = __jvmClassAnnotation(type, DebugMetadata::class.java) as DebugMetadata?
    if (metadata == null) return null
    var label = -1
    for (memberField in __jvmDeclaredFields(type)) if (__jvmFieldName(memberField) == "label") {
        __jvmSetAccessible(memberField, true)
        label = (__jvmFieldGet(memberField, frame) as Int) - 1
    }
    val lines = metadata.l
    val line = if (label >= 0 && label < lines.size) lines[label] else -1
    return __jvmNewStackTraceElement(metadata.c, metadata.m, metadata.f, line)
}
