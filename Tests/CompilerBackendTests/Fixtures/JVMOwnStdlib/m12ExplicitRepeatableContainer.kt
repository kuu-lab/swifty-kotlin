import kotlin.jvm.JvmRepeatable
import kotlin.reflect.full.findAnnotations
@Target(AnnotationTarget.CLASS) annotation class Tags(val value: Array<Tag>, val note: String = "custom")
@Target(AnnotationTarget.CLASS) @Repeatable @JvmRepeatable(Tags::class) annotation class Tag(val value: Int)
@Tag(1) @Tag(2) class Marked
@Target(AnnotationTarget.ANNOTATION_CLASS) annotation class MetaTags(val value: Array<MetaTag>)
@Target(AnnotationTarget.CLASS) @JvmRepeatable(MetaTags::class) annotation class MetaTag
@MetaTag @MetaTag annotation class MetaMarked
fun main() {
    val tags = Marked::class.findAnnotations<Tag>()
    println(tags.size); println(tags[0].value); println(tags[1].value)
    val javaTags = Marked::class.java.getAnnotationsByType(Tag::class.java)
    println(javaTags.size); println(javaTags[1].value)
}
