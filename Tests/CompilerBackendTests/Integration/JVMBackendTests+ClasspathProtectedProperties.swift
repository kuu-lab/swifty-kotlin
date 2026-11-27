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
                lateinit var publicName: String
                lateinit var publicGeneric: T
            }

            open class ProtectedOpenValues {
                protected open var value: String? = "open"
            }

            class Payload

            open class ProtectedPayloadHolder {
                @JvmField protected var payload: Payload? = null
            }

            class PublicLateinitSimple {
                lateinit var name: String
            }

            class PublicLateinitGeneric<T : Any> {
                lateinit var value: T
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("provider.jar")
            let providerBuild = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(providerBuild.exitCode == 0, "\(providerBuild.stderr)")
            let providerArchive = try ZipArchive(data: Data(contentsOf: dependency))
            func readProviderClass(_ name: String) throws -> JVMClassInfo {
                let entry = try #require(providerArchive.entries.first { $0.name == name })
                var reader = JVMClassReader(bytes: Array(try providerArchive.contents(of: entry)))
                return try reader.read()
            }
            let providerInfo = try readProviderClass("fixture/ProtectedValues.class")
            let exposedMetadata = try #require(
                providerInfo.kotlinFieldProperties["exposed"],
                "metadata: \(providerInfo.hasKotlinMetadata); fields: \(providerInfo.fields.map { ($0.name, $0.access, $0.isProtected) }); methods: \(providerInfo.methods.map { ($0.name, $0.isProtected) })"
            )
            #expect(exposedMetadata.isVar)
            #expect(exposedMetadata.isProtected)
            #expect(exposedMetadata.sourceType?.hasSuffix("?") == true)
            #expect(providerInfo.kotlinMemberProperties["publicName"] != nil)
            #expect(providerInfo.kotlinMemberProperties["publicGeneric"] != nil)
            for name in ["publicName", "publicGeneric"] {
                let field = try #require(providerInfo.fields.first { $0.name == name })
                #expect(!providerInfo.isRuntimeInstanceField(field))
            }
            let openPropertyInfo = try readProviderClass("fixture/ProtectedOpenValues.class")
            #expect(openPropertyInfo.kotlinMemberProperties["value"] != nil)

            let runtime = try ownStdlibLibrary()
            let classpath = [dependency.path, runtime.path]
            let consumer = """
            package consumer
            import fixture.ProtectedValues
            import fixture.ProtectedOpenValues
            import fixture.ProtectedPayloadHolder
            import fixture.PublicLateinitGeneric
            import fixture.PublicLateinitSimple

            class Derived : ProtectedValues<String>() {
                fun readExposed(): String? = exposed
                fun writeExposed(value: String?) { exposed = value }
                fun readOn(other: Derived): String? = other.exposed
                fun writeOn(other: Derived, value: String?) { other.exposed = value }
                fun readSuper(): String? = super.exposed
                fun writeSuper(value: String?) { super.exposed = value }
                fun readStored(): String? = stored
                fun writeStored(value: String?) { stored = value }
                fun readLate(): String = late
                fun writeLate(value: String) { late = value }
                fun readPublicName(): String = publicName
                fun writePublicName(value: String) { publicName = value }
                fun readPublicGeneric(): String = publicGeneric
                fun writePublicGeneric(value: String) { publicGeneric = value }
            }

            class OpenDerived : ProtectedOpenValues() {
                fun readValue(): String? = value
                fun writeValue(value: String?) { this.value = value }
            }

            class PayloadDerived : ProtectedPayloadHolder() {
                fun readPayload(): Any? = payload
            }

            fun main() {
                val value = Derived()
                println(value.readExposed())
                value.writeExposed(null)
                println(value.readExposed() == null)
                value.writeExposed("changed")
                println(value.readExposed())
                println(value.readOn(value))
                value.writeOn(value, null)
                println(value.readOn(value) == null)
                value.writeSuper("super")
                println(value.readSuper())
                println(value.readStored())
                value.writeStored(null)
                println(value.readStored() == null)
                val open = OpenDerived()
                println(open.readValue())
                open.writeValue(null)
                println(open.readValue() == null)
                println(PayloadDerived().readPayload() == null)
                val simple = PublicLateinitSimple()
                try {
                    simple.name
                    println("unexpected-simple")
                } catch (error: UninitializedPropertyAccessException) {
                    println("uninitialized-simple")
                }
                simple.name = "ready-simple"
                println(simple.name)
                val generic = PublicLateinitGeneric<String>()
                try {
                    generic.value
                    println("unexpected-generic")
                } catch (error: UninitializedPropertyAccessException) {
                    println("uninitialized-generic")
                }
                generic.value = "ready-generic"
                println(generic.value)
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
            #expect(run.stdout == "initial\ntrue\nchanged\nchanged\ntrue\nsuper\nbacked\ntrue\nopen\ntrue\ntrue\nuninitialized-simple\nready-simple\nuninitialized-generic\nready-generic\nuninitialized\nready\n")

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
                fun <T : ProtectedValues<String>> readGeneric(value: T): String? = value.exposed
                fun <T : ProtectedValues<String>> writeGeneric(value: T) { value.exposed = null }
            }
            """
            let (_, receiverExit, receiverDiagnostics) = try m22Build(
                root: root, sources: [("WrongReceiver.kt", wrongReceiver)], name: "wrong-receiver.jar", classpath: classpath
            )
            #expect(receiverExit == 1, "\(receiverDiagnostics.map(\.message))")
            #expect(receiverDiagnostics.filter { $0.code == "KSWIFTK-SEMA-0041" }.count == 4)
        }
    }
}
#endif
