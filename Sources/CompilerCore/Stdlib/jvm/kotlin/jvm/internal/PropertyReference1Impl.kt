package kotlin.jvm.internal
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.*
open class PropertyReference1Impl: RuntimeProperty, KProperty1<Any?, Any?> {
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(receiver: Any?): Any? = readOne(receiver)
    override fun invoke(receiver: Any?): Any? = readOne(receiver)
}
