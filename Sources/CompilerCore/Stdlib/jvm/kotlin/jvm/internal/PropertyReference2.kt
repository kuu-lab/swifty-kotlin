package kotlin.jvm.internal

import kotlin.reflect.KProperty2
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.jvm.internal.RuntimeProperty2Getter

abstract class PropertyReference2(
    owner: java.lang.Class<*>, name: String, signature: String, flags: Int
): RuntimeProperty(owner, name, signature, null, false), KProperty2<Any?, Any?, Any?> {
    constructor(): this(Any::class.java, "", "", 0)

    override val getter: KProperty2.Getter<Any?, Any?, Any?> get() = RuntimeProperty2Getter(this)
    override fun invoke(receiver1: Any?, receiver2: Any?): Any? = get(receiver1, receiver2)
    override fun getDelegate(receiver1: Any?, receiver2: Any?): Any? = delegateFor(receiver1)
}

open class PropertyReference2Impl(
    owner: java.lang.Class<*>, name: String, signature: String, flags: Int
): PropertyReference2(owner, name, signature, flags) {
    override fun get(receiver1: Any?, receiver2: Any?): Any? = readTwo(receiver1, receiver2)
}
