import java.io.CharArrayReader
import java.io.CharArrayWriter
import java.io.FileReader
import java.io.FileWriter
import java.io.FilterWriter
import java.io.LineNumberReader
import java.io.OutputStreamWriter
import java.io.PushbackReader
import java.io.StringReader
import java.io.StringWriter

// KUU-4396: bundled java.io Reader/Writer family gaps. CharArrayReader/
// CharArrayWriter, FilterWriter, PushbackReader, LineNumberReader,
// FileReader, FileWriter, and OutputStreamWriter. Randomness-free output
// only; LineNumberReader pins JVM's line counting including the EOF
// increment for an unterminated final line.

fun main() {
    val cr = CharArrayReader(charArrayOf('a', 'b', 'c'))
    println(cr.read())
    val buf = CharArray(4)
    println(cr.read(buf, 0, 4))
    println(String(buf))
    cr.close()
    val cr2 = CharArrayReader(charArrayOf('a', 'b', 'c'))
    cr2.mark(2)
    cr2.read()
    cr2.reset()
    println(cr2.read())
    cr2.close()

    val cw = CharArrayWriter()
    cw.write("hi")
    cw.write(charArrayOf('!', '?'), 0, 2)
    cw.append('!')
    println(cw.toString())
    println(cw.size())
    println(String(cw.toCharArray()))
    cw.reset()
    println(cw.size())
    cw.close()

    val pr = PushbackReader(StringReader("abc"), 8)
    println(pr.read())
    pr.unread('q'.code)
    pr.unread(charArrayOf('x', 'y'))
    val pbuf = CharArray(4)
    println(pr.read(pbuf, 0, 4))
    println(String(pbuf))
    pr.close()

    val lnr = LineNumberReader(StringReader("a\nb\rc\r\nd"))
    println(lnr.readLine())
    println(lnr.readLine())
    println(lnr.getLineNumber())
    println(lnr.readLine())
    println(lnr.readLine())
    println(lnr.getLineNumber())
    println(lnr.readLine())
    lnr.close()

    val sw = StringWriter()
    val fw = object : FilterWriter(sw) {}
    fw.write("delegated")
    fw.close()
    println(sw.toString())

    val path = "/tmp/kswiftk_diff_javaio_rw.txt"
    val fw2 = FileWriter(path)
    fw2.write("line1\nline2\n")
    fw2.close()
    val fr = FileReader(path)
    println(fr.read())
    val fbuf = CharArray(6)
    println(fr.read(fbuf, 0, 6))
    println(String(fbuf))
    fr.close()

    val osw = OutputStreamWriter(java.io.File(path).outputStream())
    osw.write("appended")
    osw.close()
    println(java.io.File(path).readText())

    val fwa = FileWriter(path, true)
    fwa.write("+tail")
    fwa.close()
    println(java.io.File(path).readText().endsWith("+tail"))
}
