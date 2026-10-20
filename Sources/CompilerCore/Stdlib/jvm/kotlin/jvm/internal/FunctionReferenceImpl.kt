package kotlin.jvm.internal
import kotlin.reflect.jvm.internal.RuntimeFunction
open class FunctionReferenceImpl protected constructor(override val arity: Int, receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int, bound: Boolean): RuntimeFunction(owner, name, signature, receiver, bound), FunctionBase<Any?> {
    constructor(arity: Int, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): this(arity, null, owner, name, signature, flags, false)
    constructor(arity: Int, receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): this(arity, receiver, owner, name, signature, flags, true)
}
open class AdaptedFunctionReference protected constructor(override val arity: Int, receiver: Any?, private val owner: java.lang.Class<*>, private val name: String, private val signature: String, private val flags: Int, private val bound: Boolean): FunctionBase<Any?> {
    @kotlin.jvm.JvmField protected val receiver: Any? = receiver
    constructor(arity: Int, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): this(arity, null, owner, name, signature, flags, false)
    constructor(arity: Int, receiver: Any?, owner: java.lang.Class<*>, name: String, signature: String, flags: Int): this(arity, receiver, owner, name, signature, flags, true)
    override fun equals(other: Any?): Boolean = other is AdaptedFunctionReference && arity == other.arity && receiver == other.receiver && owner == other.owner && name == other.name && signature == other.signature && flags == other.flags
    override fun hashCode(): Int = owner.hashCode() * 31 + signature.hashCode()
}
