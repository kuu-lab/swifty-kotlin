@file:OptIn(kotlinx.serialization.SealedSerializationApi::class)

import kotlinx.serialization.descriptors.*
import kotlinx.serialization.descriptors.SerialDescriptor as Descriptor

annotation class DescriptorTag(val value: String)

class LeafDescriptor(
    override val serialName: String, override val kind: SerialKind,
    override val isNullable: Boolean = false, override val isInline: Boolean = false
): Descriptor {
    override val elementsCount: Int get() = 0
    override fun getElementName(index: Int): String = throw IllegalStateException("leaf:$index")
    override fun getElementIndex(name: String): Int = throw IllegalStateException("leaf:$name")
    override fun getElementAnnotations(index: Int): List<Annotation> = throw IllegalStateException("leaf:$index")
    override fun getElementDescriptor(index: Int): Descriptor = throw IllegalStateException("leaf:$index")
    override fun isElementOptional(index: Int): Boolean = throw IllegalStateException("leaf:$index")
}

class EnvelopeDescriptor: Descriptor {
    private val first: Descriptor = LeafDescriptor("First", PrimitiveKind.STRING)
    private val second: Descriptor = LeafDescriptor("Second", PrimitiveKind.INT, true, true)
    override val serialName: String get() = "Envelope"
    override val kind: SerialKind get() = StructureKind.CLASS
    override val elementsCount: Int get() = 2
    override val annotations: List<Annotation> get() = listOf(DescriptorTag("root"))
    override fun getElementName(index: Int): String = when(index) {
        0 -> "first"
        1 -> "second"
        else -> throw IndexOutOfBoundsException("index:$index")
    }
    override fun getElementIndex(name: String): Int = when(name) {
        "first" -> 0
        "second" -> 1
        else -> -3
    }
    override fun getElementAnnotations(index: Int): List<Annotation> = when(index) {
        0 -> listOf(DescriptorTag("field"))
        1 -> emptyList()
        else -> throw IndexOutOfBoundsException("index:$index")
    }
    override fun getElementDescriptor(index: Int): Descriptor = when(index) {
        0 -> first
        1 -> second
        else -> throw IndexOutOfBoundsException("index:$index")
    }
    override fun isElementOptional(index: Int): Boolean = when(index) {
        0 -> false
        1 -> true
        else -> throw IndexOutOfBoundsException("index:$index")
    }
}

fun main() {
    val descriptor: Descriptor = EnvelopeDescriptor()
    val fullyQualified: kotlinx.serialization.descriptors.SerialDescriptor = descriptor
    check(fullyQualified === descriptor)
    check(fullyQualified.serialName == "Envelope")
    check(!fullyQualified.isNullable && !fullyQualified.isInline)
    println("${descriptor.serialName}|${descriptor.kind}|${descriptor.elementsCount}|${descriptor.isNullable}|${descriptor.isInline}|${descriptor.annotations.size}")
    println((descriptor.annotations[0] as DescriptorTag).value)
    for (index in 0 until descriptor.elementsCount) {
        val child = descriptor.getElementDescriptor(index)
        println("${descriptor.getElementName(index)}|${descriptor.getElementIndex(descriptor.getElementName(index))}|${child.serialName}|${child.kind}|${child.isNullable}|${child.isInline}|${descriptor.isElementOptional(index)}|${descriptor.getElementAnnotations(index).size}")
        check(child.isNullable == (index == 1))
        check(child.isInline == (index == 1))
        check(child.annotations.isEmpty())
    }
    println((descriptor.getElementAnnotations(0)[0] as DescriptorTag).value)
    println("unknown:${descriptor.getElementIndex("unknown")}")
    val names = descriptor.elementNames
    val left = names.iterator()
    val right = names.iterator()
    println("first:${left.next()}")
    println("independent:${right.next()}")
    println("rest:${left.next()}:${left.hasNext()}")
    try { left.next(); error("missing failure") } catch(e: IndexOutOfBoundsException) { println(e.message) }
    println(names.toList())
    val children = descriptor.elementDescriptors
    val a = children.iterator()
    val b = children.iterator()
    check(a.next() === descriptor.getElementDescriptor(0))
    check(b.next() === descriptor.getElementDescriptor(0))
    check(a.next() === descriptor.getElementDescriptor(1))
    check(!a.hasNext())
    try { a.next(); error("missing failure") } catch(e: IndexOutOfBoundsException) { println(e.message) }
    println(children.map { it.serialName })
    val leaf: Descriptor = descriptor.getElementDescriptor(0)
    println("empty:${leaf.elementNames.iterator().hasNext()}:${leaf.elementDescriptors.iterator().hasNext()}")
    try { leaf.elementNames.iterator().next(); error("missing failure") } catch(e: IllegalStateException) { println(e.message) }
}
