#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedProtectedJvmFieldsAndBackingPropertiesPreserveJvmAccess() throws {
        try withWorkspace { root in
            let provider = """
            package fixture
            open class ProtectedValues<T : Any> {
                @JvmField protected var exposed: String? = "initial"
                protected var stored: String? = "backed"
                protected lateinit var late: T
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("provider.jar")
            let providerBuild = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(providerBuild.exitCode == 0, "\(providerBuild.stderr)")
            let providerArchive = try ZipArchive(data: Data(contentsOf: dependency))
            let providerClass = try #require(providerArchive.entries.first { $0.name == "fixture/ProtectedValues.class" })
            var providerReader = JVMClassReader(bytes: Array(try providerArchive.contents(of: providerClass)))
            let providerInfo = try providerReader.read()
            let exposedMetadata = try #require(
                providerInfo.kotlinFieldProperties["exposed"],
                "metadata: \(providerInfo.hasKotlinMetadata); fields: \(providerInfo.fields.map { ($0.name, $0.access, $0.isProtected) }); methods: \(providerInfo.methods.map { ($0.name, $0.isProtected) })"
            )
            #expect(exposedMetadata.isVar)
            #expect(exposedMetadata.sourceType?.hasSuffix("?") == true)

            let runtime = try ownStdlibLibrary()
            let classpath = [dependency.path, runtime.path]
            let consumer = """
            package consumer
            import fixture.ProtectedValues

            class Derived : ProtectedValues<String>() {
                fun readExposed(): String? = exposed
                fun writeExposed(value: String?) { exposed = value }
                fun readStored(): String? = stored
                fun writeStored(value: String?) { stored = value }
                fun readLate(): String = late
                fun writeLate(value: String) { late = value }
            }

            fun main() {
                val value = Derived()
                println(value.readExposed())
                value.writeExposed(null)
                println(value.readExposed() == null)
                value.writeExposed("changed")
                println(value.readExposed())
                println(value.readStored())
                value.writeStored(null)
                println(value.readStored() == null)
                try {
                    value.readLate()
                    println("unexpected")
                } catch (error: UninitializedPropertyAccessException) {
                    println("uninitialized")
                }
                value.writeLate("ready")
                println(value.readLate())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Consumer.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "consumer.ConsumerKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "initial\ntrue\nchanged\nbacked\ntrue\nuninitialized\nready\n")

            let unrelated = """
            package consumer
            import fixture.ProtectedValues
            fun read(value: ProtectedValues<String>): String? = value.exposed
            """
            let (_, unrelatedExit, unrelatedDiagnostics) = try m22Build(
                root: root, sources: [("Unrelated.kt", unrelated)], name: "unrelated.jar", classpath: classpath
            )
            #expect(unrelatedExit == 1, "\(unrelatedDiagnostics.map(\.message))")

            let wrongReceiver = """
            package consumer
            import fixture.ProtectedValues
            class Derived : ProtectedValues<String>() {
                fun read(value: ProtectedValues<String>): String? = value.exposed
                fun write(value: ProtectedValues<String>) { value.exposed = null }
            }
            """
            let (_, receiverExit, receiverDiagnostics) = try m22Build(
                root: root, sources: [("WrongReceiver.kt", wrongReceiver)], name: "wrong-receiver.jar", classpath: classpath
            )
            #expect(receiverExit == 1, "\(receiverDiagnostics.map(\.message))")
        }
    }
}
#endif
