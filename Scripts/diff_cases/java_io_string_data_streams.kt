import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.BufferedWriter
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.PrintWriter
import java.io.StringReader
import java.io.StringWriter

fun main() {
    val reader = StringReader("abc")
    println(reader.ready())
    println(reader.read())
    println(reader.read())
    println(reader.read())
    println(reader.read())
    val writer = StringWriter()
    writer.write("x")
    println(writer)
    val buffered = BufferedWriter(writer)
    buffered.write("y")
    buffered.newLine()
    buffered.flush()
    val printer = PrintWriter(writer)
    printer.print("z")
    printer.println(42)
    printer.close()
    println(writer.toString())
    printer.print("ignored after close")
    println(printer.checkError())

    val bytes = ByteArrayOutputStream()
    val dataOutput = DataOutputStream(bytes)
    dataOutput.writeInt(5)
    dataOutput.writeShort(0x1234)
    dataOutput.writeBoolean(true)
    val dataInput = DataInputStream(ByteArrayInputStream(bytes.toByteArray()))
    println(dataInput.readInt())
    println(dataInput.readUnsignedShort())
    println(dataInput.readBoolean())
}
