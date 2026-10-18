package f02jvmabi

import kotlinx.io.Segment
import java.lang.reflect.Modifier

object SegmentDataAsByteArrayJvmAbi {
    @JvmStatic
    fun main(@Suppress("UNUSED_PARAMETER") args: Array<String>) {
        val booleanClass = java.lang.Boolean.TYPE
        val method = Segment::class.java.getDeclaredMethod(
            "dataAsByteArray",
            booleanClass,
        )

        check(method.parameterTypes.contentEquals(arrayOf(booleanClass)))
        check(method.returnType == ByteArray::class.java)
        check(Modifier.isPublic(method.modifiers))
        check(Modifier.isFinal(method.modifiers))
        check(!Modifier.isStatic(method.modifiers))
        check(method.isSynthetic)

        f02consumer.main()
    }
}
