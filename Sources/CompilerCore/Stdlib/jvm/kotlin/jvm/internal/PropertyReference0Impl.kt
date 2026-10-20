package kotlin.jvm.internal
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.*
open class PropertyReference0Impl: RuntimeProperty, KProperty0<Any?> {
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(): Any? = readZero()
    override fun invoke(): Any? = readZero()
}
