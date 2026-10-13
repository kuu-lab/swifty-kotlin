// Proposed candidate-only regression, entryPointFQName = entrycontrols.launch.
// This option is supplied through CompilationContext, not a claimed CLI flag.
package entrycontrols
fun main() { println("original-main") }
fun launch(args: Array<String>) {
    println("selected:" + args.size)
    if (args.size > 0) println(args[0])
}
