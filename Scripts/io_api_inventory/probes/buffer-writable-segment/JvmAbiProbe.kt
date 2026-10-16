package f02consumer

import kotlinx.io.Buffer
import kotlinx.io.Segment
import java.lang.reflect.Modifier

fun verifyWritableSegmentJvmAbi() {
    val method = Buffer::class.java.getDeclaredMethod("writableSegment", Int::class.javaPrimitiveType)
    check(Modifier.isPublic(method.modifiers))
    check(Modifier.isFinal(method.modifiers))
    check(method.isSynthetic)
    check(!Modifier.isStatic(method.modifiers))
    check(method.parameterTypes.contentEquals(arrayOf(Int::class.javaPrimitiveType)))
    check(method.returnType == Segment::class.java)
    println("jvm-abi:public-final-synthetic-instance-writableSegment(I)Lkotlinx/io/Segment;")
}

fun main() {
    verifyWritableSegmentJvmAbi()
}
