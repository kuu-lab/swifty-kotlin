import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*

class FieldModel(
    @Required val required: Int = 1,
    @Transient val temporary: Int = 2,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val optional: Int = 3,
)

fun main() {
    val required = Required()
    val transient = Transient()
    check(required == Required() && required.hashCode() == 0)
    check(transient == Transient() && transient.hashCode() == 0)
    check((required as Annotation) != transient)
    check(required.annotationClass.simpleName == "Required")
    check(transient.annotationClass.simpleName == "Transient")
    val always = EncodeDefault()
    val never = EncodeDefault(mode = EncodeDefault.Mode.NEVER)
    check(always.annotationClass.simpleName == "EncodeDefault")
    check(always.mode === EncodeDefault.Mode.ALWAYS && never.mode === EncodeDefault.Mode.NEVER)
    check(always == EncodeDefault(EncodeDefault.Mode.ALWAYS) && always != never)
    check(never.hashCode() == ((127 * "mode".hashCode()) xor EncodeDefault.Mode.NEVER.hashCode()))
    check(EncodeDefault.Mode.entries.map { it.name }.joinToString(",") == "ALWAYS,NEVER")
    check(EncodeDefault.Mode.valueOf("ALWAYS") === always.mode)
    val copied = EncodeDefault.Mode.values()
    check(copied.size == 2 && copied.map { it.name }.joinToString(",") == "ALWAYS,NEVER")
    check(EncodeDefault.Mode.valueOf("NEVER") === never.mode)
    copied[0] = EncodeDefault.Mode.NEVER
    check(EncodeDefault.Mode.values()[0] === EncodeDefault.Mode.ALWAYS)
    check(EncodeDefault.Mode.entries[0] === EncodeDefault.Mode.ALWAYS)
    var invalid = false
    try { EncodeDefault.Mode.valueOf("missing") } catch (e: IllegalArgumentException) { invalid = true }
    check(invalid)
    val descriptor = buildClassSerialDescriptor("Manual") {
        element("field", PrimitiveSerialDescriptor("Child", PrimitiveKind.INT),
                annotations = listOf(required, transient, never))
    }
    val annotations = descriptor.getElementAnnotations(0)
    check(annotations.size == 3 && annotations[0] === required && annotations[1] === transient && annotations[2] === never)
    check(descriptor.elementsCount == 1 && !descriptor.isElementOptional(0))
    println("annotations:constructors:equality:hash")
    println("mode:default:entries:values:valueOf")
    println("descriptor:explicit:identity")
}
