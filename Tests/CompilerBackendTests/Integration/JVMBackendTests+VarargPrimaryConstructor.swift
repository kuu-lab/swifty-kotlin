#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func primitiveVarargPrimaryConstructorMatchesKotlinc() throws {
        try withWorkspace { root in
            let source = """
            class Box(vararg val elements: Int)
            class FixedBox(val elements: IntArray)
            fun main() {
                val empty = Box()
                println(empty.elements.size)
                val emptySpread = Box(*intArrayOf())
                println(emptySpread.elements.size)
                val one = Box(9)
                println(one.elements.size)
                println(one.elements[0])
                val many = Box(1, 2, 3)
                println(many.elements.size)
                println(many.elements[0])
                println(many.elements[2])
                val input = intArrayOf(4, 5)
                val spread = Box(*input)
                input[0] = 40
                println(spread.elements.size)
                println(spread.elements[0])
                println(spread.elements[1])
                val mixed = Box(6, *intArrayOf(7, 8))
                println(mixed.elements.size)
                println(mixed.elements[0])
                println(mixed.elements[2])
                println(FixedBox(intArrayOf(2, 3)).elements.size)
            }
            """
            let result = try compile(source, root: root, mode: .jvmJar, includeJVMRuntime: true)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let appJar = root.appendingPathComponent("hello.jar")
            let candidate = try java(["-jar", appJar.path])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stderr.isEmpty)

            let referenceBuild = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
            try #require(referenceBuild.exitCode == 0, "\(referenceBuild.stderr)")
            let reference = try java(["-jar", root.appendingPathComponent("reference.jar").path])
            #expect(reference.exitCode == 0, "\(reference.stderr)")
            #expect(reference.stderr.isEmpty)
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stdout == "0\n0\n1\n9\n3\n1\n3\n2\n4\n5\n3\n6\n8\n2\n")

            let varargSignature = try javap(["-p", "-s", "-classpath", appJar.path, "Box"])
            #expect(varargSignature.stdout.contains("public Box(int...);"))
            #expect(varargSignature.stdout.contains("descriptor: ([I)V"))
            #expect(varargSignature.stdout.contains("descriptor: ()[I"))
            let arrayControlSignature = try javap(["-p", "-s", "-classpath", appJar.path, "FixedBox"])
            #expect(arrayControlSignature.stdout.contains("public FixedBox(int[]);"))
        }
    }
}
#endif
