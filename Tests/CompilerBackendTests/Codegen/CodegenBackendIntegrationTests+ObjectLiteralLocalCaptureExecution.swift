// KSP-CAP-001: End-to-end execution tests for object-expression member
// function bodies capturing outer local variables/parameters. Property
// initializer capture already worked (inlined at the construction site);
// member function bodies are lowered as independent KIR functions, so the
// captured values must be threaded through instance fields instead.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCodegenObjectLiteralMemberFunctionCapturesValParameter() throws {
        let source = """
        interface Greeter {
            fun greet(): String
        }

        fun makeGreeter(name: String): Greeter {
            return object : Greeter {
                override fun greet(): String {
                    return "Hello, " + name
                }
            }
        }

        fun main() {
            val g = makeGreeter("World")
            println(g.greet())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureValParamExecution",
            expected: "Hello, World\n"
        )
    }

    func testCodegenObjectLiteralMemberFunctionCapturesAndMutatesVarAcrossCalls() throws {
        let source = """
        interface Counter {
            fun increment(): Int
        }

        fun makeCounter(start: Int): Counter {
            var count = start
            return object : Counter {
                override fun increment(): Int {
                    count = count + 1
                    return count
                }
            }
        }

        fun main() {
            val c = makeCounter(10)
            println(c.increment())
            println(c.increment())
            println(c.increment())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureVarMutationExecution",
            expected:
                """
                11
                12
                13
                """
                + "\n"
        )
    }

    // Verified against real kotlinc (kotlinc-jvm): a bare reference inside
    // the member function binds to the captured outer local, not the object
    // literal's own member of the same name -- the outer local wins, and the
    // object's own member would only be reachable via explicit `this.x`.
    func testCodegenObjectLiteralCapturedOuterLocalShadowsOwnPropertyOfSameName() throws {
        let source = """
        interface Box {
            fun value(): Int
        }

        fun makeBox(): Box {
            val x = 100
            return object : Box {
                val x = 5
                override fun value(): Int {
                    return x
                }
            }
        }

        fun main() {
            println(makeBox().value())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureShadowingExecution",
            expected: "100\n"
        )
    }

    func testCodegenObjectLiteralMemberFunctionCapturesFunctionTypedParameter() throws {
        let source = """
        interface Provider {
            fun provide(): Int
        }

        fun makeProvider(block: () -> Int): Provider {
            return object : Provider {
                override fun provide(): Int {
                    return block()
                }
            }
        }

        fun main() {
            val p = makeProvider { 42 }
            println(p.provide())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureLambdaParamExecution",
            expected: "42\n"
        )
    }

    func testCodegenObjectLiteralMultipleInstancesCaptureIndependentMutableState() throws {
        // Two separate makeCounter() calls must not share the same captured
        // `count` box -- each object literal instance captures its own.
        let source = """
        interface Counter {
            fun increment(): Int
        }

        fun makeCounter(start: Int): Counter {
            var count = start
            return object : Counter {
                override fun increment(): Int {
                    count = count + 1
                    return count
                }
            }
        }

        fun main() {
            val a = makeCounter(0)
            val b = makeCounter(100)
            println(a.increment())
            println(b.increment())
            println(a.increment())
            println(b.increment())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCaptureIndependentInstancesExecution",
            expected:
                """
                1
                101
                2
                102
                """
                + "\n"
        )
    }
}
