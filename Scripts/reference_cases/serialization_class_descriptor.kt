@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.InternalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlinx.serialization.descriptors.*

annotation class BuilderTag(val value: String)

class ChangingChild(
    override var serialName: String,
    override var kind: SerialKind = PrimitiveKind.STRING
) : SerialDescriptor by PrimitiveSerialDescriptor("Child", PrimitiveKind.STRING)

class TracedChild(private val name: String, private val trace: MutableList<String>)
    : SerialDescriptor by PrimitiveSerialDescriptor("Traced", PrimitiveKind.STRING) {
    override val serialName: String
        get() { trace.add("$name:name"); return name }
    override val kind: SerialKind
        get() { trace.add("$name:kind"); return PrimitiveKind.STRING }
}

fun invalidBuilder(action: () -> Unit, expected: String) {
    try { action(); error("accepted invalid builder") }
    catch (e: IllegalArgumentException) { check(e.message == expected) }
}

fun checkBounds(descriptor: SerialDescriptor) {
    for (index in listOf(Int.MIN_VALUE, -1, descriptor.elementsCount, Int.MAX_VALUE)) {
        val actions: List<() -> Any?> = listOf(
            { descriptor.getElementName(index) }, { descriptor.getElementDescriptor(index) },
            { descriptor.getElementAnnotations(index) }, { descriptor.isElementOptional(index) }
        )
        for (action in actions) {
            try { action(); error("accepted out of bounds") }
            catch (e: IndexOutOfBoundsException) { }
        }
    }
}

