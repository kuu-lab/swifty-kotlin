package java.lang.reflect

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_java_field_get_annotations_typed")
private external fun __fieldGetAnnotations(field: Field): Array<Annotation>

/** JVM-shaped metadata for enum entry fields exposed by java.lang.Class. */
public class Field internal constructor() {
    public fun getAnnotations(): Array<Annotation> = __fieldGetAnnotations(this)
}
