package kotlin.reflect.jvm.internal
import kotlin.jvm.internal.*
import kotlin.reflect.*
open class RuntimeProperty(owner: Any, name: String, signature: String, receiver: Any?, bound: Boolean): RuntimeCallable(owner, name, signature, receiver, bound), KProperty<Any?> {
    private val propertyNode: Proto get() = metadata.property(name)
    override val isLateinit: Boolean get() = (propertyNode.number(11) and 4096) != 0
    override val isConst: Boolean get() = (propertyNode.number(11) and 2048) != 0
    protected override fun resultType(): Proto = metadata.type(propertyNode, 3, 9)
    override val returnType: KType get() = RuntimeType(metadata, metadata.type(propertyNode, 3, 9), propertyNode.children(4))
    override val annotations: List<Annotation> get() {
        val signature = metadata.propertySignature(propertyNode, 2)
        return if (signature.isEmpty()) emptyList() else visibleAnnotations(findMethod(ownerClass, signature))
    }
    fun readZero(): Any? = boxResult(callArray(arrayOf<Any?>(), true), metadata, metadata.type(propertyNode, 3, 9))
    fun readOne(receiver: Any?): Any? = boxResult(callArray(arrayOf(receiver), true), metadata, metadata.type(propertyNode, 3, 9))
    private fun write(receiver: Any?, value: Any?) {
        val signature = metadata.propertySignature(propertyNode, 4)
        if (signature.isEmpty()) throw IllegalStateException("Property is immutable")
        val method = findMethod(ownerClass, signature)
        val types = __jvmExecutableParams(method)
        if ((__jvmExecutableModifiers(method) and 8) != 0) {
            if (types.size == 1) invokeMethod(method, null, arrayOf(adaptArgument(value, types[0])))
            else invokeMethod(method, null, arrayOf(adaptArgument(receiver, types[0]), adaptArgument(value, types[1])))
        } else invokeMethod(method, receiver, arrayOf(adaptArgument(value, types[0])))
    }
    fun writeZero(value: Any?) { write(boundReceiver, value) }
    fun writeOne(receiver: Any?, value: Any?) { write(receiver, value) }
}

internal fun propertyReference(owner: Any, name: String, signature: String, mutable: Boolean): KProperty1<Any?, Any?> = if (mutable) MutablePropertyReference1Impl(owner as java.lang.Class<*>, name, signature, 0) else PropertyReference1Impl(owner as java.lang.Class<*>, name, signature, 0)
