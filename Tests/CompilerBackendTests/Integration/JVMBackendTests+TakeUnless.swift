#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func takeUnlessFiltersReceiverLikeUpstream(mode: EmitMode) throws {
        let source = """
        class Box(val value: Int) {
            fun passed(): Boolean = value > 0
        }

        fun main() {
            val dropped = "hello".takeUnless { it.length > 3 }
            val kept = "hi".takeUnless { it.length > 3 }
            println(dropped)
            println(kept)
            val nullable: String? = null
            println(nullable?.takeUnless { it.isEmpty() })
            val box = Box(1)
            println(box.takeUnless { it.passed() } == null)
            println(Box(-1).takeUnless { it.passed() }?.value)
            // callsInPlace(EXACTLY_ONCE) contracts make predicate-side
            // initialization visible for lambda-literal predicates, as in
            // stock kotlinc; opaque function values stay rejected.
            var x: Int
            "hi".takeUnless { x = 5; false }
            println(x)
            var y: Int
            "yo".takeIf { y = 7; true }
            println(y)
            // Assignment before a labeled return still counts on every path.
            var z: Int
            "hey".takeUnless zz@{ z = 3; return@zz true }
            println(z)
            // finally runs on the return path too, so its assignment counts.
            var w: Int
            "yo".takeUnless lit@{
                try {
                    if (it.isEmpty()) return@lit false
                } finally {
                    w = 9
                }
                true
            }
            println(w)
            // An assignment before a conditional return in finally still
            // counts on every path.
            var v: Int
            "hey".takeUnless lit2@{
                try {
                    if (it.isEmpty()) return@lit2 false
                } finally {
                    v = 5
                    if (it.length > 1) return@lit2 true
                }
                true
            }
            println(v)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact, "HelloKt"])
            #expect(execution.stdout == "null\nhi\nnull\ntrue\n-1\n5\n7\n3\n9\n5\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func takeUnlessEarlyReturnInsideTryReadsFinallyAssignment(mode: EmitMode) throws {
        // The empty receiver takes the labeled return inside try, so this
        // exercises the early-return path at runtime: finally still assigns
        // and the read afterwards observes it. Stock kotlinc prints a blank
        // line then 11; kswiftc must produce the same output.
        let source = """
        fun main() {
            var e: Int
            val r = "".takeUnless lit@{
                try {
                    if (it.isEmpty()) return@lit false
                } finally {
                    e = 11
                }
                true
            }
            println(r)
            println(e)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact, "HelloKt"])
            #expect(execution.stdout == "\n11\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func contractLambdaReturnInsideTryFinallyKeepsDefiniteAssignment(mode: EmitMode) throws {
        // buildList ships a callsInPlace(EXACTLY_ONCE) contract on master. A
        // labeled return inside try-with-finally must keep master's
        // fall-through definite-assignment behavior: the return-path tracking
        // added for takeUnless cannot see finally's effects and must not
        // reject this valid program. Compile-only: the JVM test artifact does
        // not bundle kotlin.collections.CollectionsKt for execution.
        let source = """
        fun main() {
            var x: Int
            buildList {
                try {
                    add(1)
                    return@buildList
                } finally {
                    x = 5
                }
            }
            println(x)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func takeUnlessContractRejectsUninitializedReadsLikeKotlinc(mode: EmitMode) throws {
        // Stock kotlinc rejects definite assignment through a safe call (the
        // lambda may never run) and through a labeled return that skips the
        // assignment; kswiftc must reject the same programs.
        let safeCall = """
        fun main() {
            var x: Int
            val s: String? = null
            s?.takeUnless { x = 5; false }
            println(x)
        }
        """
        let earlyReturn = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{ if (it.isEmpty()) return@lit false; x = 5; true }
            println(x)
        }
        """
        // A return inside finally completes the lambda before finally's
        // remaining assignments, so x may still be uninitialized.
        let finallyReturn = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    if (it.isEmpty()) return@lit false
                } finally {
                    if (it.length > 1) return@lit true
                    x = 5
                }
                true
            }
            println(x)
        }
        """
        // A safe call in finally may skip its lambda entirely, so an
        // assignment that only happens inside its argument is conditional;
        // kotlinc rejects the read.
        let finallySafeCall = """
        fun main() {
            var x: Int
            val s: String? = null
            "hi".takeUnless lit@{
                try {
                    if (it.isEmpty()) return@lit false
                } finally {
                    s?.takeUnless { x = 5; false }
                }
                true
            }
            println(x)
        }
        """
        try withWorkspace { root in
            for source in [safeCall, earlyReturn, finallyReturn, finallySafeCall] {
                let result = try compile(source, root: root, mode: mode)
                try #require(result.0 != 0, "expected definite-assignment failure")
                #expect(result.1.contains { $0.message.contains("must be initialized") })
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func contractLambdaReturnInsideTryFinallyRejectsUninitializedRead(mode: EmitMode) throws {
        // The early return inside try skips the assignment after the
        // try-with-finally, and finally does not assign x, so stock kotlinc
        // rejects the read. Compile-only, like the buildList test above.
        let buildListReturn = """
        fun main() {
            var x: Int
            buildList lit@{
                try {
                    if (isEmpty()) return@lit
                } finally {
                    println("f")
                }
                x = 5
            }
            println(x)
        }
        """
        let takeUnlessCatchReturn = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    println(it)
                } catch (e: Exception) {
                    return@lit false
                } finally {
                    println("f")
                }
                x = 5
                true
            }
            println(x)
        }
        """
        let nestedTryFinallyReturn = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    try {
                        if (it.isEmpty()) return@lit false
                    } finally {
                        println("inner")
                    }
                } finally {
                    println("outer")
                }
                x = 5
                true
            }
            println(x)
        }
        """
        try withWorkspace { root in
            for source in [buildListReturn, takeUnlessCatchReturn, nestedTryFinallyReturn] {
                let result = try compile(source, root: root, mode: mode)
                try #require(result.0 != 0, "expected definite-assignment failure")
                #expect(result.1.contains { $0.message.contains("must be initialized") })
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func contractLambdaReturnInsideNestedTryFinallyAcceptsOuterFinallyAssignment(mode: EmitMode) throws {
        let source = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    try {
                        if (it.isEmpty()) return@lit false
                    } finally {
                        println("inner")
                    }
                } finally {
                    x = 5
                }
                true
            }
            println(x)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func contractLambdaReturnInFinallyIsNotCreditedWithThatFinallyAssignment(mode: EmitMode) throws {
        // The return inside the inner finally's inline lambda leaves the
        // outer lambda before the inner finally's later assignment runs.
        let source = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    try {
                        println(it)
                    } finally {
                        "a".let { if (it.isEmpty()) return@lit false }
                        x = 5
                    }
                } finally {
                    println("cleanup")
                }
                true
            }
            println(x)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 != 0, "expected definite-assignment failure")
            #expect(result.1.contains { $0.message.contains("must be initialized") })
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func contractLambdaReturnCancelledByThrowingFinallyIsNotACompletionPath(mode: EmitMode) throws {
        let source = """
        fun main() {
            var x: Int
            "hi".takeUnless lit@{
                try {
                    if (it.isEmpty()) return@lit false
                } finally {
                    throw IllegalStateException("boom")
                }
                x = 5
                true
            }
            println(x)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
        }
    }
}
#endif
