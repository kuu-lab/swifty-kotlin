import java.io.File
import java.lang.ProcessBuilder
import java.lang.ProcessHandle
import java.util.concurrent.TimeUnit

// KUU-4311: ProcessBuilder environment()/directory()/redirect* APIs and
// Process.onExit/waitFor(timeout)/toHandle plus the ProcessHandle surface.
// Output is deterministic: env contents are probed with unique marker names,
// file redirects truncate before appending, and process metadata prints
// booleans rather than pids or timings.
fun drain(process: java.lang.Process): String {
    val text = process.inputStream.bufferedReader().readText()
    process.waitFor()
    return text
}

fun main() {
    // environment() mutations reach the child; untouched vars are inherited.
    val marker = "KUU4311_ENV_MARK"
    val gone = "KUU4311_ENV_GONE"
    val envProc = ProcessBuilder("/usr/bin/env").apply {
        environment().put(marker, "present")
        environment().put(gone, "x")
        environment().remove(gone)
        environment().remove("HOME")
    }.start()
    val envText = drain(envProc)
    println(envText.lines().any { it == "$marker=present" })
    println(!envText.lines().any { it.startsWith("$gone=") })
    println(envText.lines().any { it.startsWith("PATH=") })
    println(!envText.lines().any { it.startsWith("HOME=") })

    // environment() rejects invalid names like the JDK ProcessEnvironment.
    try {
        ProcessBuilder("/bin/true").environment().put("BAD=NAME", "x")
        println("envname accepted")
    } catch (e: IllegalArgumentException) {
        println("envname IAE")
    }

    // directory() getter/setter; null inherits the parent directory.
    val dirPb = ProcessBuilder("/bin/pwd")
    println(dirPb.directory() == null)
    dirPb.directory(File("/"))
    println(dirPb.directory()!!.path == "/")
    println(drain(dirPb.start()).trim())
    dirPb.directory(null)
    println(dirPb.directory() == null)

    // File redirects capture stdout/stderr; appendTo accumulates.
    val outFile = File("/tmp/kuu4311_diff_out.txt")
    val errFile = File("/tmp/kuu4311_diff_err.txt")
    val appFile = File("/tmp/kuu4311_diff_app.txt")
    val rc = ProcessBuilder("/bin/sh", "-c", "echo out-line; echo err-line 1>&2; exit 7")
        .redirectOutput(outFile)
        .redirectError(errFile)
        .start()
        .waitFor()
    println(rc == 7)
    println(outFile.readText().trim())
    println(errFile.readText().trim())
    // Truncate first so repeated runs stay deterministic, then append.
    ProcessBuilder("/bin/true").redirectOutput(ProcessBuilder.Redirect.to(appFile)).start().waitFor()
    ProcessBuilder("/bin/echo", "app-1").redirectOutput(ProcessBuilder.Redirect.to(appFile)).start().waitFor()
    ProcessBuilder("/bin/echo", "app-2").redirectOutput(ProcessBuilder.Redirect.appendTo(appFile)).start().waitFor()
    println(appFile.readText().trim().replace("\n", ","))

    // redirectErrorStream(true) merges stderr into the stdout pipe.
    val merged = ProcessBuilder("/bin/sh", "-c", "echo mo; echo me 1>&2")
        .redirectErrorStream(true)
        .start()
    val mergedText = drain(merged)
    println(mergedText.contains("mo") && mergedText.contains("me"))

    // Redirect type/file/toString/equals/hashCode surface.
    val rTo = ProcessBuilder.Redirect.to(File("/tmp/kuu4311_r"))
    println(rTo.type())
    println(rTo.file()!!.path == "/tmp/kuu4311_r")
    println(ProcessBuilder.Redirect.PIPE.type())
    println(ProcessBuilder.Redirect.INHERIT.type())
    println(ProcessBuilder.Redirect.DISCARD.type())
    println(ProcessBuilder.Redirect.DISCARD.file()!!.path == "/dev/null")
    println(ProcessBuilder.Redirect.to(File("/tmp/kuu4311_r")) == rTo)
    println(ProcessBuilder.Redirect.DISCARD == ProcessBuilder.Redirect.to(File("/dev/null")))
    println(ProcessBuilder.Redirect.PIPE.toString())
    println(ProcessBuilder.Redirect.INHERIT.toString())
    println(ProcessBuilder.Redirect.DISCARD.toString())
    println(ProcessBuilder.Redirect.from(File("/tmp/in")).toString())
    println(ProcessBuilder.Redirect.to(File("/tmp/out")).toString())
    println(ProcessBuilder.Redirect.appendTo(File("/tmp/app")).toString())

    // Invalid redirect directions throw IllegalArgumentException.
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

    // inheritIO: child stdio is wired to the parent's descriptors.
    println("--inherit-before--")
    ProcessBuilder("/bin/echo", "inherit-line").inheritIO().start().waitFor()
    println("--inherit-after--")

    // waitFor(timeout) + onExit + destroyForcibly.
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
    println(fut.isDone)
    println(fut.get() === sleeper)
    println(sleeper.exitValue() == 137)

    // exitValue() on a live process throws IllegalThreadStateException.
    val live = ProcessBuilder("/bin/sleep", "30").start()
    try {
        live.exitValue()
        println("ev accepted")
    } catch (e: IllegalThreadStateException) {
        println("ev ITE")
    }
    live.destroy()
    println(live.waitFor() >= 128)

    // toHandle + ProcessHandle surface (booleans only; pids are nondeterministic).
    println(live.toHandle().pid() == live.pid())
    val cur = ProcessHandle.current()
    println(cur.isAlive())
    println(cur.pid() > 0L)
    println(ProcessHandle.of(cur.pid()).isPresent())
    println(!ProcessHandle.of(99999999).isPresent())
    println(cur.parent().isPresent())
    println(cur.children().count() >= 0L)
    println(cur.descendants().count() >= 0L)
    println(ProcessHandle.allProcesses().count() > 0L)
    println(ProcessHandle.current() == cur)

    // ProcessHandle.destroy on a live child.
    val victim = ProcessBuilder("/bin/sleep", "30").start()
    Thread.sleep(100)
    val vh = victim.toHandle()
    println(vh.isAlive())
    println(vh.destroy())
    victim.waitFor()
    println(!vh.isAlive())
    println(!ProcessHandle.of(victim.pid()).isPresent())
}
