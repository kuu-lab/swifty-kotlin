package kotlin.jvm.internal
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.jvm.internal.RuntimeProperty0Getter
import kotlin.reflect.*
open class PropertyReference0Impl: RuntimeProperty, KProperty0<Any?> {
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(): Any? = readZero()
    override fun invoke(): Any? = readZero()
    override fun getDelegate(): Any? = delegateZero()
    override val getter: KProperty0.Getter<Any?> get() = RuntimeProperty0Getter(this)
}
