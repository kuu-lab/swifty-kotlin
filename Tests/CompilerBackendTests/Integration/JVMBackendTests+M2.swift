#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func assertJVM(_ source: String, _ expected: String, mode: EmitMode = .jvmJar) throws {
        try withWorkspace { root in
            let compilation = try compile(source, root: root, mode: mode)
            try #require(compilation.0 == 0, "\(compilation.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(Array(execution.stdout.utf8) == Array(expected.utf8))
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func variablesFunctionsRecursionAndBranches(mode: EmitMode) throws {
        try assertJVM("""
        fun add(a: Int, b: Int): Int = a + b
        fun add(a: Long, b: Long): Long = a + b
        fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)
        fun absolute(n: Int): Int {
            if (n < 0) { return -n } else { return n }
        }
        fun shadow(x: Int): Int { val x = x + 1; return x }
        fun main() {
            val greeting: String = "M2"
            println(greeting)
            var count: Int = add(2, 3)
            count *= 2
            count -= 1
            count /= 3
            count %= 2
            println(count)
            println(add(4L, 5L))
            println(factorial(6))
            println(absolute(-7))
            println(shadow(2))
            val chosen = if (count == 1) { val x = 10; x + 2 } else { 99 }
            println(chosen)
            if (false) println("wrong")
            if (true) { val count = 100; println(count) }
            println(count)
        }
        """, "M2\n1\n9\n720\n7\n3\n12\n100\n1\n", mode: mode)
    }

    @Test
    func numericTypesConversionsOverflowAndNaN() throws {
        try assertJVM("""
        fun twice(x: Double): Double = x * 2.0
        fun main() {
            var n = 2147483647
            n += 1
            println(n)
            println(-2147483648)
            println(-7 / 3)
            println(-7 % 3)
            println(9007199254740993L + 2L)
            println(1.5 + 2.25)
            println(1.5f * 2.0f)
            println(3L + 0.5)
            println(twice(2.25))
            println((-7.9).toInt())
            println(2147483648L.toInt())
            println(3.toLong() + 4L)
            println(2.5.toFloat())
            val nan = 0.0 / 0.0
            println(nan < 1.0)
            println(nan <= 1.0)
            println(nan > 1.0)
            println(nan >= 1.0)
            println(nan == nan)
            println(nan != nan)
            println(-0.0)
        }
        """, "-2147483648\n-2147483648\n-2\n-1\n9007199254740995\n3.75\n3.0\n3.5\n4.5\n-7\n-2147483648\n7\n2.5\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\n-0.0\n")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func loopsBreakContinueAndRangeBoundaries(mode: EmitMode) throws {
        try assertJVM("""
        fun main() {
            var total = 0
            for (i in 1..5) {
                if (i == 2) continue
                total += i
            }
            println(total)
            for (i in 5 downTo 1) { if (i == 2) break; print(i) }
            println()
            for (i in 0..<3) print(i)
            println()
            for (i in 4..2) println("wrong")
            for (i in 2 downTo 4) println("wrong")
            for (i in 3..<3) println("wrong")
            var n = 0
            while (n < 5) { n++; if (n == 2) continue; if (n == 4) break; print(n) }
            println()
            do { n--; print(n) } while (n > 1)
            println()
            do { val local = 0; print(local) } while (local > 0)
            println()
            for (i in 2147483646..2147483647) println(i)
            for (i in -2147483647 downTo -2147483648) println(i)
            for (i in 9223372036854775806L..9223372036854775807L) println(i)
            for (i in -9223372036854775807L downTo -9223372036854775807L) println(i)
        }
        """, "13\n543\n012\n13\n321\n0\n2147483646\n2147483647\n-2147483647\n-2147483648\n9223372036854775806\n9223372036854775807\n-9223372036854775807\n", mode: mode)
    }

    @Test
    func snapshotsShortCircuitAndIncrementResults() throws {
        try assertJVM("""
        fun pair(a: Int, b: Int): Int = a * 10 + b
        fun observed(value: Boolean): Boolean { println("rhs"); return value }
        fun main() {
            var x = 1
            println(pair(x, x++))
            println(x)
            println(++x)
            println(x++)
            println(x)
            println(false && observed(true))
            println(true || observed(false))
            println(true && observed(false))
            println(false || observed(true))
            println(!(1 < 2))
            val a = "same"
            val b = "same"
            println(a == b)
            println(a != "other")
        }
        """, "11\n2\n3\n3\n4\nfalse\ntrue\nrhs\nfalse\nrhs\ntrue\nfalse\ntrue\ntrue\n")
    }

    @Test
    func largeBranchAndWideLocalsVerify() throws {
        let largeBody = String(repeating: "println(\"unreachable\")\n", count: 2100)
        try assertJVM("fun main() { if (false) {\n" + largeBody + "} else { println(\"wide branch\") } }", "wide branch\n")
    }

    @Test(arguments: [
        "fun main() { val x = 1; x = 2 }",
        "fun main() { var x = 1; x = true }",
        "fun main() { println(missing) }",
        "fun main() { if (true) { val x = 1 }; println(x) }",
        "fun f(): Int { if (true) return 1 }; fun main() {}",
        "fun f(x: Int): Int = x; fun main() { f(true) }",
        "fun main() { while (1) {} }",
        "fun main() { break }",
        "fun main() { continue }",
        "fun main() { var x: Int; println(x) }",
        "fun main() { val x: Int; x = 1; x = 2 }",
        "fun main() { for (i in 1..3 step 2) println(i) }",
        "fun main() { println(1) garbage }",
        "fun main() { var x = 1; @Missing x += 2 }",
        "fun main() where T : Any { println(1) }",
        "fun main() { var x = 1; x += 0.5 }",
    ])
    func rejectsInvalidOrUnsupportedM2Programs(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.severity == .error })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
