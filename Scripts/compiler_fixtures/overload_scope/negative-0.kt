package rejectedcontract
interface BaseReader { fun read(target: String, count: Long): Long }
interface ChildReader : BaseReader { fun read(target: ByteArray, start: Int = 0): Int }
fun ordinaryIntIsNotLong(reader: ChildReader, count: Int) { reader.read("sink", count) }
