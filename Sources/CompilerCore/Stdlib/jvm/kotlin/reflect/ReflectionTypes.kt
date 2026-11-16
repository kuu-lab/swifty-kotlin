package kotlin.reflect
interface KAnnotatedElement { val annotations: List<Annotation> }
interface KCallable<out R>: KAnnotatedElement {
    val isSuspend: Boolean
    val typeParameters: List<KTypeParameter>
    fun callBy(args: Map<KParameter, Any?>): R
    val name: String
    val parameters: List<KParameter>
    val returnType: KType
    fun call(vararg args: Any?): R
}
interface KFunction<out R>: KCallable<R>, kotlin.Function<R> { val isInline: Boolean; val isOperator: Boolean; val isInfix: Boolean; val isExternal: Boolean; override val isSuspend: Boolean }
interface KProperty<out V>: KCallable<V> {
    val isLateinit: Boolean
    val isConst: Boolean
    val getter: Getter<V>
    interface Accessor<out V> { val property: KProperty<V> }
    interface Getter<out V>: Accessor<V>, KFunction<V>
}
interface KMutableProperty<V>: KProperty<V> {
    val setter: Setter<V>
    interface Setter<V>: KProperty.Accessor<V>, KFunction<Unit> { override val property: KProperty<V> }
}
interface KProperty0<out V>: KProperty<V>, kotlin.jvm.functions.Function0<V> {
    fun get(): V
    fun getDelegate(): Any?
    override val getter: Getter<V>
    interface Getter<out V>: KProperty.Getter<V>, kotlin.jvm.functions.Function0<V>
}
interface KProperty1<T, out V>: KProperty<V>, kotlin.jvm.functions.Function1<T, V> { fun get(receiver: T): V }
interface KProperty2<D, E, out V>: KProperty<V>, kotlin.jvm.functions.Function2<D, E, V> {
    fun get(receiver1: D, receiver2: E): V
    fun getDelegate(receiver1: D, receiver2: E): Any?
    override val getter: Getter<D, E, V>
    interface Getter<D, E, out V>: KProperty.Getter<V>, kotlin.jvm.functions.Function2<D, E, V>
}
interface KMutableProperty0<V>: KProperty0<V>, KMutableProperty<V> {
    fun set(value: V)
    override val setter: Setter<V>
    interface Setter<V>: KMutableProperty.Setter<V>, kotlin.jvm.functions.Function1<V, Unit>
}
interface KMutableProperty1<T, V>: KProperty1<T, V>, KMutableProperty<V> { fun set(receiver: T, value: V) }
interface KClassifier
interface KDeclarationContainer {
    val members: Collection<KCallable<*>>
}

interface KClass<T>: KAnnotatedElement, KClassifier, KDeclarationContainer {
    val simpleName: String?
    val qualifiedName: String?
    val constructors: Collection<KFunction<T>>
    val nestedClasses: Collection<KClass<*>>
    val objectInstance: T?
    val isFinal: Boolean; val isOpen: Boolean; val isAbstract: Boolean; val isSealed: Boolean
    val isData: Boolean; val isInner: Boolean; val isCompanion: Boolean; val isFun: Boolean; val isValue: Boolean
    fun isInstance(value: Any?): Boolean
}
interface KType: KAnnotatedElement {
    val classifier: KClassifier?
    val arguments: List<KTypeProjection>
    val isMarkedNullable: Boolean
}

enum class KVariance { INVARIANT, IN, OUT }

data class KTypeProjection(val variance: KVariance?, val type: KType?) {
    init {
        require((variance == null) == (type == null)) {
            "A star projection requires both variance and type to be absent."
        }
    }

    companion object {
        @JvmField val STAR: KTypeProjection = KTypeProjection(null, null)
        @JvmStatic fun invariant(type: KType): KTypeProjection = KTypeProjection(KVariance.INVARIANT, type)
        @JvmStatic fun contravariant(type: KType): KTypeProjection = KTypeProjection(KVariance.IN, type)
        @JvmStatic fun covariant(type: KType): KTypeProjection = KTypeProjection(KVariance.OUT, type)
    }
}

interface KParameter: KAnnotatedElement { val name: String?; val index: Int; val isOptional: Boolean }
interface KTypeParameter: KClassifier { val name: String; val isReified: Boolean; val upperBounds: List<KType> }
