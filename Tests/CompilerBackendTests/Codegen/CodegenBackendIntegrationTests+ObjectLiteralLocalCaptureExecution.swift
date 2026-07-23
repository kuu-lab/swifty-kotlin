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

    // KSP-441: for-in over a generic object-expression Sequence/Iterator pipeline
    // whose `map` is inferred from the receiver's element type.
    func testCodegenForInOverGenericObjectExpressionSequence() throws {
        let source = """
        interface Seq<out T> {
            operator fun iterator(): Iterator<T>
        }

        fun <T, R> Seq<T>.mapManual(transform: (T) -> R): Seq<R> {
            val source = this
            val t = transform
            return object : Seq<R> {
                override fun iterator(): Iterator<R> {
                    val src = source
                    val tr = t
                    val it = src.iterator()
                    return object : Iterator<R> {
                        override fun hasNext(): Boolean = it.hasNext()
                        override fun next(): R = tr(it.next())
                    }
                }
            }
        }

        fun makeSeq(limit: Int): Seq<Int> = object : Seq<Int> {
            override fun iterator(): Iterator<Int> {
                val l = limit
                return object : Iterator<Int> {
                    var count = 0
                    override fun hasNext(): Boolean = count < l
                    override fun next(): Int {
                        val r = count
                        count++
                        return r
                    }
                }
            }
        }

        fun main() {
            val mapped = makeSeq(3).mapManual { it * 10 }
            for (i in mapped) {
                println(i)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForInGenericObjectExpressionSequenceExecution",
            expected:
                """
                0
                10
                20
                """
                + "\n"
        )
    }

    // KSP-441: trailing-lambda type inference for a member function of a
    // user-defined generic class must substitute the receiver's type args.
    func testCodegenGenericClassMemberTrailingLambdaTypeInference() throws {
        let source = """
        class Box<T>(val value: T) {
            fun <R> map(transform: (T) -> R): Box<R> = Box(transform(value))
        }

        fun main() {
            val b = Box(3).map { it * 10 }
            println(b.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericClassMemberTrailingLambdaInferenceExecution",
            expected: "30\n"
        )
    }
}
