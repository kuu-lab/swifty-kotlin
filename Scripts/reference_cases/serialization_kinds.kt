@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

import kotlinx.serialization.descriptors.SerialKind as Kind
import kotlinx.serialization.descriptors.PrimitiveKind as Primitive
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.descriptors.PolymorphicKind

fun kinds(): List<Kind> = listOf(
    Kind.ENUM, Kind.CONTEXTUAL,
    Primitive.BOOLEAN, Primitive.BYTE, Primitive.CHAR, Primitive.SHORT,
    Primitive.INT, Primitive.LONG, Primitive.FLOAT, Primitive.DOUBLE, Primitive.STRING,
    StructureKind.CLASS, StructureKind.LIST, StructureKind.MAP, StructureKind.OBJECT,
    PolymorphicKind.SEALED, PolymorphicKind.OPEN
)

fun main() {
    val names = listOf("ENUM", "CONTEXTUAL", "BOOLEAN", "BYTE", "CHAR", "SHORT",
        "INT", "LONG", "FLOAT", "DOUBLE", "STRING", "CLASS", "LIST", "MAP", "OBJECT", "SEALED", "OPEN")
    val values = kinds()
    check(values.size == 17)
    for (index in values.indices) {
        val kind = values[index]
        check(kind.toString() == names[index])
        check(kind.hashCode() == names[index].hashCode())
        check(kind === kinds()[index])
        val family = when (kind) {
            is Primitive -> "primitive"
            is StructureKind -> "structure"
            is PolymorphicKind -> "polymorphic"
            else -> "serial"
        }
        println("${kind}|${kind.hashCode()}|${family}|${kind === kinds()[index]}")
    }
    check(kotlinx.serialization.descriptors.PrimitiveKind.INT === Primitive.INT)
    val first: Kind = Kind.ENUM
    val second: Kind = Kind.CONTEXTUAL
    check(first !== second)
    val intKind: Primitive = Primitive.INT
    val longKind: Primitive = Primitive.LONG
    check(intKind != longKind)
}
