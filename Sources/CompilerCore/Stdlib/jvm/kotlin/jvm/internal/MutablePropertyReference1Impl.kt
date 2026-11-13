package kotlin.jvm.internal

import kotlin.reflect.KDeclarationContainer

open class MutablePropertyReference1Impl: MutablePropertyReference1 {
    constructor(owner: KDeclarationContainer, name: String, signature: String) :
        super((owner as ClassReference<*>).jClass, name, signature, null, false)
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(receiver: Any?): Any? = readOne(receiver)
    override fun set(receiver: Any?, value: Any?) { writeOne(receiver, value) }
}
