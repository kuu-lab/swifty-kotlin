package kotlin.reflect.jvm.internal
import kotlin.jvm.internal.*
import kotlin.reflect.*
open class RuntimeProperty(owner: Any, name: String, signature: String, receiver: Any?, bound: Boolean): RuntimeCallable(owner, name, signature, receiver, bound), KProperty<Any?> {
    private val propertyNode: Proto get() = metadata.property(name)
    override val isLateinit: Boolean get() = (propertyNode.number(11) and 4096) != 0
    override val isConst: Boolean get() = (propertyNode.number(11) and 2048) != 0
    protected override fun resultType(): Proto = metadata.type(propertyNode, 3, 9)
    override val returnType: KType get() = RuntimeType(metadata, metadata.type(propertyNode, 3, 9), propertyNode.children(4))
    override val parameters: List<KParameter> get() {
        if (!isConst) return super.parameters
        if (bound || !metadata.isClass) return emptyList()
        return listOf(RuntimeParameter(this, 0, null, false, emptyList()))
    }
    override val annotations: List<Annotation> get() {
        val signature = metadata.propertySignature(propertyNode, 2)
        return if (signature.isEmpty()) emptyList() else visibleAnnotations(findMethod(ownerClass, signature))
    }
    fun readZero(): Any? = boxResult(callArray(arrayOf<Any?>(), true), metadata, metadata.type(propertyNode, 3, 9))
    fun readOne(receiver: Any?): Any? = boxResult(callArray(arrayOf(receiver), true), metadata, metadata.type(propertyNode, 3, 9))
    private fun classCompanionFieldOwner(): Any? {
        if ((metadata.root.number(1) and 448) != 384) return null
        val outerName = __jvmClassName(ownerClass).substringBeforeLast("$")
        val outer = __jvmLoadClass(outerName, false, __jvmClassLoader(ownerClass))
        return if ((__jvmClassModifiers(outer) and 512) == 0) outer else null
    }
    override fun callArray(args: Array<out Any?>, unwrapException: Boolean): Any? {
        if (!isConst) return super.callArray(args, unwrapException)
        val outer = classCompanionFieldOwner()
        // Logical instance parameters remain present for static object fields.
        val arity = if (!bound && outer != null) 1 else 0
        if (args.size != arity) throw IllegalArgumentException("Callable expects $arity arguments, but ${args.size} were provided.")
        val fieldOwner = outer ?: ownerClass
        val signature = propertyNode.child(100).child(1)
        val fieldName = if (signature.has(1)) metadata.string(signature.number(1)) else name
        for (field in __jvmDeclaredFields(fieldOwner)) {
            if (__jvmFieldName(field) == fieldName && (__jvmFieldModifiers(field) and 8) != 0) {
                __jvmSetAccessible(field, true)
                return boxResult(__jvmFieldGet(field, null), metadata, resultType())
            }
        }
        throw IllegalStateException("Missing reflected JVM const field: $fieldName")
    }
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
