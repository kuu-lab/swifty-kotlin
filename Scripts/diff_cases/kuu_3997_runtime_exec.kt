import java.lang.Runtime

// KUU-3997: Runtime.exec(String) / Runtime.exec(Array<String>) coverage.
// Only silent commands are used so child-process stdout ordering cannot
// diverge between the two backends.
fun main() {
    val runtime = Runtime.getRuntime()

    val ok = runtime.exec("true")
    println(ok.waitFor())
    println(ok.exitValue())
    println(ok.isAlive)
    println(ok.pid() > 0L)

    val failed = runtime.exec("false")
    println(failed.waitFor())

    // The string form tokenizes like StringTokenizer defaults: runs of
    // delimiters collapse and extra arguments are passed through.
    val multi = runtime.exec("/usr/bin/true   ignored   arguments")
    println(multi.waitFor())

    val arrayForm = runtime.exec(arrayOf("/usr/bin/true", "ignored"))
    println(arrayForm.waitFor())

    try {
        runtime.exec("")
        println("empty accepted")
    } catch (e: IllegalArgumentException) {
        println("empty rejected")
    }

    try {
        runtime.exec("definitely-not-a-real-binary-kuu3997")
        println("missing accepted")
    } catch (e: java.io.IOException) {
        println("missing rejected")
    }
}
