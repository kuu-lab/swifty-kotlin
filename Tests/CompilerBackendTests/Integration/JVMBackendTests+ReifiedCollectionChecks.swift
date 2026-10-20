#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func reifiedCollectionFixture() throws -> (source: String, expected: String) {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        return (try String(contentsOf: fixtures.appendingPathComponent("reifiedCapturedCollectionChecks.kt"), encoding: .utf8),
                try String(contentsOf: fixtures.appendingPathComponent("reifiedCapturedCollectionChecks.out"), encoding: .utf8))
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func reifiedCapturedCollectionChecksPreserveMutability(mode: EmitMode) throws {
        let fixture = try reifiedCollectionFixture()
        try withWorkspace { root in
            try runM11(fixture.source, expected: fixture.expected, mode: mode, root: root)
        }
    }

    @Test
    func officialKotlinUsesCapturedMutableChecksWithEitherRuntime() throws {
        let fixture = try reifiedCollectionFixture()
        try withWorkspace { root in
            let parts = fixture.source.components(separatedBy: "fun main() {")
            try #require(parts.count == 2)
            let library = try compile("package audit\n" + parts[0], root: root, mode: .jvmJar)
            try #require(library.0 == 0, "\(library.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar").path, officialRuntime = try m11Runtime()
            let consumer = "package consumer\nimport audit.*\nimport kotlin.coroutines.*\nfun main() {" + parts[1]
            try consumer.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", artifact + ":" + officialRuntime, "-d", "consumer.jar"], root: root)
            let repositoryRuntime = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(repositoryRuntime.1 == 0, "\(repositoryRuntime.2.map(\.message))")
            for runtime in [officialRuntime, repositoryRuntime.0.path] {
                let result = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + artifact + ":" + runtime, "consumer.ConsumerKt"])
                #expect(result.stdout == fixture.expected)
                #expect(result.stderr.isEmpty)
            }
        }
    }

    @Test(arguments: ["closure", "reference", "object"], [84, 85])
    func reifiedCaptureLimitsIncludeThreeTokenValues(kind: String, count: Int) throws {
        try withWorkspace { root in
            let names = (0..<count).map { "T\($0)" }, outerNames = (0..<count).map { "U\($0)" }
            let parameters = names.map { "reified " + $0 }.joined(separator: ", ")
            let outerParameters = outerNames.map { "reified " + $0 }.joined(separator: ", ")
            let body = names.map { $0 + "::class" }.joined(separator: "; ")
            let source: String
            switch kind {
            case "closure": source = "inline fun <\(parameters)> capture(): () -> Boolean = { \(body); true }"
            case "object": source = """
                interface Probe { fun check(): Boolean }
                inline fun <\(parameters)> capture(): Probe = object: Probe { override fun check(): Boolean { \(body); return true } }
                """
            default: source = """
                class Packed<\(names.joined(separator: ", "))>
                class Owner {
                    inline fun <\(parameters)> value(): Packed<\(names.joined(separator: ", "))> { \(body); return Packed() }
                }
                inline fun <\(outerParameters)> capture(owner: Owner): () -> Packed<\(outerNames.joined(separator: ", "))> = owner::value
                """
            }
            let output = root.appendingPathComponent("hello.jar"), original = Data("previous output".utf8)
            try original.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            if count == 84 {
                #expect(result.0 == 0, "\(result.1.map(\.message))")
                #expect(try Data(contentsOf: output) != original)
            } else {
                #expect(result.0 != 0)
                #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" && $0.message.contains("slot limit") }, "\(result.1.map(\.message))")
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
                #expect(try Data(contentsOf: output) == original)
            }
        }
    }
}
#endif
