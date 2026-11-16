package kotlin.jvm.internal
import kotlin.reflect.*
open class MutablePropertyReference0Impl: MutablePropertyReference0 {
    constructor(owner: KDeclarationContainer, name: String, signature: String) :
        super((owner as ClassReference<*>).jClass, name, signature, null, false)
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(): Any? = readZero()
    override fun set(value: Any?) { writeZero(value) }
}
