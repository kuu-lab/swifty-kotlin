package kotlin.jvm.internal

open class MutablePropertyReference1Impl: MutablePropertyReference1 {
    constructor(owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, null, false)
    constructor(receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): super(owner, name, signature, receiver, true)
    override fun get(receiver: Any?): Any? = readOne(receiver)
    override fun set(receiver: Any?, value: Any?) { writeOne(receiver, value) }
}
