package golden.sema

import kotlinx.io.*

fun utf8(source: Source, sink: Sink, buffer: Buffer, chars: CharSequence): String {
    sink.writeString("é€😀")
    sink.writeString(chars, 0, chars.length)
    sink.writeCodePointValue(0x10ffff)
    println(source.readCodePointValue())
    println(source.indexOf(10.toByte(), 0L, 10L))
    println(source.readLine())
    println(source.readLineStrict(10L))
    println(source.readString(0L))
    println(source.readString())
    return buffer.readString()
}
