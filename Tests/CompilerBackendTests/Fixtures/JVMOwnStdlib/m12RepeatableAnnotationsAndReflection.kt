import kotlin.reflect.full.findAnnotations
@Repeatable annotation class Tag(val value: String)
@Tag("one") @Tag("two") class Marked {
    @get:Tag("get1") @get:Tag("get2") var value = 1
}
@Tag("fun1") @Tag("fun2") fun tagged(@Tag("p1") @Tag("p2") value: Int): Int = value
@Target(AnnotationTarget.PROPERTY) @Repeatable annotation class PropertyTag(val value: Int)
@PropertyTag(3) @PropertyTag(4) val top = 1
@Tag("single") class Single
fun main() {
    val tags = Marked::class.findAnnotations<Tag>()
    println(tags.size); println(tags[0].value); println(tags[1].value)
    println(Marked::class.annotations.size)
    println(Marked::class.java.getAnnotationsByType(Tag::class.java).size)
    val f = ::tagged; println(f.findAnnotations<Tag>()[1].value)
    println(f.parameters[0].findAnnotations<Tag>()[0].value)
    println(::top.findAnnotations<PropertyTag>()[1].value)
    println(Single::class.findAnnotations<Tag>()[0].value)
}
