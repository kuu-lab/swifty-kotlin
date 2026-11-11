package kotlin.jvm.internal

import kotlin.reflect.KMutableProperty
import kotlin.reflect.KMutableProperty1
import kotlin.reflect.jvm.internal.RuntimeProperty
import kotlin.reflect.jvm.internal.RuntimeProperty1Setter

public abstract class MutablePropertyReference1 protected constructor(
    owner: java.lang.Class<*>, name: String, signature: String, receiver: Any?, bound: Boolean
) : RuntimeProperty(owner, name, signature, receiver, bound), KMutableProperty1<Any?, Any?> {
    public constructor() : this(Any::class.java, "", "", null, false)
    public constructor(receiver: Any?) : this(Any::class.java, "", "", receiver, true)
    public constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int) :
        this(owner, name, signature, receiver, true)

    override fun invoke(receiver: Any?): Any? = get(receiver)
    override val setter: KMutableProperty.Setter<Any?> get() = RuntimeProperty1Setter(this)
}
