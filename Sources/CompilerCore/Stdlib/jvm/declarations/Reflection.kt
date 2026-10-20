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
interface KProperty<out V>: KCallable<V> { val isLateinit: Boolean; val isConst: Boolean }
interface KMutableProperty<V>: KProperty<V>
interface KProperty0<out V>: KProperty<V> { fun get(): V }
interface KProperty1<T, out V>: KProperty<V> { fun get(receiver: T): V }
interface KMutableProperty0<V>: KProperty0<V>, KMutableProperty<V> { fun set(value: V) }
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