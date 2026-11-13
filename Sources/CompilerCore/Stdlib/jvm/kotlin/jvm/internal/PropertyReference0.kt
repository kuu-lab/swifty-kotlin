package kotlin.jvm.internal

import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty0
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.jvm.internal.RuntimeProperty0Getter
import kotlin.reflect.jvm.internal.RuntimeProperty0Setter

abstract class PropertyReference0 protected constructor(
    owner: java.lang.Class<*>, name: String, signature: String, receiver: Any?, bound: Boolean
): RuntimeProperty(owner, name, signature, receiver, bound), KProperty0<Any?> {
    constructor(): this(Any::class.java, "", "", null, false)
    constructor(receiver: Any?): this(Any::class.java, "", "", receiver, true)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int):
        this(owner, name, signature, receiver, true)

    override fun invoke(): Any? = get()
    override fun getDelegate(): Any? = delegateZero()
    override val getter: KProperty0.Getter<Any?> get() = RuntimeProperty0Getter(this)
}

abstract class MutablePropertyReference0 protected constructor(
    owner: java.lang.Class<*>, name: String, signature: String, receiver: Any?, bound: Boolean
): PropertyReference0(owner, name, signature, receiver, bound), KMutableProperty0<Any?> {
    constructor(): this(Any::class.java, "", "", null, false)
    constructor(receiver: Any?): this(Any::class.java, "", "", receiver, true)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int):
        this(owner, name, signature, receiver, true)

    override val setter: KMutableProperty0.Setter<Any?> get() = RuntimeProperty0Setter(this)
}
