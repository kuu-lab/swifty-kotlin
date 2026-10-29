package kotlin.reflect
interface KAnnotatedElement { val annotations: List<Annotation> }
interface KCallable<out R>: KAnnotatedElement {
    val name: String
    val parameters: List<KParameter>
    val returnType: KType
    fun call(vararg args: Any?): R
    fun callBy(args: Map<KParameter, Any?>): R
}
interface KFunction<out R>: KCallable<R> { val isInline: Boolean; val isOperator: Boolean; val isSuspend: Boolean }
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
interface KProperty0<out V>: KProperty<V> {
    fun get(): V
    fun getDelegate(): Any?
    operator fun invoke(): V
    override val getter: Getter<V>
    interface Getter<out V>: KProperty.Getter<V> { operator fun invoke(): V }
}
interface KProperty1<T, out V>: KProperty<V> { fun get(receiver: T): V }
interface KMutableProperty0<V>: KProperty0<V>, KMutableProperty<V> {
    fun set(value: V)
    override val setter: Setter<V>
    interface Setter<V>: KMutableProperty.Setter<V> { operator fun invoke(value: V) }
}
interface KMutableProperty1<T, V>: KProperty1<T, V>, KMutableProperty<V> { fun set(receiver: T, value: V) }
interface KClassifier
interface KClass<T>: KAnnotatedElement, KClassifier {
    val simpleName: String?
    val qualifiedName: String?
    val members: Collection<KCallable<*>>
    val constructors: Collection<KFunction<T>>
    val nestedClasses: Collection<KClass<*>>
    val objectInstance: T?
    val isFinal: Boolean; val isOpen: Boolean; val isAbstract: Boolean; val isSealed: Boolean
    val isData: Boolean; val isInner: Boolean; val isCompanion: Boolean; val isFun: Boolean; val isValue: Boolean
    fun isInstance(value: Any?): Boolean
}
interface KType: KAnnotatedElement { val classifier: KClassifier?; val isMarkedNullable: Boolean }
interface KParameter: KAnnotatedElement { val name: String?; val index: Int; val isOptional: Boolean }
