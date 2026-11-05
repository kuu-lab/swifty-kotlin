import java.lang.Runtime
import java.io.File

// KUU-4289: Process stream APIs (getInputStream/getOutputStream/getErrorStream)
// and Runtime.exec envp/dir overloads. Output is deterministic: child output
// is drained through the streams before waitFor, and env checks print
// booleans rather than environment contents.
fun main() {
    val rt = Runtime.getRuntime()

    val echo = rt.exec(arrayOf("/bin/echo", "hello-stream"))
    println(echo.inputStream.bufferedReader().readText().trim())
    println(echo.waitFor())

    val cat = rt.exec(arrayOf("/bin/cat"))
    cat.outputStream.write("ping\n".toByteArray())
    cat.outputStream.flush()
    cat.outputStream.close()
    println(cat.inputStream.bufferedReader().readText().trim())
    println(cat.waitFor())

    val err = rt.exec(arrayOf("/bin/sh", "-c", "echo oops >&2"))
    println(err.errorStream.bufferedReader().readText().trim())
    err.inputStream.bufferedReader().readText()
    println(err.waitFor())

    // envp fully replaces the environment (JDK semantics).
    val env = rt.exec(arrayOf("/usr/bin/env"), arrayOf("FOO=bar"))
    val envOut = env.inputStream.bufferedReader().readText()
    env.waitFor()
    println(envOut.contains("FOO=bar"))
    println(envOut.contains("PATH="))

    // dir selects the working directory for array and string forms.
    val pwd = rt.exec(arrayOf("/bin/pwd"), null, File("/"))
    println(pwd.inputStream.bufferedReader().readText().trim())
    pwd.waitFor()
    val spwd = rt.exec("/bin/pwd", null, File("/"))
    println(spwd.inputStream.bufferedReader().readText().trim())
    spwd.waitFor()

    // Empty command arrays surface ArrayIndexOutOfBoundsException like the JDK.
    try {
        rt.exec("   ")
        println("ws accepted")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("ws AIOOBE")
    }
    try {
        rt.exec(arrayOf<String>())
        println("arr accepted")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("arr AIOOBE")
    }

    // Repeated stream getters return the identical object.
    val p = rt.exec("true")
    println(p.inputStream === p.inputStream)
    println(p.outputStream === p.outputStream)
    println(p.waitFor())
}
