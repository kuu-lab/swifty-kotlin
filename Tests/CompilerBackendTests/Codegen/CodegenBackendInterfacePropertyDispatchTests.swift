#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendInterfacePropertyDispatchTests {

    @Test
    func testObjectExpressionStoredPropertyReadThroughInterface() throws {
        let source = """
        interface Holder { val value: Int }
        fun make(): Holder = object : Holder { override val value: Int = 42 }
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141ObjectStoredProperty",
            expected: "42\n"
        )
    }

    @Test
    func testNamedClassStoredPropertyReadThroughInterface() throws {
        let source = """
        interface Holder { val value: Int }
        class Impl : Holder { override val value: Int = 42 }
        fun make(): Holder = Impl()
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141NamedClassStoredProperty",
            expected: "42\n"
        )
    }

    @Test
    func testInheritedConcretePropertiesImplementGenericInterface() throws {
        let source = try diffCaseSource("kuu_2876_inherited_class_property_itable.kt")

        try assertKotlinOutput(
            source,
            moduleName: "Kuu2876InheritedClassPropertyItable",
            expected: "56\n56\n57\n41\n"
        )
    }

    @Test
    func testInterfaceTypedParameterPropertyRead() throws {
        let source = """
        interface Holder { val value: Int }
        class Impl : Holder { override val value: Int = 42 }
        fun useHolder(h: Holder): Int = h.value
        fun main() { println(useHolder(Impl())) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141InterfaceParameter",
            expected: "42\n"
        )
    }

    @Test
    func testCustomGetterPropertyReadThroughInterface() throws {
        let source = """
        interface Holder { val value: Int }
        fun make(): Holder = object : Holder { override val value: Int get() = 42 }
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141CustomGetter",
            expected: "42\n"
        )
    }

    @Test
    func testImplicitReceiverPropertyReadInsideInterfaceDefaultMethod() throws {
        let source = """
        interface Holder {
            val value: Int
            fun doubled(): Int = value * 2
            fun sum(other: Holder): Int = value + other.value
        }
        class Impl : Holder { override val value: Int = 21 }
        fun main() {
            val holder: Holder = Impl()
            println(holder.doubled())
            println(holder.sum(Impl()))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug187ImplicitReceiverInterfaceProperty",
            expected: "42\n42\n"
        )
    }

    @Test
    func testInterfacePropertyAssignmentInsideSuspendReceiverLambda() throws {
        let source = try diffCaseSource("kuu_3301_interface_default_suspend_receiver_assignment.kt")

        try assertKotlinOutput(
            source,
            moduleName: "Kuu3301InterfaceDefaultSuspendReceiverAssignment",
            expected: "OK\nGeneric OK\n"
        )
    }

    @Test
    func testCanonicalDiffCaseInterfaceStoredPropertyDispatch() throws {
        let source = try diffCaseSource("interface_stored_property_dispatch.kt")

        try assertKotlinOutput(
            source,
            moduleName: "Bug141InterfaceStoredPropertyDispatch",
            expected:
                """
                1
                2
                42
                7
                42
                kotlin
                """ + "\n"
        )
    }

    @Test
    func testBug211CharSequenceLengthDispatchAcrossImplementations() throws {
        let source = """
        fun lengthOf(value: CharSequence): Int = value.length
        fun CharSequence.lengthViaExtension(): Int = this.length

        class CustomSequence(private val content: String) : CharSequence {
            override val length: Int
                get() = content.length
            override fun get(index: Int): Char = content[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                content.substring(startIndex, endIndex)
        }

        fun main() {
            println(lengthOf("hello"))
            println("world".lengthViaExtension())
            println(StringBuilder("xyz").lengthViaExtension())
            println(lengthOf(CustomSequence("custom")))
            println(CustomSequence("custom").lengthViaExtension())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug211CharSequenceLengthDispatch",
            expected: "5\n5\n3\n6\n6\n"
        )
    }

    @Test
    func testSourceStdlibTopLevelExtensionsKeepCharSequenceLengthItableSlot() throws {
        let source = """
        fun lengthOf(value: CharSequence): Int = value.length
        fun main() { println(lengthOf("ab")) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharSequenceLengthSourceStdlibItable",
            expected: "2\n",
            allowDefaultStdlibLibrary: false
        )
    }

    @Test
    func testKsp817CharSequenceGetDispatchAcrossImplementations() throws {
        let source = """
        fun getAt(value: CharSequence, index: Int): Char = value[index]

        class CustomSequence(private val content: String) : CharSequence {
            override val length: Int
                get() = content.length
            override fun get(index: Int): Char = content[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                content.substring(startIndex, endIndex)
        }

        fun main() {
            println(getAt("hello", 1))
            println(getAt(StringBuilder("xyz"), 2))
            println(getAt(CustomSequence("custom"), 3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Ksp817CharSequenceGetDispatch",
            expected: "e\nz\nt\n"
        )
    }

    @Test
    func testInterfaceDefaultPropertyGetterItableDispatchAcrossImplementations() throws {
        let source = """
        interface Greeter {
            val greeting: String
                get() = "Hello"
            fun greet(name: String): String = "$greeting, $name!"
        }

        class CustomGreeter : Greeter {
            override val greeting: String = "Hi"
        }

        class DefaultGreeter : Greeter

        interface BaseInterface {
            val baseProp: String
                get() = "baseDefault"
            val overriddenInChild: String
                get() = "baseOverridden"
        }

        interface ChildInterface : BaseInterface {
            val childProp: String
                get() = "childDefault"
            override val overriddenInChild: String
                get() = "childOverridden"
        }

        open class BaseClass : ChildInterface {
            override val baseProp: String
                get() = "classBaseProp"
        }

        class ConcreteClass : BaseClass()

        fun readBase(b: BaseInterface): String = "${b.baseProp};${b.overriddenInChild}"
        fun readChild(c: ChildInterface): String = c.childProp

        fun main() {
            val g1 = CustomGreeter()
            val g2 = DefaultGreeter()
            println(g1.greet("Alice"))
            println(g2.greet("Bob"))
            println(g1.greeting)
            println(g2.greeting)

            val obj = ConcreteClass()
            println(readBase(obj))
            println(readChild(obj))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InterfaceDefaultPropertyGetterDispatch",
            expected:
                """
                Hi, Alice!
                Hello, Bob!
                Hi
                Hello
                classBaseProp;childOverridden
                childDefault
                """ + "\n"
        )
    }

    @Test
    func testRepeatedInterfacePropertySetterDispatchAcrossImplementations() throws {
        let source = """
        package fixture

        interface Counter {
            val name: String
            var value: Int
        }

        class First(override val name: String, override var value: Int) : Counter
        class Second(override val name: String, override var value: Int) : Counter

        fun incrementTwice(counter: Counter) {
            counter.value = counter.value + 1
            counter.value = counter.value + 1
        }

        fun main() {
            val first: Counter = First("first", 1)
            val second: Counter = Second("second", 2)
            repeat(3) {
                incrementTwice(first)
                incrementTwice(second)
            }
            first.value = 7
            second.value = 8
            println("${first.name}:${first.value}")
            println("${second.name}:${second.value}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InterfacePropertySetterDispatch",
            expected: "first:7\nsecond:8\n"
        )
    }

    @Test
    func testGenericInterfacePropertySetterUsesErasureBridge() throws {
        let source = try diffCaseSource("kuu_2090_generic_interface_property_setter.kt")

        try assertKotlinOutput(
            source,
            moduleName: "GenericInterfacePropertySetterBridge",
            expected: "direct\nOK\n"
        )
    }

    @Test
    func testInterfacePropertySetterDispatchAcrossKlibBoundary() throws {
        let librarySource = """
        package fixture

        interface Counter {
            val name: String
            var value: Int
        }

        class First(override val name: String, override var value: Int) : Counter
        class Second(override val name: String, override var value: Int) : Counter
        """
        let consumerSource = """
        package consumer

        import fixture.Counter
        import fixture.First
        import fixture.Second

        fun incrementTwice(counter: Counter) {
            counter.value = counter.value + 1
            counter.value = counter.value + 1
        }

        fun main() {
            val first: Counter = First("first", 1)
            val second: Counter = Second("second", 2)
            repeat(3) {
                incrementTwice(first)
                incrementTwice(second)
            }
            first.value = 7
            second.value = 8
            println("${first.name}:${first.value}")
            println("${second.name}:${second.value}")
        }
        """

        try withCompiledLibrary(source: librarySource, moduleName: "InterfaceSetterLibrary") { libraryPath in
            try withTemporaryFile(contents: consumerSource) { consumerPath in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputBase) }

                let consumer = try makeArtifactCompilationContext(
                    inputs: [consumerPath],
                    moduleName: "InterfaceSetterConsumer",
                    emit: .executable,
                    outputPath: outputBase,
                    searchPaths: [libraryPath]
                )
                try runToLowering(consumer)
                try assertNoDiagnosticErrors(consumer)
                try CodegenPhase().run(consumer)
                try LinkPhase().run(consumer)

                let result = try CommandRunner.run(executable: outputBase, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "first:7\nsecond:8\n")
            }
        }
    }
}
#endif
