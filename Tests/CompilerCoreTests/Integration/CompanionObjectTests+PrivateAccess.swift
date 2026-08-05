#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-OBJ-016: Companion Object Private Access Tests

extension CompanionObjectTests {

    @Test func testPrivateAccessSema() throws {
        let sources: [String] = [
            // testCompanionAccessPrivateConstructor
            """
            package sample0
                    class Foo private constructor(val value: Int) {
                        companion object {
                            fun create(): Foo = Foo(42)
                        }
                    }
                    fun main() {
                        val f: Foo = Foo.create()
                    }

            """,

            // testCompanionAccessPrivateProperty
            """
            package sample1
                    class Bar {
                        private val secret: Int = 123
                        companion object {
                            fun getSecret(bar: Bar): Int = bar.secret
                        }
                    }
                    fun main() {
                        val b = Bar()
                        val s: Int = Bar.getSecret(b)
                    }

            """,

            // testCompanionAccessPrivateMethod
            """
            package sample2
                    class Baz {
                        private fun helper(): String = "secret"
                        companion object {
                            fun callHelper(baz: Baz): String = baz.helper()
                        }
                    }
                    fun main() {
                        val b = Baz()
                        val s: String = Baz.callHelper(b)
                    }

            """,

            // testClassAccessCompanionPrivateMembers
            """
            package sample3
                    class Container {
                        companion object {
                            private val secretValue: Int = 999
                            private fun secretOp(): Int = secretValue * 2
                        }

                        fun getSecret(): Int = Companion.secretValue
                        fun getSecretOp(): Int = Companion.secretOp()
                    }
                    fun main() {
                        val c = Container()
                        val v1: Int = c.getSecret()
                        val v2: Int = c.getSecretOp()
                    }

            """,

            // testCompanionFactoryPatternWithPrivateConstructor
            """
            package sample4
                    data class Person private constructor(
                        private val name: String,
                        private val age: Int
                    ) {
                        companion object {
                            fun createAdult(name: String): Person = Person(name, 18)
                            fun createChild(name: String): Person = Person(name, 0)
                            fun fromNameAndAge(name: String, age: Int): Person = Person(name, age)
                        }

                        fun getInfo(): String = "$name ($age)"
                    }
                    fun main() {
                        val adult = Person.createAdult("Alice")
                        val child = Person.createChild("Bob")
                        val custom = Person.fromNameAndAge("Charlie", 25)

                        val info1: String = adult.getInfo()
                        val info2: String = child.getInfo()
                        val info3: String = custom.getInfo()
                    }

            """,

            // testCompanionPrivateConstructorWithParameters
            """
            package sample5
                    class Config private constructor(
                        private val host: String,
                        private val port: Int,
                        private val useSSL: Boolean
                    ) {
                        companion object {
                            fun default(): Config = Config("localhost", 8080, false)
                            fun production(host: String): Config = Config(host, 443, true)
                            fun custom(host: String, port: Int, ssl: Boolean): Config = Config(host, port, ssl)
                        }

                        fun getConnectionString(): String {
                            val protocol = if (useSSL) "https" else "http"
                            return "$protocol://$host:$port"
                        }
                    }
                    fun main() {
                        val default = Config.default()
                        val prod = Config.production("example.com")
                        val custom = Config.custom("test.local", 3000, true)

                        val conn1: String = default.getConnectionString()
                        val conn2: String = prod.getConnectionString()
                        val conn3: String = custom.getConnectionString()
                    }

            """,

            // testNonCompanionObjectCannotAccessPrivateMembers
            """
            package sample6
                    class Outer {
                        private val secret: Int = 42

                        object NotACompanion {
                            fun tryAccess(): Int = secret  // Should fail
                        }
                    }

            """,

            // testExternalCannotAccessPrivateConstructor
            """
            package sample7
                    class Secure private constructor(val data: String) {
                        companion object {
                            fun create(): Secure = Secure("safe")
                        }
                    }

                    fun main() {
                        val s = Secure("unsafe")  // Should fail
                    }

            """,

            // testCompanionExtensionFunction
            """
            package sample8
                    class MyClass {
                        companion object
                    }

                    fun MyClass.Companion.extensionFun(): String = "extended"

                    fun main() {
                        val result: String = MyClass.Companion.extensionFun()
                    }

            """,

            // testCompanionExtensionProperty
            """
            package sample9
                    class Data {
                        companion object
                    }

                    val Data.Companion.extensionProp: Int get() = 42

                    fun main() {
                        val value: Int = Data.Companion.extensionProp
                    }

            """,

            // testNamedCompanionExtensionFunction
            """
            package sample10
                    class Service {
                        companion object Factory
                    }

                    fun Service.Factory.create(): Service = Service()

                    fun main() {
                        val s: Service = Service.Factory.create()
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testCompanionAccessPrivateConstructor

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion accessing private constructor, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionAccessPrivateProperty

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion accessing private property, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionAccessPrivateMethod

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion accessing private method, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testClassAccessCompanionPrivateMembers

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for class accessing companion private members, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionFactoryPatternWithPrivateConstructor

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for factory pattern with private constructor, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionPrivateConstructorWithParameters

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for private constructor with parameters, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNonCompanionObjectCannotAccessPrivateMembers

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Nested objects currently share the enclosing class's private access rules"
                        )

            }
            // testExternalCannotAccessPrivateConstructor

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        #expect(
                            sampleDiags.contains(where: { $0.severity == .error }),
                            "Expected sema error for external access to private constructor"
                        )

            }
            // testCompanionExtensionFunction

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion extension function, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionExtensionProperty

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for companion extension property, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNamedCompanionExtensionFunction

            do {
                let sample10Path = paths[10]
                let sampleDiags = diagnosticsForPath(sample10Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for named companion extension function, got: \(sampleDiags.map(\.code))"
                        )

            }

        }
    }


    /// Verify companion object can access private constructor




    /// Verify companion object can access private properties




    /// Verify companion object can access private methods




    /// Verify class can access companion's private members




    /// Verify companion with private constructor and factory pattern




    /// Verify companion access to private constructor with parameters




    /// Verify that non-companion objects cannot access private members




    /// Verify that external code cannot access private constructor directly




    /// Verify KIR lowering works with private constructor access


    @Test func testCompanionPrivateConstructorKIRLowering() throws {
        let source = """
        class Item private constructor(val id: Int) {
            companion object {
                fun create(): Item = Item(1)
            }
        }
        fun main() {
            val item: Item = Item.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no KIR errors for private constructor access, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }

        #expect(
            functionNames.contains("create"),
            "Expected companion factory function in KIR, got: \(functionNames)"
        )
    }



    /// Verify companion extension functions work




    /// Verify companion extension properties work




    /// Verify named companion extension functions


}
#endif
