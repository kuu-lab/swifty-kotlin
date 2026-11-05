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

    /// KUU-4311: `ProcessBuilder` environment/directory/redirect APIs,
    /// `Process.waitFor(timeout)`/`onExit()`/`toHandle()`, and the
    /// `ProcessHandle` surface. Assertions print booleans so the expected
    /// output stays deterministic across machines.
    @Test
    func processBuilderRedirectsAndProcessHandle() throws {
        try compileAndRunKotlin(
            """
            import java.io.File
            import java.lang.ProcessBuilder
            import java.lang.ProcessHandle
            import java.util.concurrent.TimeUnit

            fun drain(process: java.lang.Process): String {
                val text = process.inputStream.bufferedReader().readText()
                process.waitFor()
                return text
            }

            fun main() {
                val marker = "KSWIFTK_TEST_ENV_MARK"
                val gone = "KSWIFTK_TEST_ENV_GONE"
                val envText = drain(ProcessBuilder("/usr/bin/env").apply {
                    environment().put(marker, "present")
                    environment().put(gone, "x")
                    environment().remove(gone)
                    environment().remove("HOME")
                }.start())
                println(envText.lines().any { it == "$marker=present" })
                println(!envText.lines().any { it.startsWith("$gone=") })
                println(!envText.lines().any { it.startsWith("HOME=") })

                try {
                    ProcessBuilder("/bin/true").environment().put("BAD=NAME", "x")
                    println("envname accepted")
                } catch (e: IllegalArgumentException) {
                    println("envname IAE")
                }

                val dirPb = ProcessBuilder("/bin/pwd")
                println(dirPb.directory() == null)
                dirPb.directory(File("/"))
                println(drain(dirPb.start()).trim() == "/")

                val outFile = File("/tmp/kswiftk_test_pb_out.txt")
                val errFile = File("/tmp/kswiftk_test_pb_err.txt")
                val rc = ProcessBuilder("/bin/sh", "-c", "echo out-line; echo err-line 1>&2; exit 7")
                    .redirectOutput(outFile)
                    .redirectError(errFile)
                    .start()
                    .waitFor()
                println(rc == 7)
                println(outFile.readText().trim() == "out-line")
                println(errFile.readText().trim() == "err-line")

                val merged = drain(ProcessBuilder("/bin/sh", "-c", "echo mo; echo me 1>&2")
                    .redirectErrorStream(true).start())
                println(merged.contains("mo") && merged.contains("me"))

                val rTo = ProcessBuilder.Redirect.to(File("/tmp/kswiftk_test_r"))
                println(rTo.type() == ProcessBuilder.Redirect.Type.WRITE)
                println(ProcessBuilder.Redirect.DISCARD.type() == ProcessBuilder.Redirect.Type.WRITE)
                println(ProcessBuilder.Redirect.DISCARD.toString() == "WRITE")
                println(ProcessBuilder.Redirect.to(File("/tmp/kswiftk_test_r")) == rTo)
                println(ProcessBuilder.Redirect.PIPE.toString() == "PIPE")

                try {
                    ProcessBuilder("/bin/true").redirectInput(ProcessBuilder.Redirect.to(File("/tmp/x")))
                    println("bad_in accepted")
                } catch (e: IllegalArgumentException) {
                    println("bad_in IAE")
                }
                try {
                    ProcessBuilder("/bin/true").redirectOutput(ProcessBuilder.Redirect.from(File("/tmp/x")))
                    println("bad_out accepted")
                } catch (e: IllegalArgumentException) {
                    println("bad_out IAE")
                }

                val sleeper = ProcessBuilder("/bin/sleep", "30").start()
                println(!sleeper.waitFor(100, TimeUnit.MILLISECONDS))
                val fut = sleeper.onExit()
                sleeper.destroyForcibly()
                println(sleeper.waitFor(5, TimeUnit.SECONDS))
                var spins = 0
                while (!fut.isDone && spins < 500) {
                    Thread.sleep(10)
                    spins++
                }
                println(fut.isDone && fut.get() === sleeper)
                println(sleeper.exitValue() == 137)

                val live = ProcessBuilder("/bin/sleep", "30").start()
                try {
                    live.exitValue()
                    println("ev accepted")
                } catch (e: IllegalThreadStateException) {
                    println("ev ITE")
                }
                live.destroy()
                println(live.waitFor() >= 128)

                val cur = ProcessHandle.current()
                println(live.toHandle().pid() == live.pid())
                println(cur.isAlive() && cur.pid() > 0L)
                println(ProcessHandle.of(cur.pid()).isPresent())
                println(!ProcessHandle.of(99999999).isPresent())
                println(cur.parent().isPresent())
                println(ProcessHandle.allProcesses().count() > 0L)
                println(ProcessHandle.current() == cur)

                val victim = ProcessBuilder("/bin/sleep", "30").start()
                Thread.sleep(100)
                val vh = victim.toHandle()
                println(vh.isAlive())
                println(vh.destroy())
                victim.waitFor()
                println(!vh.isAlive())
                println(!ProcessHandle.of(victim.pid()).isPresent())
            }
            """,
            expectedOutput: """
            true
            true
            true
            envname IAE
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            bad_in IAE
            bad_out IAE
            true
            true
            true
            true
            ev ITE
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true

            """
        )
    }
}
#endif
