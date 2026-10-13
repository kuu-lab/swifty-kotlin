package delegation.methods

class KnownLabel : Label {
    override fun label(): String = "known"
    override fun value(offset: Int): Int = 10 + offset
    override fun fail(): Int = 10
}

open class WrappedLabel(private val original: Label) : Label by original
