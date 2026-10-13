package rejectedcontract
interface ByteBase { fun read(target: String, count: Byte): Int }
interface ByteChild : ByteBase { fun read(target: Int, start: Int = 0): Int }
fun explicitLongDoesNotNarrow(reader: ByteChild) { reader.read("sink", 1L) }
