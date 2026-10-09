interface CountSource { val count: Int }
class Counter(var value: Int) : CountSource {
    override val count: Int get() = value
}
interface CountReader { fun read(): Int }
val CountSource.reader: CountReader
    get() = object : CountReader { override fun read(): Int = count }
val CountSource.readerFactory: () -> CountReader
    get() = { object : CountReader { override fun read(): Int = count } }
val CountSource.readCount: () -> Int
    get() = { count }
val CountSource.shadowed: CountReader
    get() = object : CountReader {
        val count: Int get() = 100
        override fun read(): Int = count
    }
fun main() {
    val counter = Counter(2)
    val source: CountSource = counter
    val reader = source.reader
    val factory = source.readerFactory
    val callback = source.readCount
    val other: CountSource = Counter(7)
    val otherFactory = other.readerFactory
    val otherReader = otherFactory()
    val shadowed = source.shadowed
    val nestedFactory: CountSource.() -> CountReader = {
        val inner: String.() -> CountReader = {
            object : CountReader { override fun read(): Int = count + length }
        }
        inner("xx")
    }
    val nested = source.nestedFactory()
    val localFactory: CountSource.() -> CountReader = {
        val inner: String.() -> CountReader = {
            class Reader : CountReader { override fun read(): Int = count + length }
            Reader()
        }
        inner("xxx")
    }
    val local = source.localFactory()
    println("${reader.read()}:${factory().read()}:${callback()}:${otherReader.read()}:${shadowed.read()}")
    println(nested.read())
    println(local.read())
    counter.value = 9
    println("${reader.read()}:${factory().read()}:${callback()}:${otherReader.read()}:${shadowed.read()}")
    println(nested.read())
    println(local.read())
}
