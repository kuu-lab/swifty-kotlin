// KUU-2295: Adapted from JetBrains/kotlin's pinned public box test.
// https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/annotations/resolveWithLowPriorityAnnotation.kt
@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun foo(i: Int): Int = 1
fun foo(a: Any): Int = 2

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun bar(a: String?): Int = 3
fun bar(a: Any): Int = 4

class MyString(val value: String)
class Baz
@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
constructor(val s: String) {
    constructor(s: MyString): this(s.value)
}

fun Baz(s: String) = Baz(MyString(s + "!"))

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun select(x: Int): String = "int"
fun select(x: Any): String = "any"

fun selectWithoutAnnotation(x: Int): String = "int"
fun selectWithoutAnnotation(x: Any): String = "any"

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun selectInapplicableLowPriority(x: Boolean): String = "boolean"
fun selectInapplicableLowPriority(x: Any): String = "any"

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun selectWhenOnlyLowPriorityIsApplicable(x: Int): String = "int"
fun selectWhenOnlyLowPriorityIsApplicable(x: Boolean): String = "boolean"

fun box(): String {
    if (foo(1) != 2) return "fail1"
    if (bar(null) != 3) return "fail2"
    if (Baz("hello").s != "hello!") return "fail3"
    if (select(1) != "any") return "FAIL:low-priority"
    if (selectWithoutAnnotation(1) != "int") return "FAIL:annotation-free"
    if (selectInapplicableLowPriority(1) != "any") return "FAIL:inapplicable-low-priority"
    if (selectWhenOnlyLowPriorityIsApplicable(1) != "int") return "FAIL:only-applicable-low-priority"
    return "OK"
}

fun main() {
    print(box())
}
