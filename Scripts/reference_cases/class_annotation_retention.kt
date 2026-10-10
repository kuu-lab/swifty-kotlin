package retentioncases

import kotlin.annotation.Retention as Keep
import kotlin.annotation.AnnotationRetention.BINARY as BinaryOnly
import kotlin.annotation.AnnotationRetention.BINARY as RUNTIME
import retentioncases.Holder as Alias
import kotlin.reflect.KClass
import kotlin.reflect.typeOf
import kotlin.reflect.full.findAnnotation

@Keep((AnnotationRetention.SOURCE)) annotation class SourceMark
@Keep(value = ((BinaryOnly))) annotation class BinaryMark
@Keep(((AnnotationRetention.RUNTIME))) annotation class RuntimeMark
annotation class DefaultMark
@Keep(AnnotationRetention.BINARY) private annotation class PrivateBinary
@Keep(AnnotationRetention.SOURCE) private annotation class PrivateSource
@Keep((AnnotationRetention.RUNTIME)) annotation class QualifiedRuntime
@Keep(RUNTIME) annotation class ImportedBinary

class Holder {
    @Keep(AnnotationRetention.SOURCE) annotation class Source
    @Keep(AnnotationRetention.BINARY) annotation class Binary
    annotation class Runtime
}
typealias BinaryAlias = Alias.Binary
typealias BinaryAliasChain = BinaryAlias
class RelativeContainer {
    @Keep(AnnotationRetention.SOURCE) annotation class Source
    @Keep(AnnotationRetention.BINARY) annotation class Binary
}
@Alias.Binary @Alias.Source @RelativeContainer.Source @RelativeContainer.Binary @QualifiedRuntime @ImportedBinary @Alias.Runtime
class NestedTagged
@BinaryAliasChain @LateSource @LateRuntime class AliasTagged
@Keep(AnnotationRetention.SOURCE) annotation class LateSource
annotation class LateRuntime
@Keep(AnnotationRetention.BINARY) annotation class Mark
class Shadow {
    annotation class Mark
    @Mark class Tagged
}
@QualifiedRuntime @ImportedBinary fun marked() = 1

@SourceMark @BinaryMark @RuntimeMark @DefaultMark @PrivateBinary @PrivateSource
class Tagged
@SourceMark @BinaryMark @RuntimeMark @DefaultMark
object Singleton
@SourceMark @BinaryMark @RuntimeMark @DefaultMark
open class Base
class Derived : Base()

fun names(value: KClass<*>): String = value.annotations.map { it.annotationClass.simpleName }.sortedBy { it }.joinToString(",")

fun main() {
    val expected = "DefaultMark,RuntimeMark"
    check(names(Tagged::class) == expected)
    val handle = Tagged::class
    check(names(handle) == expected && names(handle) == expected)
    val instance = Tagged()
    check(names(instance::class) == expected)
    check(names(Singleton::class) == expected && names(Singleton::class) == expected)
    val base = Derived::class.supertypes.first().classifier as KClass<*>
    check(names(base) == expected)
    val classifier = typeOf<Base>().classifier as KClass<*>
    check(names(classifier) == expected)
    check(Tagged::class.findAnnotation<BinaryMark>() == null)
    check(Tagged::class.findAnnotation<SourceMark>() == null)
    check(Tagged::class.findAnnotation<DefaultMark>() != null)
    check(names(NestedTagged::class) == "QualifiedRuntime,Runtime")
    check(names(AliasTagged::class) == "LateRuntime")
    check(names(Shadow.Tagged::class) == "Mark")
    check(::marked.annotations.map { it.annotationClass.simpleName }.joinToString(",") == "QualifiedRuntime")
    println("class:literal:variable:constructed:$expected")
    println("object:supertype:classifier:$expected")
    println("lookup:runtime-only")
    println("aliases:nested:shadowing:runtime-only")
    println("callable:QualifiedRuntime")
}
