package kotlin.jvm.internal

import kotlin.reflect.KProperty1
import kotlin.reflect.jvm.internal.RuntimeProperty

abstract class PropertyReference1 protected constructor(
    owner: java.lang.Class<*>, name: String, signature: String, receiver: Any?, bound: Boolean
): RuntimeProperty(owner, name, signature, receiver, bound), KProperty1<Any?, Any?> {
    constructor(): this(Any::class.java, "", "", null, false)
    constructor(receiver: Any?): this(Any::class.java, "", "", receiver, true)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int):
        this(owner, name, signature, receiver, true)

    override fun invoke(receiver: Any?): Any? = get(receiver)
}
