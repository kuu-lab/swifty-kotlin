// KUU-4064: member-extension properties/functions are excluded from
// member*/declaredMember* like the JVM, but still list under `members`
// and surface through memberExtension*/declaredMemberExtension*.
import kotlin.reflect.full.*

open class Host {
    var String.extProp: Int
        get() = length
        set(value) {}
    fun String.extFn(): Int = length
    val normal: Int = 1
    fun normalFn() = 0
}

class Sub : Host() {
    val String.subExt: Int
        get() = length
}

fun main() {
    val klass = Host::class
    println("memberProperties has extProp: ${klass.memberProperties.any { it.name == "extProp" }}")
    println("memberProperties has normal: ${klass.memberProperties.any { it.name == "normal" }}")
    println("declaredMemberProperties has extProp: ${klass.declaredMemberProperties.any { it.name == "extProp" }}")
    println("declaredMemberProperties has normal: ${klass.declaredMemberProperties.any { it.name == "normal" }}")
    println("memberFunctions has extFn: ${klass.memberFunctions.any { it.name == "extFn" }}")
    println("memberFunctions has normalFn: ${klass.memberFunctions.any { it.name == "normalFn" }}")
    println("declaredMemberFunctions has extFn: ${klass.declaredMemberFunctions.any { it.name == "extFn" }}")
    println("members has extProp: ${klass.members.any { it.name == "extProp" }}")
    println("members has extFn: ${klass.members.any { it.name == "extFn" }}")
    println("memberExtensionProperties has extProp: ${klass.memberExtensionProperties.any { it.name == "extProp" }}")
    println("memberExtensionProperties has normal: ${klass.memberExtensionProperties.any { it.name == "normal" }}")
    println("declaredMemberExtensionProperties has extProp: ${klass.declaredMemberExtensionProperties.any { it.name == "extProp" }}")
    println("memberExtensionFunctions has extFn: ${klass.memberExtensionFunctions.any { it.name == "extFn" }}")
    println("memberExtensionFunctions has normalFn: ${klass.memberExtensionFunctions.any { it.name == "normalFn" }}")
    println("declaredMemberExtensionFunctions has extFn: ${klass.declaredMemberExtensionFunctions.any { it.name == "extFn" }}")

    val sub = Sub::class
    println("Sub memberExtensionProperties has extProp: ${sub.memberExtensionProperties.any { it.name == "extProp" }}")
    println("Sub memberExtensionProperties has subExt: ${sub.memberExtensionProperties.any { it.name == "subExt" }}")
    println("Sub declaredMemberExtensionProperties has extProp: ${sub.declaredMemberExtensionProperties.any { it.name == "extProp" }}")
    println("Sub declaredMemberExtensionProperties has subExt: ${sub.declaredMemberExtensionProperties.any { it.name == "subExt" }}")
    println("Sub memberExtensionFunctions has extFn: ${sub.memberExtensionFunctions.any { it.name == "extFn" }}")
    println("Sub memberProperties has subExt: ${sub.memberProperties.any { it.name == "subExt" }}")
}
