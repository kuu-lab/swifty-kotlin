#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4289: `Process` stream APIs — the parent reads the child's stdout
    /// and stderr and writes the child's stdin through pipes.
    @Test
    func processStreamsCarryChildOutputAndInput() throws {
        try compileAndRunKotlin(
            """
            import java.lang.Runtime
            fun main() {
                val rt = Runtime.getRuntime()

                val echo = rt.exec(arrayOf("/bin/echo", "hello-stream"))
                println(echo.inputStream.bufferedReader().readText().trim())
                println(echo.waitFor())

                val cat = rt.exec(arrayOf("/bin/cat"))
                cat.outputStream.write("ping\\n".toByteArray())
                cat.outputStream.flush()
                cat.outputStream.close()
                println(cat.inputStream.bufferedReader().readText().trim())
                println(cat.waitFor())

                val err = rt.exec(arrayOf("/bin/sh", "-c", "echo oops >&2"))
                println(err.errorStream.bufferedReader().readText().trim())
                err.inputStream.bufferedReader().readText()
                println(err.waitFor())
            }
            """,
            expectedOutput: "hello-stream\n0\nping\n0\noops\n0\n"
        )
    }

    /// KUU-4289: `Runtime.exec` envp/dir overloads — a non-null envp fully
    /// replaces the environment and dir selects the working directory.
    @Test
    func runtimeExecEnvpAndDirOverloads() throws {
        try compileAndRunKotlin(
            """
            import java.lang.Runtime
            import java.io.File
            fun main() {
                val rt = Runtime.getRuntime()

                val env = rt.exec(arrayOf("/usr/bin/env"), arrayOf("FOO=bar"))
                val envOut = env.inputStream.bufferedReader().readText()
                env.waitFor()
                println(envOut.contains("FOO=bar"))
                println(envOut.contains("PATH="))

                val pwd = rt.exec(arrayOf("/bin/pwd"), null, File("/"))
                println(pwd.inputStream.bufferedReader().readText().trim())
                pwd.waitFor()

                val spwd = rt.exec("/bin/pwd", null, File("/"))
                println(spwd.inputStream.bufferedReader().readText().trim())
                spwd.waitFor()

                val senv = rt.exec("/usr/bin/env", arrayOf("ONLY=this"))
                val sout = senv.inputStream.bufferedReader().readText()
                senv.waitFor()
                println(sout.contains("ONLY=this"))
                println(sout.contains("PATH="))
            }
            """,
            expectedOutput: "true\nfalse\n/\n/\ntrue\nfalse\n"
        )
    }

    /// KUU-4289: an empty command array — reached directly or through a
    /// whitespace-only `exec(String)` — surfaces
    /// `ArrayIndexOutOfBoundsException` like the JDK, while `exec("")` keeps
    /// throwing `IllegalArgumentException`.
    @Test
    func processEmptyCommandThrowsArrayIndexOutOfBounds() throws {
        try compileAndRunKotlin(
            """
            import java.lang.Runtime
            fun main() {
                val rt = Runtime.getRuntime()
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
                try {
                    java.lang.ProcessBuilder().start()
                    println("pb accepted")
                } catch (e: ArrayIndexOutOfBoundsException) {
                    println("pb AIOOBE")
                }
                try {
                    rt.exec("")
                    println("empty accepted")
                } catch (e: IllegalArgumentException) {
                    println("empty IAE")
                }
            }
            """,
            expectedOutput: "ws AIOOBE\narr AIOOBE\npb AIOOBE\nempty IAE\n"
        )
    }

    /// KUU-4289: repeated stream getters return the identical object, like the JDK.
    @Test
    func processStreamGettersReturnSameInstance() throws {
        try compileAndRunKotlin(
            """
            import java.lang.Runtime
            fun main() {
                val p = Runtime.getRuntime().exec("true")
                println(p.inputStream === p.inputStream)
                println(p.outputStream === p.outputStream)
                println(p.errorStream === p.errorStream)
                println(p.waitFor())
            }
            """,
            expectedOutput: "true\ntrue\ntrue\n0\n"
        )
    }
}
#endif
