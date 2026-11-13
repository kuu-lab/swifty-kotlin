package kotlin.jvm.internal

import kotlin.reflect.KDeclarationContainer
import kotlin.reflect.jvm.internal.RuntimeFunction

open class FunctionReference private constructor(
    override val arity: Int, receiver: Any?, bound: Boolean
): RuntimeFunction(Any::class.java, "", "", receiver, bound), FunctionBase<Any?> {
    constructor(arity: Int): this(arity, null, false)
    constructor(arity: Int, receiver: Any?): this(arity, receiver, true)

    public open fun getOwner(): KDeclarationContainer? = null
    public open fun getSignature(): String = ""
    override val ownerClass: Any get() = (getOwner() as? ClassReference<*>)?.jClass ?: Any::class.java
    override val signatureString: String get() = getSignature()
}
