#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct FunctionParameterDefaultArgumentTests {
    private let declarations = """
    fun interface Operation { fun apply(value: Char): Int }
    object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
    fun Operation(value: Int = 0, block: (String) -> Int): Operation = CharOperation
    fun order(a: Int, b: Int, c: Int) = a + b + c
    fun spread(a: Int, b: IntArray) = b.size
    fun l(f: (String) -> String, g: (String) -> String = { it }) = f("x")
    fun f(x: Int, g: (Int) -> Int = { it }): Int = g(x)
    fun h(x: Int, g: (Int) -> Int = { it }, k: Int = 9): Int = g(x) + k
    fun both(f: (String) -> String = { "f" }, g: (String) -> String = { "g" }) = f(g("x"))
    fun shaped(f: (String) -> String = { it }, g: (Int) -> Int = { it }) = f("x")
    fun <T> generic(x: T, f: (T) -> String, g: (T) -> String = { "default" }) = f(x)
    class E(val x: Int, val g: (Int) -> Int = { it })
    class J(val s: String, val f: (String) -> String, val k: Int = 0)
    class K(val s: String, val g: (String) -> String = { it }, val f: (String) -> String)
    class L(val f: (String) -> String, val g: (String) -> String = { it })
    class M(val f: (String) -> String, val g: ((String) -> String)? = null)
    class N(val xs: List<String>, val g: (String) -> String = { it })
    class O(val xs: List<String>, val n: Int, val g: (String) -> String = { it })
    class Choice<T>(val choices: List<T>, val toVariant: (String) -> T, val variantToString: (T) -> String = { "default" })
    class Host {
        fun call(f: (String) -> String, g: (String) -> String = { it }) = f("x")
    }
    fun Host.extension(f: (String) -> String, g: (String) -> String = { it }) = f("x")
    """

    private let validCalls = [
        "Operation { it.length }", "Operation(block = { it.length })",
        "order(a = 1, b = 2, 3)", "l(fn)", "l({ it + \"!\" })", "l(::identity)", "l(f = fn)",
        "f(1)", "h(2)", "E(1)", "N(listOf(\"a\"))", "O(listOf(\"a\"), 5)",
        "J(\"a\", fn)", "K(\"a\", f = fn)", "L(fn)", "L({ it })", "M(fn)", "M({ it })",
        "generic(\"x\", fn)", "generic(\"x\", { it })", "generic<String>(\"x\", fn)",
        "Choice(listOf(\"a\"), fn)", "Choice(listOf(\"a\"), { it })", "Choice<String>(listOf(\"a\"), fn)",
        "Host().call(fn)", "Host().call({ it })", "Host().extension(fn)",
        "host?.call(fn)", "Host().call(f = fn) { it }",
        "shaped({ it + \"!\" })", "shaped { it + 1 }", "both(f = fn, fn)",
        "both(fn)", "both({ it })", "both { it }", "both() { it }", "both label@ { it }",
        "K(\"a\") { it }", "generic(\"x\", fn) { it }",
    ]

    @Test
    func acceptsValidCalls() throws {
        let ctx = makeContextFromSource(declarations + "\n" + """
        fun identity(s: String): String = s
        fun test() {
            val fn: (String) -> String = { it + "!" }
            val host: Host? = Host()
            \(validCalls.joined(separator: "\n"))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // The issue's unparenthesized reproducer binds g and leaves required f missing in Kotlin.
    @Test
    func rejectsInvalidCalls() throws {
        let calls = ["l { it + \"!\" }", "L { it }", "l()", "l({ 1 })", "both(g = { it }, { it })",
                     "order(b = 2, a = 1, 3)", "spread(a = 1, *intArrayOf(2))"]
        var source = declarations
        var ranges: [Range<Int>] = []
        for (index, call) in calls.enumerated() {
            let start = source.utf8.count
            source += "\nfun invalid\(index)() { \(call) }\n"
            ranges.append(start..<source.utf8.count)
        }
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        for (call, range) in zip(calls, ranges) {
            // A lambda return-type mismatch uses the ordinary type diagnostic.
            let code = call == "l({ 1 })" ? "KSWIFTK-TYPE-0001" : "KSWIFTK-SEMA-0002"
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == code && $0.primaryRange.map { range.contains($0.start.offset) } == true
            }, "Expected \(code) for \(call): \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
