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

            open class ProtectedSetterValues {
                lateinit var name: String
                    protected set
            }

            open class ProtectedOpenValues {
                protected open var value: String? = "open"
            }

            open class ProtectedVisibilityValues {
                @Deprecated("removed", level = DeprecationLevel.HIDDEN)
                protected open var legacy: String = "old"

                @get:JvmSynthetic
                protected open val syntheticValue: String = "synthetic"
            }

            class Payload

            open class ProtectedPayloadHolder {
                @JvmField protected var payloads: List<Payload>? = null
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
            let setterInfo = try readProviderClass("fixture/ProtectedSetterValues.class")
            let setterProperty = try #require(setterInfo.kotlinMemberProperties["name"])
            #expect(!setterProperty.getter.isProtected)
            #expect(setterProperty.setter?.isProtected == true)
            let openPropertyInfo = try readProviderClass("fixture/ProtectedOpenValues.class")
            #expect(openPropertyInfo.kotlinMemberProperties["value"] != nil)
            let visibilityInfo = try readProviderClass("fixture/ProtectedVisibilityValues.class")
            #expect(visibilityInfo.kotlinMemberProperties["legacy"] == nil)
            #expect(!visibilityInfo.methods.contains { $0.name == "getLegacy" })
            #expect(visibilityInfo.kotlinMemberProperties["syntheticValue"] != nil)
            let payloadInfo = try readProviderClass("fixture/ProtectedPayloadHolder.class")
            let payloadField = try #require(payloadInfo.fields.first { $0.name == "payloads" })
            #expect(payloadField.descriptor == "Ljava/util/List;")
            #expect(payloadInfo.kotlinFieldProperties["payloads"]?.sourceType?.contains("Payload") == true)

            let runtime = try ownStdlibLibrary()
            let classpath = [dependency.path, runtime.path]
            let consumer = """
            package consumer
            import fixture.ProtectedValues
            import fixture.ProtectedSetterValues
            import fixture.ProtectedOpenValues
            import fixture.ProtectedPayloadHolder
            import fixture.ProtectedVisibilityValues
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

            class SetterDerived : ProtectedSetterValues() {
                fun writeName(value: String) { name = value }
            }

            class OpenDerived : ProtectedOpenValues() {
                fun readValue(): String? = value
                fun writeValue(value: String?) { this.value = value }
            }

            class VisibilityDerived : ProtectedVisibilityValues() {
                fun readSynthetic(): String = syntheticValue
            }

            class PayloadDerived : ProtectedPayloadHolder() {
                fun readPayload(): Any? = payloads
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
                val setter = SetterDerived()
                setter.writeName("ready-setter")
                println(setter.name)
                println(VisibilityDerived().readSynthetic())
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
            #expect(run.stdout == "initial\ntrue\nchanged\nchanged\ntrue\nsuper\nbacked\ntrue\nopen\ntrue\nready-setter\nsynthetic\ntrue\nuninitialized-simple\nready-simple\nuninitialized-generic\nready-generic\nuninitialized\nready\n")

            let unrelatedSetter = """
            package consumer
            import fixture.ProtectedSetterValues
            fun read(value: ProtectedSetterValues): String = value.name
            fun write(value: ProtectedSetterValues) { value.name = "unrelated" }
            """
            let (_, setterExit, setterDiagnostics) = try m22Build(
                root: root, sources: [("UnrelatedSetter.kt", unrelatedSetter)], name: "unrelated-setter.jar", classpath: classpath
            )
            #expect(setterExit == 1, "\(setterDiagnostics.map(\.message))")
            #expect(setterDiagnostics.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-SEMA-0041"])

            let hiddenProperty = """
            package consumer
            import fixture.ProtectedVisibilityValues
            class HiddenDerived : ProtectedVisibilityValues() {
                fun readHidden(): String = legacy
            }
            """
            let (_, hiddenExit, hiddenDiagnostics) = try m22Build(
                root: root, sources: [("HiddenProperty.kt", hiddenProperty)], name: "hidden-property.jar", classpath: classpath
            )
            #expect(hiddenExit == 1, "\(hiddenDiagnostics.map(\.message))")
            #expect(hiddenDiagnostics.contains { $0.message.contains("legacy") })

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

    @Test
    func importedPropertyDeprecationAndAccessorlessSignaturesRemainDistinct() throws {
        let provider = """
        package fixture

        open class ProtectedPropertyBase {
            protected val status: String = "visible"

            @Deprecated("removed", level = DeprecationLevel.HIDDEN)
            protected val String.status: String get() = this

            @Deprecated("removed", level = DeprecationLevel.HIDDEN)
            protected open var legacy: String = "old"

            @get:JvmSynthetic
            protected open val syntheticValue: String = "synthetic"

            lateinit var name: String
                @Deprecated("removed", level = DeprecationLevel.HIDDEN)
                protected set
        }

        open class FieldAndGetter {
            @JvmField var value: String = "field"
            fun getValue(): String = "method"
        }
        """

        try withWorkspace { root in
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("provider.jar")
            let providerBuild = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(providerBuild.exitCode == 0, "\(providerBuild.stderr)")
            let archive = try ZipArchive(data: Data(contentsOf: dependency))
            func readProviderClass(_ name: String) throws -> JVMClassInfo {
                let entry = try #require(archive.entries.first { $0.name == name })
                var reader = JVMClassReader(bytes: Array(try archive.contents(of: entry)))
                return try reader.read()
            }

            let propertyInfo = try readProviderClass("fixture/ProtectedPropertyBase.class")
            let status = try #require(propertyInfo.kotlinMemberProperties["status"])
            #expect(status.getter.isProtected)
            #expect(propertyInfo.kotlinMemberProperties["legacy"] == nil)
            #expect(!propertyInfo.methods.contains { $0.name == "getLegacy" })
            #expect(propertyInfo.kotlinMemberProperties["syntheticValue"] != nil)
            let name = try #require(propertyInfo.kotlinMemberProperties["name"])
            #expect(!name.getter.isHiddenByDeprecation)
            #expect(name.setter == nil)

            let fieldInfo = try readProviderClass("fixture/FieldAndGetter.class")
            let value = try #require(fieldInfo.kotlinMemberProperties["value"])
            #expect(value.getter.isAccessorlessField)
            #expect(fieldInfo.kotlinFieldProperties["value"]?.isVar == true)

            let runtime = try ownStdlibLibrary()
            let classpath = [dependency.path, runtime.path]
            let consumer = """
            package consumer
            import fixture.FieldAndGetter
            import fixture.ProtectedPropertyBase

            class Derived : ProtectedPropertyBase() {
                fun readStatus(): String = status
                fun readName(): String = name
                fun readSynthetic(): String = syntheticValue
            }

            class FieldDerived : FieldAndGetter() {
                fun readValue(): String = value
                fun writeValue(value: String) { this.value = value }
            }

            fun main() {
                val fields = FieldDerived()
                println(fields.readValue())
                fields.writeValue("updated")
                println(fields.readValue())
                println(Derived().readStatus())
                println(Derived().readSynthetic())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Consumer.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-cp", ([app.path] + classpath).joined(separator: ":"), "consumer.ConsumerKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "field\nupdated\nvisible\nsynthetic\n")

            let hiddenSetterWrite = """
            package consumer
            import fixture.ProtectedPropertyBase

            class HiddenSetterWrite : ProtectedPropertyBase() {
                fun readName(): String = name
                fun writeName(value: String) { name = value }
                fun readLegacy(): String = legacy
            }
            """
            let (_, setterExit, setterDiagnostics) = try m22Build(
                root: root, sources: [("HiddenSetterWrite.kt", hiddenSetterWrite)],
                name: "hidden-setter.jar", classpath: classpath
            )
            #expect(setterExit == 1, "\(setterDiagnostics.map(\.message))")
            #expect(setterDiagnostics.filter { $0.severity == .error }.count == 2)
            #expect(setterDiagnostics.contains { $0.message.contains("Val cannot be reassigned") })
            #expect(setterDiagnostics.contains { $0.message.contains("legacy") })
        }
    }
}
#endif
