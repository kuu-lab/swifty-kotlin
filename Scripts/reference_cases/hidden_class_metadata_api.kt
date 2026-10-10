package hidden.metadata
interface Value
internal class Hidden : Value { override fun hashCode(): Int = 17 }
private class AlsoHidden : Value { override fun hashCode(): Int = 23 }
fun value(): Value = Hidden()
fun other(): Value = AlsoHidden()
