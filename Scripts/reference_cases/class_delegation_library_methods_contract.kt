package delegation.methods

interface Label {
    fun label(): String = "default"
    fun value(offset: Int): Int
    fun fail(): Int
}