fun main() {
    val text = PrimitiveSerialDescriptor("Text", PrimitiveKind.STRING)
    val integer = PrimitiveSerialDescriptor("Integer", PrimitiveKind.INT)
    val empty = buildClassSerialDescriptor("Empty")
    check(empty.serialName == "Empty" && empty.kind == StructureKind.CLASS && empty.elementsCount == 0)
    check(!empty.isNullable && !empty.isInline && empty.annotations.isEmpty())
    check(empty.getElementIndex("missing") == -3 && empty.toString() == "Empty()")
    checkBounds(empty)
    check(buildClassSerialDescriptor("kotlin.Int").serialName == "kotlin.Int")
    val twoParameters = buildClassSerialDescriptor("Pair", text, integer)
    val spreadParameters = buildClassSerialDescriptor("Pair", *arrayOf(text, integer))
    check(twoParameters == spreadParameters && twoParameters.hashCode() == spreadParameters.hashCode())
    check(twoParameters != buildClassSerialDescriptor("Pair", integer, text))
    val namedAction = buildClassSerialDescriptor("Named", builderAction = { element("id", integer) })
    check(namedAction.elementsCount == 1 && namedAction.getElementDescriptor(0) === integer)

    var captured: ClassSerialDescriptorBuilder? = null
    val rootAnnotations = mutableListOf<Annotation>(BuilderTag("root"))
    val fieldAnnotations = mutableListOf<Annotation>(BuilderTag("field"))
    val record = buildClassSerialDescriptor("Record", text) {
        check(serialName == "Record")
        captured = this
        annotations = rootAnnotations
        isNullable = true
        element("id", integer, isOptional = true)
        element("", text, annotations = fieldAnnotations)
    }
    check(record.kind == StructureKind.CLASS && record.elementsCount == 2)
    check(!record.isNullable && !record.isInline)
    check(record.getElementName(0) == "id" && record.getElementName(1) == "")
    check(record.getElementIndex("id") == 0 && record.getElementIndex("") == 1 && record.getElementIndex("late") == -3)
    check(record.getElementDescriptor(0) === integer && record.getElementDescriptor(1) === text)
    check(record.isElementOptional(0) && !record.isElementOptional(1))
    check(record.annotations === rootAnnotations && record.getElementAnnotations(1) === fieldAnnotations)
    captured!!.element("late", text)
    captured!!.annotations = emptyList()
    rootAnnotations.add(BuilderTag("second"))
    fieldAnnotations.add(BuilderTag("second"))
    check(record.elementsCount == 2 && record.annotations.size == 2 && record.getElementAnnotations(1).size == 2)
    check(record.toString() == "Record(id: Integer, : Text)")
    checkBounds(record)

    val sameShape = buildClassSerialDescriptor("Record", text) { element("different", integer); element("another", text) }
    check(record == sameShape && record.hashCode() == sameShape.hashCode())
    val sameShapeDifferentKind = buildSerialDescriptor("Record", StructureKind.LIST, text) { element("a", integer); element("b", text) }
    check(record == sameShapeDifferentKind && record.hashCode() == sameShapeDifferentKind.hashCode())
    check(record != buildClassSerialDescriptor("Record") { element("a", integer); element("b", text) })
    check(record != buildClassSerialDescriptor("Other", text) { element("a", integer); element("b", text) })
    check(record != buildClassSerialDescriptor("Record", text) { element("a", integer) })
    check(record != text && !record.equals(null))

    val child = ChangingChild("First")
    val lazyHash = buildClassSerialDescriptor("Live") { element("child", child) }
    child.serialName = "BeforeHash"
    val firstHash = lazyHash.hashCode()
    val originalShape = buildClassSerialDescriptor("Live") { element("x", ChangingChild("BeforeHash")) }
    check(lazyHash == originalShape && firstHash == originalShape.hashCode())
    child.serialName = "AfterHash"
    check(lazyHash.hashCode() == firstHash && lazyHash != originalShape)
    check(lazyHash.toString() == "Live(child: AfterHash)")
    val updatedShape = buildClassSerialDescriptor("Live") { element("y", ChangingChild("AfterHash")) }
    check(lazyHash == updatedShape)
    child.kind = PrimitiveKind.INT
    check(lazyHash != updatedShape && lazyHash.hashCode() == firstHash)

    val trace = mutableListOf<String>()
    val traced = buildClassSerialDescriptor("TracedRecord") {
        element("a", TracedChild("A", trace)); element("b", TracedChild("B", trace))
    }
    traced.hashCode()
    check(trace == listOf("A:name", "B:name", "A:kind", "B:kind"))
    trace.clear()
    traced.hashCode()
    check(trace.isEmpty())

    for (kind in listOf(StructureKind.LIST, StructureKind.MAP, StructureKind.OBJECT, SerialKind.ENUM, SerialKind.CONTEXTUAL, PrimitiveKind.INT, PolymorphicKind.OPEN)) {
        val descriptor = buildSerialDescriptor("Custom", kind) { element("child", text) }
        check(descriptor.kind === kind && descriptor.elementsCount == 1 && descriptor.getElementDescriptor(0) === text)
    }
    for (name in listOf("", " ", "\t", "\n")) {
        invalidBuilder({ buildClassSerialDescriptor(name) }, "Blank serial names are prohibited")
        invalidBuilder({ buildSerialDescriptor(name, StructureKind.CLASS) }, "Blank serial names are prohibited")
    }
    invalidBuilder({ buildSerialDescriptor("Custom", StructureKind.CLASS) }, "For StructureKind.CLASS please use 'buildClassSerialDescriptor' instead")
    invalidBuilder({ buildClassSerialDescriptor("Duplicate") { element("x", text); element("x", integer) } }, "Element with name 'x' is already registered in Duplicate")
    invalidBuilder({ buildClassSerialDescriptor("DuplicateEmpty") { element("", text); element("", integer) } }, "Element with name '' is already registered in DuplicateEmpty")
    println("builder:snapshots:annotation-aliases:${record.hashCode()}")
    println("equality:shape:type-parameters:kind-independent")
    println("hash:lazy:live-child:$firstHash")
    println("errors:blank:duplicate:class-kind:bounds")
}
