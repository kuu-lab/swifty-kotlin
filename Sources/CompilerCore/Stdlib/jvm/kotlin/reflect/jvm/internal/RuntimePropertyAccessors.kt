package kotlin.reflect.jvm.internal

import kotlin.reflect.*
import kotlin.jvm.internal.*

internal class RuntimePropertyGetter(private val owner: RuntimeProperty): KProperty.Getter<Any?> {
    override val property: KProperty<Any?> get() = owner
    override val name: String get() = "<get-" + owner.name + ">"
    override val parameters: List<KParameter> get() = owner.parameters
    override val returnType: KType get() = owner.returnType
    override val annotations: List<Annotation> get() = owner.annotations
    override val typeParameters: List<KTypeParameter> get() = emptyList()
    override val isSuspend: Boolean get() = false
    override val isInline: Boolean get() = false
    override val isOperator: Boolean get() = false
    override val isInfix: Boolean get() = false
    override val isExternal: Boolean get() = false
    override fun call(vararg args: Any?): Any? = owner.callArray(args)
    override fun callBy(args: Map<KParameter, Any?>): Any? = owner.callBy(args)
}

internal class RuntimeProperty0Getter(private val owner: RuntimeProperty): KProperty0.Getter<Any?> {
    override val property: KProperty<Any?> get() = owner
    override val name: String get() = "<get-" + owner.name + ">"
    override val parameters: List<KParameter> get() = owner.parameters
    override val returnType: KType get() = owner.returnType
    override val annotations: List<Annotation> get() = owner.annotations
    override val typeParameters: List<KTypeParameter> get() = emptyList()
    override val isSuspend: Boolean get() = false
    override val isInline: Boolean get() = false
    override val isOperator: Boolean get() = false
    override val isInfix: Boolean get() = false
    override val isExternal: Boolean get() = false
    override fun call(vararg args: Any?): Any? = owner.callArray(args)
    override fun callBy(args: Map<KParameter, Any?>): Any? = owner.callBy(args)
    override fun invoke(): Any? = owner.readZero()
}

internal class RuntimeProperty0Setter(private val owner: RuntimeProperty): KMutableProperty0.Setter<Any?> {
    override val property: KProperty<Any?> get() = owner
    override val name: String get() = "<set-" + owner.name + ">"
    override val parameters: List<KParameter> get() = listOf(RuntimeParameter(owner, 0, null, false, emptyList()))
    override val returnType: KType get() = RuntimeClassType(__jvmClassOf(Unit))
    override val annotations: List<Annotation> get() = emptyList()
    override val typeParameters: List<KTypeParameter> get() = emptyList()
    override val isSuspend: Boolean get() = false
    override val isInline: Boolean get() = false
    override val isOperator: Boolean get() = false
    override val isInfix: Boolean get() = false
    override val isExternal: Boolean get() = false
    override fun call(vararg args: Any?) {
        if (args.size != 1) throw IllegalArgumentException("Setter expects one argument.")
        owner.writeZero(args[0])
    }
    override fun callBy(args: Map<KParameter, Any?>) {
        val parameter = parameters[0]
        if (!args.containsKey(parameter)) throw IllegalArgumentException("Missing setter argument.")
        owner.writeZero(args[parameter])
    }
    override fun invoke(value: Any?) { owner.writeZero(value) }
}

internal class RuntimeProperty1Setter(private val owner: RuntimeProperty): KMutableProperty.Setter<Any?> {
    override val property: KProperty<Any?> get() = owner
    override val name: String get() = "<set-" + owner.name + ">"
    override val parameters: List<KParameter> get() {
        val result = owner.parameters.toMutableList()
        result.add(RuntimeParameter(owner, result.size, null, false, emptyList()))
        return result
    }
    override val returnType: KType get() = RuntimeClassType(__jvmClassOf(Unit))
    override val annotations: List<Annotation> get() = emptyList()
    override val typeParameters: List<KTypeParameter> get() = emptyList()
    override val isSuspend: Boolean get() = false
    override val isInline: Boolean get() = false
    override val isOperator: Boolean get() = false
    override val isInfix: Boolean get() = false
    override val isExternal: Boolean get() = false
    override fun call(vararg args: Any?) {
        if (args.size != 2) throw IllegalArgumentException("Setter expects two arguments.")
        owner.writeOne(args[0], args[1])
    }
    override fun callBy(args: Map<KParameter, Any?>) {
        val parameters = parameters
        if (parameters.size != 2 || !args.containsKey(parameters[0]) || !args.containsKey(parameters[1])) {
            throw IllegalArgumentException("Missing setter arguments.")
        }
        owner.writeOne(args[parameters[0]], args[parameters[1]])
    }
}
