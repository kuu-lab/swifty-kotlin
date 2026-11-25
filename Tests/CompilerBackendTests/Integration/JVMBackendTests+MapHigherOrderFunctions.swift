#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapHigherOrderFunctionsUseBundledStdlib(mode: EmitMode) throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1)
            println(values.getOrElse("missing") { println("missing-default"); 0 })
            println(values.getOrElse("a") { println("unused-getOrElse"); -1 })

            val mutable = mutableMapOf<String, Int>()
            println(mutable.getOrPut("a") { println("insert-default"); 5 })
            println(mutable.getOrPut("a") { println("unused-getOrPut"); 6 })
            println(mutable)

            println(values.mapKeys { it.key.uppercase() })
            println(values.mapValues { it.value * 10 })
            println(values.filterKeys { it == "a" })
            println(values.filterValues { it > 0 })
        }
        """
        let expected = "missing-default\n0\n1\ninsert-default\n5\n5\n{a=5}\n{A=1}\n{a=10}\n{a=1}\n{a=1}\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-operations.jar" : "map-operations-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapForEachSupportsEntryDestructuring(mode: EmitMode) throws {
        let source = """
        fun main() {
            val analytics = mapOf("view" to 3, "click" to 1)
            analytics.forEach { (dest, events) -> println("$dest:$events") }
            analytics.forEach { entry -> println("${entry.key}=${entry.value}") }
            analytics.forEach { dest, events -> println("[$dest]=$events") }
        }
        """
        let expected = "view:3\nclick:1\nview=3\nclick=1\n[view]=3\n[click]=1\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-foreach.jar" : "map-foreach-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapForEachEntryLambdaSupportsNonLocalReturn(mode: EmitMode) throws {
        let source = """
        fun firstByEntry(): Int {
            mapOf("a" to 1, "b" to 2).forEach { e -> if (e.key == "a") return e.value }
            return 0
        }
        fun firstByDestructured(): Int {
            mapOf("x" to 5, "y" to 6).forEach { (k, v) -> if (k == "y") return v }
            return 0
        }
        fun firstByKeyValue(): String {
            var seen = ""
            mapOf("p" to 7, "q" to 8).forEach { k, v -> seen += "$k$v;" }
            return seen
        }
        fun labeled(): String {
            var s = ""
            mapOf("m" to 1).forEach l@{ e -> s += e.key; if (e.key == "m") return@l; s += "!" }
            return s
        }
        fun main() {
            println(firstByEntry())
            println(firstByDestructured())
            println(firstByKeyValue())
            println(labeled())
        }
        """
        let expected = "1\n6\np7;q8;\nm\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-foreach-return.jar" : "map-foreach-return-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapForEachEvaluatesCallbackBeforeIterating(mode: EmitMode) throws {
        let source = """
        fun entryAction(m: MutableMap<String, Int>): (Map.Entry<String, Int>) -> Unit {
            m["b"] = 2
            return { e -> println("e:${e.key}=${e.value}") }
        }
        fun pairAction(m: MutableMap<String, Int>): (String, Int) -> Unit {
            m["c"] = 3
            return { k, v -> println("p:$k=$v") }
        }
        fun main() {
            val m1 = mutableMapOf("a" to 1)
            m1.forEach(entryAction(m1))
            val m2 = mutableMapOf("x" to 7)
            m2.forEach(pairAction(m2))
        }
        """
        let expected = "e:a=1\ne:b=2\np:x=7\np:c=3\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-foreach-order.jar" : "map-foreach-order-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }
}
#endif
