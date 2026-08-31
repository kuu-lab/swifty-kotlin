import kotlin.enums.EnumEntries
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

@OptIn(ExperimentalEncodingApi::class)
fun main() {
    val default: Base64.Default = Base64.Default
    val base64: Base64 = default
    val entries: EnumEntries<Base64.PaddingOption> = Base64.PaddingOption.entries

    println(default === Base64.Default)
    println(base64 === Base64.Default)
    println(entries.size)
    println(entries[0] == Base64.PaddingOption.PRESENT)
    println(entries[1] == Base64.PaddingOption.ABSENT)
    println(entries[2] == Base64.PaddingOption.PRESENT_OPTIONAL)
    println(entries[3] == Base64.PaddingOption.ABSENT_OPTIONAL)
}
