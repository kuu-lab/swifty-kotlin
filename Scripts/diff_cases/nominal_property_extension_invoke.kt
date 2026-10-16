interface InvokeTarget
operator fun InvokeTarget.invoke(): String = "extension"
class ExtensionTarget : InvokeTarget

class MemberTarget : InvokeTarget {
    operator fun invoke(): String = "member"
}

class InapplicableMemberTarget : InvokeTarget {
    operator fun invoke(value: Int): String = "member:$value"
}
operator fun InapplicableMemberTarget.invoke(): String = "specific-extension"

class MemberPropertyHolder(val value: MemberTarget)
class FallbackPropertyHolder(val value: InapplicableMemberTarget)
class NullablePropertyHolder(val value: ExtensionTarget)

var getterReads = 0
class GetterPropertyHolder {
    val value: ExtensionTarget
        get() {
            getterReads++
            return ExtensionTarget()
        }
}

object ObjectPropertyHolder {
    val value = ExtensionTarget()
}

class ExtensionDispatcher {
    operator fun ExtensionTarget.invoke(): String = "dispatch-extension"
}

fun nullableCall(holder: NullablePropertyHolder?): String? = holder?.value()
fun localCallControl(): String {
    val value: InvokeTarget = ExtensionTarget()
    return value()
}
fun explicitInvokeControl(): String = ObjectPropertyHolder.value.invoke()
fun propertyReadControl(): String = if (ObjectPropertyHolder.value is InvokeTarget) "OK" else "FAIL"
fun dispatchExtensionCall(): String = with(ExtensionDispatcher()) { ObjectPropertyHolder.value() }

fun main() {
    println(ObjectPropertyHolder.value())
    println(MemberPropertyHolder(MemberTarget()).value())
    println(FallbackPropertyHolder(InapplicableMemberTarget()).value())
    println(nullableCall(null))
    println(nullableCall(NullablePropertyHolder(ExtensionTarget())))
    println(localCallControl())
    println(explicitInvokeControl())
    println(propertyReadControl())
    println(dispatchExtensionCall())
    println(GetterPropertyHolder().value())
    println("getters:$getterReads")
}
