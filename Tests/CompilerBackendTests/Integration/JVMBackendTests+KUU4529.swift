#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4529: the JVM source validator must accept a line break before
    /// Elvis and annotations on catch parameters, matching kotlinc.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4529ElvisNewlineTakeIfAndAnnotatedCatch(mode: EmitMode) throws {
        let source = #"""
        fun parse(input: String): String =
            input.takeIf { it.isNotEmpty() }
                ?: "empty"

        fun parseOrThrow(input: String): String = try {
            input.takeIf { it.isNotEmpty() }
                ?: error("empty")
        } catch (@Suppress("UNUSED_PARAMETER") failure: IllegalStateException) {
            "caught"
        }

        fun main() {
            println(parse("x"))
            println(parse(""))
            println(parseOrThrow("y"))
            println(parseOrThrow(""))
        }
        """#
        try withWorkspace { root in
            try runM11(source, expected: "x\nempty\ny\ncaught\n", mode: mode, root: root)
        }
    }

    /// KUU-4529: `List.slice(IntRange)` lowers through the JDK List view.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4529ListSliceIntRange(mode: EmitMode) throws {
        let source = #"""
        fun middle(items: List<String>): List<String> = items.slice(1..1)
        fun head(items: List<Int>): List<Int> = items.slice(0 until 2)
        fun main() {
            println(middle(listOf("a", "b", "c")))
            println(head(listOf(1, 2, 3, 4)))
            println(listOf(1, 2, 3).slice(2..2))
        }
        """#
        try withWorkspace { root in
            try runM11(source, expected: "[b]\n[1, 2]\n[3]\n", mode: mode, root: root)
        }
    }

    /// KUU-4529: `kotlin.io.path.Path` factories and extension queries route to
    /// `java.nio.file` on the JVM lane.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4529PathFactoriesAndQueries(mode: EmitMode) throws {
        let source = #"""
        import java.nio.file.Path
        import kotlin.io.path.Path
        import kotlin.io.path.absolute
        import kotlin.io.path.isRegularFile
        import kotlin.io.path.notExists

        fun describe(path: Path): String = "${path.absolute()}|${path.notExists()}|${path.isRegularFile()}"

        fun main() {
            println(describe(Path("/tmp")))
            println(describe(Path("/etc/hosts")))
            println(describe(Path("/tmp/kswiftk-kuu4529-missing")))
        }
        """#
        try withWorkspace { root in
            try runM11(source, expected: "/tmp|false|false\n/etc/hosts|false|true\n/tmp/kswiftk-kuu4529-missing|true|false\n", mode: mode, root: root)
        }
    }
}
#endif
