package kotlin.text
class StringBuilder: CharSequence {
    constructor()
    constructor(capacity: Int)
    constructor(content: String)
    constructor(content: CharSequence)
    override val length: Int get() = 0
    override operator fun get(index: Int): Char = null!!
    operator fun set(index: Int, value: Char) {}
    fun getChars(srcBegin: Int, srcEnd: Int, dst: CharArray, dstBegin: Int) {}
    fun setCharAt(index: Int, value: Char) {}
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = null!!
    override fun toString(): String = null!!
    fun append(value: CharSequence?, startIndex: Int, endIndex: Int): StringBuilder = this
    fun append(value: CharArray, offset: Int, len: Int): StringBuilder = this
    fun appendCodePoint(codePoint: Int): StringBuilder = this
    fun codePointAt(index: Int): Int = 0
    fun codePointBefore(index: Int): Int = 0
    fun codePointCount(beginIndex: Int, endIndex: Int): Int = 0
    fun substring(startIndex: Int): String = null!!
    fun substring(startIndex: Int, endIndex: Int): String = null!!
    fun indexOf(str: String): Int = 0
    fun indexOf(str: String, fromIndex: Int): Int = 0
    fun lastIndexOf(str: String): Int = 0
    fun lastIndexOf(str: String, fromIndex: Int): Int = 0
    fun capacity(): Int = 0
    fun ensureCapacity(minimumCapacity: Int) {}
    fun trimToSize() {}
    fun setLength(newLength: Int) {}
    fun reverse(): StringBuilder = this
    fun deleteAt(index: Int): StringBuilder = this
    fun deleteRange(startIndex: Int, endIndex: Int): StringBuilder = this
    fun deleteCharAt(index: Int): StringBuilder = this
    fun delete(startIndex: Int, endIndex: Int): StringBuilder = this
    fun setRange(startIndex: Int, endIndex: Int, value: String): StringBuilder = this
    fun replace(startIndex: Int, endIndex: Int, value: String): StringBuilder = this
    fun clear(): StringBuilder = this
    fun appendRange(value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder = this
    fun appendRange(value: CharArray, startIndex: Int, endIndex: Int): StringBuilder = this
    fun insertRange(index: Int, value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder = this
    fun insertRange(index: Int, value: CharArray, startIndex: Int, endIndex: Int): StringBuilder = this
    fun appendLine(): StringBuilder = this
fun append(value: Any?): StringBuilder = this
fun appendLine(value: Any?): StringBuilder = this
fun insert(index: Int, value: Any?): StringBuilder = this
fun append(value: String?): StringBuilder = this
fun appendLine(value: String?): StringBuilder = this
fun insert(index: Int, value: String?): StringBuilder = this
fun append(value: CharSequence?): StringBuilder = this
fun appendLine(value: CharSequence?): StringBuilder = this
fun insert(index: Int, value: CharSequence?): StringBuilder = this
fun append(value: CharArray?): StringBuilder = this
fun appendLine(value: CharArray?): StringBuilder = this
fun insert(index: Int, value: CharArray?): StringBuilder = this
fun append(value: Char): StringBuilder = this
fun appendLine(value: Char): StringBuilder = this
fun insert(index: Int, value: Char): StringBuilder = this
fun append(value: Boolean): StringBuilder = this
fun appendLine(value: Boolean): StringBuilder = this
fun insert(index: Int, value: Boolean): StringBuilder = this
fun append(value: Int): StringBuilder = this
fun appendLine(value: Int): StringBuilder = this
fun insert(index: Int, value: Int): StringBuilder = this
fun append(value: Long): StringBuilder = this
fun appendLine(value: Long): StringBuilder = this
fun insert(index: Int, value: Long): StringBuilder = this
fun append(value: Float): StringBuilder = this
fun appendLine(value: Float): StringBuilder = this
fun insert(index: Int, value: Float): StringBuilder = this
fun append(value: Double): StringBuilder = this
fun appendLine(value: Double): StringBuilder = this
fun insert(index: Int, value: Double): StringBuilder = this
}
