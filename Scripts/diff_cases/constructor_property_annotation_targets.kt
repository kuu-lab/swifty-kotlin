@Target(AnnotationTarget.PROPERTY)
annotation class PropertyOnly

@Target(AnnotationTarget.FIELD)
annotation class FieldOnly

@Target(AnnotationTarget.VALUE_PARAMETER)
annotation class ParamOnly

sealed class PartData(
    @Deprecated("Use release instead", level = DeprecationLevel.WARNING)
    public val dispose: () -> Unit,
)

class AnnotatedProperties(
    @Deprecated("Use immutable instead") val legacyVal: Int,
    @Deprecated("Use mutable instead") var legacyVar: Int,
    @PropertyOnly val propertyValue: Int,
    @FieldOnly var fieldValue: Int,
    @ParamOnly val parameterValue: Int,
    @property:PropertyOnly val explicitProperty: Int,
    @field:FieldOnly var explicitField: Int,
    @param:ParamOnly val explicitParameter: Int,
)

fun main() {
    val properties = AnnotatedProperties(1, 2, 3, 4, 5, 6, 7, 8)
    println(properties.legacyVal)
    println(properties.legacyVar)
    properties.legacyVar = 20
    println(properties.legacyVar)
    println(properties.propertyValue)
    println(properties.fieldValue)
    properties.fieldValue = 40
    println(properties.fieldValue)
    println(properties.parameterValue)
    println(properties.explicitProperty)
    println(properties.explicitField)
    println(properties.explicitParameter)
}
