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
}
#endif
