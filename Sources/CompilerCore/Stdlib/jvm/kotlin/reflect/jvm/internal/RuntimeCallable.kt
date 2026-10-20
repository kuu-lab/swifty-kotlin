package kotlin.reflect.jvm.internal
import kotlin.jvm.internal.*
import kotlin.reflect.*

internal class RuntimeType(private val metadata: RuntimeMetadata, private val type: Proto, private val parameters: List<Proto> = emptyList()): KType {
    override val annotations: List<Annotation> get() = emptyList()
    override val isMarkedNullable: Boolean get() = type.number(3) != 0
    override val classifier: KClassifier? get() {
        if (!type.has(6)) return null
        return ClassReference(loadMetadataType(metadata.string(type.number(6)), metadata.owner) as java.lang.Class<Any>)
    }
    override fun toString(): String = renderRuntimeType(metadata, type, parameters)
}
internal class RuntimeTypeParameter(private val metadata: RuntimeMetadata, private val node: Proto): KTypeParameter {
    override val name: String get() = metadata.string(node.number(2))
    override val isReified: Boolean get() = node.number(3) != 0
    override val upperBounds: List<KType> get() {
        val result = mutableListOf<KType>()
        for (bound in node.children(5)) result.add(RuntimeType(metadata, bound))
        return result
    }
}
internal class RuntimeClassType(private val owner: Any): KType {
    override val annotations: List<Annotation> get() = emptyList()
    override val isMarkedNullable: Boolean get() = false
    override val classifier: KClassifier get() = ClassReference(owner as java.lang.Class<Any>)
    override fun toString(): String = ClassReference(owner as java.lang.Class<Any>).qualifiedName ?: __jvmClassName(owner)
}
internal class RuntimeParameter(private val key: RuntimeCallable, override val index: Int, override val name: String?, override val isOptional: Boolean, override val annotations: List<Annotation>): KParameter {
    override fun equals(other: Any?): Boolean = other is RuntimeParameter && key == other.key && index == other.index
    override fun hashCode(): Int = key.hashCode() * 31 + index
}
internal fun adaptArgument(value: Any?, target: Any): Any? {
    if (value == null || __jvmClassInstance(target, value)) return value
    for (method in __jvmDeclaredMethods(__jvmClassOf(value))) {
        if (__jvmMethodName(method) == "unbox-impl") return __jvmMethodInvoke(method, value, arrayOf<Any?>())
    }
    return value
}
internal fun invokeMethod(method: Any, receiver: Any?, args: Array<Any?>): Any? {
    try { return __jvmMethodInvoke(method, receiver, args) }
    catch (failure: Throwable) {
        if (__jvmClassName(__jvmClassOf(failure)) == "java.lang.reflect.InvocationTargetException") throw __jvmInvocationCause(failure)!!
        throw failure
    }
}
internal fun boxResult(value: Any?, metadata: RuntimeMetadata, type: Proto): Any? {
    if (value === kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED) return value
    if (!type.has(6)) return value
    val name = metadata.string(type.number(6))
    if (name == "kotlin/Unit" && type.number(3) == 0) return Unit
    val klass = loadMetadataType(name, metadata.owner)
    if ((RuntimeMetadata(klass).root.number(1) and 8192) == 0 || value == null && type.number(3) != 0) return value
    if (value != null && __jvmClassInstance(klass, value)) return value
    for (method in __jvmDeclaredMethods(klass)) if (__jvmMethodName(method) == "box-impl") return invokeMethod(method, null, arrayOf(value))
    return value
}
open class RuntimeCallable(
    protected val ownerClass: Any,
    private val displayName: String,
    protected val signatureString: String,
    protected val boundReceiver: Any?,
    protected val bound: Boolean
): KCallable<Any?> {
    @kotlin.jvm.JvmField protected val receiver: Any? = boundReceiver
    protected val metadata: RuntimeMetadata get() = RuntimeMetadata(ownerClass)
    protected val node: Proto get() = metadata.callable(signatureString)
    protected val constructor: Boolean get() = signatureString.startsWith("<init>(")
    protected val method: Any get() {
        if (constructor) {
            for (constructor in __jvmDeclaredConstructors(ownerClass)) {
                if ("<init>" + executableDescriptor(constructor, true) == signatureString) { __jvmSetAccessible(constructor, true); return constructor }
            }
            throw IllegalStateException("Missing reflected JVM constructor: $signatureString")
        }
        return findMethod(ownerClass, signatureString)
    }
    override val name: String get() = displayName
    override val isSuspend: Boolean get() = (node.number(9) and 8192) != 0
    override val returnType: KType get() = if (displayName == "<init>") RuntimeClassType(ownerClass) else RuntimeType(metadata, metadata.type(node, 3, 7), node.children(4))
    override val typeParameters: List<KTypeParameter> get() {
        val result = mutableListOf<KTypeParameter>()
        for (parameter in node.children(4)) result.add(RuntimeTypeParameter(metadata, parameter))
        return result
    }
    override val annotations: List<Annotation> get() = if (__jvmClassIsAnnotation(ownerClass) && displayName == "<init>") emptyList() else visibleAnnotations(method)
    override val parameters: List<KParameter> get() {
        val result = mutableListOf<KParameter>()
        if (__jvmClassIsAnnotation(ownerClass) && displayName == "<init>") {
            val result = mutableListOf<KParameter>()
            for (parameter in node.children(2)) {
                val name = metadata.string(parameter.number(2))
                var optional = false
                for (method in __jvmDeclaredMethods(ownerClass)) if (__jvmMethodName(method) == name) optional = __jvmMethodDefault(method) != null
                result.add(RuntimeParameter(this, result.size, name, optional, emptyList()))
            }
            return result
        }
        val method = method
        val instance = !constructor && (__jvmExecutableModifiers(method) and 8) == 0
        if (instance && !bound) result.add(RuntimeParameter(this, 0, null, false, emptyList()))
        val declarations = node.children(if (displayName == "<init>") 2 else 6)
        val annotations = __jvmExecutableParamAnnotations(method)
        val receiverOffset = if (node.has(5)) 1 else 0
        if (receiverOffset == 1 && !bound) result.add(RuntimeParameter(this, result.size, null, false, if (annotations.size > 0) expandAnnotations(annotations[0]) else emptyList()))
        var index = 0
        while (index < declarations.size) {
            val parameter = declarations[index]
            val javaIndex = index + receiverOffset
            result.add(RuntimeParameter(this, result.size, metadata.string(parameter.number(2)), (parameter.number(1) and 2) != 0, if (javaIndex < annotations.size) expandAnnotations(annotations[javaIndex]) else emptyList()))
            index++
        }
        return result
    }
    protected open fun resultType(): Proto {
        if (displayName != "<init>") return metadata.type(node, 3, 7)
        return Proto(emptyList())
    }
    override fun call(vararg args: Any?): Any? = callArray(args)
    open fun callArray(args: Array<out Any?>, unwrapException: Boolean = false): Any? {
        if (__jvmClassIsAnnotation(ownerClass) && displayName == "<init>") {
            val values = mutableMapOf<String, Any?>()
            val parameters = parameters
            if (args.size != parameters.size) throw IllegalArgumentException("Wrong annotation constructor arity")
            for (parameter in parameters) values[parameter.name!!] = args[parameter.index]
            return constructAnnotation(ownerClass, values)
        }
        val method = method
        val instance = !constructor && (__jvmExecutableModifiers(method) and 8) == 0
        var offset = 0
        val receiver = if (instance) { if (bound) boundReceiver else args[offset++] } else null
        val parameterTypes = __jvmExecutableParams(method)
        val actual = arrayOfNulls<Any?>(parameterTypes.size)
        var index = 0
        if (bound && !instance && !constructor) { actual[0] = adaptArgument(boundReceiver, parameterTypes[0]); index = 1 }
        if (args.size - offset != parameterTypes.size - index) throw IllegalArgumentException("Callable expects ${parameterTypes.size} arguments")
        while (index < parameterTypes.size) { actual[index] = adaptArgument(args[offset++], parameterTypes[index]); index++ }
        val value: Any? = if (constructor) __jvmConstructorInvoke(method, actual) else if (unwrapException) invokeMethod(method, receiver, actual) else __jvmMethodInvoke(method, receiver, actual)
        if (displayName == "<init>" && !constructor) {
            for (box in __jvmDeclaredMethods(ownerClass)) if (__jvmMethodName(box) == "box-impl") return invokeMethod(box, null, arrayOf(value))
        }
        return if (constructor) value else boxResult(value, metadata, resultType())
    }
    fun reflectedElement(): Any = method
    fun callSuspending(args: Array<out Any?>, completion: kotlin.coroutines.Continuation<Any?>): Any? {
        if (!isSuspend) return callArray(args)
        val metadata = metadata
        val returnNode = resultType()
        val forwarding = object: kotlin.coroutines.Continuation<Any?> {
            override val context: kotlin.coroutines.CoroutineContext get() = completion.context
            override fun resumeWith(result: kotlin.Result<Any?>) {
                val raw = __jvmResultValue(result)
                val value = if (raw is kotlin.Result.Failure) raw else boxResult(raw, metadata, returnNode)
                __jvmResume(completion, value)
            }
        }
        val actual = arrayOfNulls<Any?>(args.size + 1)
        var index = 0
        while (index < args.size) { actual[index] = args[index]; index++ }
        actual[index] = forwarding
        return callArray(actual)
    }
    override fun callBy(args: Map<KParameter, Any?>): Any? {
        if (__jvmClassIsAnnotation(ownerClass) && displayName == "<init>") {
            val values = mutableMapOf<String, Any?>()
            for (parameter in parameters) if (args.containsKey(parameter)) values[parameter.name!!] = args[parameter]
            return constructAnnotation(ownerClass, values)
        }
        val parameters = parameters
        val values = arrayOfNulls<Any?>(parameters.size)
        var missing = false
        for (parameter in parameters) {
            if (args.containsKey(parameter)) values[parameter.index] = args[parameter]
            else if (parameter.isOptional) missing = true
            else throw IllegalArgumentException("Missing required argument: ${parameter.name}")
        }
        if (!missing) return callArray(values)
        return callDefault(args, parameters, values)
    }
    private fun callDefault(args: Map<KParameter, Any?>, parameters: List<KParameter>, values: Array<Any?>): Any? {
        val method = method
        val originalTypes = __jvmExecutableParams(method)
        val instance = !constructor && (__jvmExecutableModifiers(method) and 8) == 0
        val receiverOffset = if (instance && !bound) 1 else 0
        val extensionOffset = if (node.has(5)) 1 else 0
        val valueParameters = node.children(if (displayName == "<init>") 2 else 6)
        val maskCount = (valueParameters.size + 31) / 32
        val actual = arrayOfNulls<Any?>(originalTypes.size + (if (instance) 1 else 0) + maskCount + 1)
        var index = 0
        if (instance) actual[index++] = if (bound) boundReceiver else values[0]
        if (bound && !instance && !constructor) actual[index++] = boundReceiver
        var input = receiverOffset
        while (input < values.size) {
            val target = originalTypes[index - (if (instance) 1 else 0)]
            val parameter = parameters[input]
            actual[index++] = if (args.containsKey(parameter)) adaptArgument(values[input], target) else defaultValue(target)
            input++
        }
        var maskIndex = 0
        while (maskIndex < maskCount) {
            var mask = 0
            var bit = 0
            while (bit < 32) {
                val parameterIndex = receiverOffset + (if (bound) 0 else extensionOffset) + maskIndex * 32 + bit
                if (parameterIndex < parameters.size && !args.containsKey(parameters[parameterIndex])) mask = mask or (1 shl bit)
                bit++
            }
            actual[index++] = mask
            maskIndex++
        }
        // Arity alone cannot distinguish overloaded default dispatchers.
        val originalDescriptor = executableDescriptor(method, constructor)
        var expectedDescriptor = "("
        if (instance) expectedDescriptor += classDescriptor(ownerClass)
        expectedDescriptor += originalDescriptor.substringAfter("(").substringBefore(")")
        var mask = 0
        while (mask < maskCount) { expectedDescriptor += "I"; mask++ }
        expectedDescriptor += if (constructor) "Lkotlin/jvm/internal/DefaultConstructorMarker;)V" else "Ljava/lang/Object;)" + originalDescriptor.substringAfter(")")
        if (constructor) {
            for (candidate in __jvmDeclaredConstructors(ownerClass)) {
                if (executableDescriptor(candidate, true) == expectedDescriptor) {
                    __jvmSetAccessible(candidate, true)
                    return __jvmConstructorInvoke(candidate, actual)
                }
            }
        } else {
            val name = signatureString.substringBefore("(") + "$" + "default"
            for (candidate in __jvmDeclaredMethods(ownerClass)) {
                if (__jvmMethodName(candidate) == name && executableDescriptor(candidate) == expectedDescriptor) {
                    __jvmSetAccessible(candidate, true)
                    return boxResult(__jvmMethodInvoke(candidate, null, actual), metadata, resultType())
                }
            }
        }
        throw IllegalStateException("Missing default argument dispatcher")
    }
    override fun equals(other: Any?): Boolean = other is RuntimeCallable && ownerClass == other.ownerClass && signatureString == other.signatureString && bound == other.bound && boundReceiver == other.boundReceiver
    override fun hashCode(): Int = ownerClass.hashCode() * 31 + signatureString.hashCode()
    override fun toString(): String = "fun $displayName"
}
internal fun defaultValue(type: Any): Any? = when (__jvmClassName(type)) {
    "boolean" -> false
    "byte" -> 0.toByte()
    "short" -> 0.toShort()
    "char" -> 0.toChar()
    "int" -> 0
    "long" -> 0L
    "float" -> 0.0f
    "double" -> 0.0
    else -> null
}

open class RuntimeFunction(owner: Any, name: String, signature: String, receiver: Any?, bound: Boolean): RuntimeCallable(owner, name, signature, receiver, bound), KFunction<Any?> {
    override val isInline: Boolean get() = (node.number(9) and 1024) != 0
    override val isOperator: Boolean get() = (node.number(9) and 256) != 0
    override val isInfix: Boolean get() = (node.number(9) and 512) != 0
    override val isExternal: Boolean get() = (node.number(9) and 4096) != 0
}
