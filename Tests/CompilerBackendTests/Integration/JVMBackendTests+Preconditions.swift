#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibCheckAndErrorPreserveEvaluationAndFailures(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        let archive = try ZipArchive(data: Data(contentsOf: library))
        let entry = try #require(archive.entries.first { $0.name == "kotlin/PreconditionsKt.class" })
        var reader = JVMClassReader(bytes: Array(try archive.contents(of: entry)))
        let owner = try reader.read()
        #expect(owner.methods.contains { $0.name == "error" && $0.descriptor == "(Ljava/lang/Object;)Ljava/lang/Void;" })
        #expect(owner.methods.contains { $0.name == "check" && $0.descriptor == "(Z)V" })
        #expect(owner.methods.contains { $0.name == "check" && $0.descriptor == "(ZLkotlin/jvm/functions/Function0;)V" })
        try withWorkspace { root in
            let result = try compile("""
            var conditions = 0
            var messages = 0
            var strings = 0
            fun condition(value: Boolean): Boolean { conditions++; return value }
            class Message(val value: String) {
                override fun toString(): String { strings++; return value }
            }
            fun message(): Any { messages++; return Message("callback") }
            fun main() {
                check(condition(true))
                check(condition(true)) { messages++; Message("unused") }
                println(conditions)
                println(messages)
                println(strings)
                try { check(condition(false)) }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { check(condition(false)) { messages++; Message("detail") } }
                catch (failure: IllegalStateException) { println(failure.message) }
                println(conditions)
                println(messages)
                println(strings)
                val callback: () -> Any = { message() }
                check(true, callback)
                try { check(value = false, lazyMessage = callback) }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { error(Message("error detail")) }
                catch (failure: IllegalStateException) { println(failure.message) }
                println(messages)
                println(strings)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", artifact.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "2\n0\n0\nCheck failed.\ndetail\n4\n1\n1\ncallback\nerror detail\n2\n3\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibCheckAndErrorPreserveSmartCastsAndNonLocalReturns(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            class Checked { constructor(value: Int) { check(value == 11) } }
            fun checked(value: String?): Int { check(value != null); return value.length }
            fun checkedType(value: Any?): Int { check(value is String) { "type" }; return value.length }
            fun recovered(value: String?): Int { val text = value ?: error("missing"); return text.length }
            fun returned(): Int { check(false) { return 41 }; return 0 }
            fun shorted(): Int { check(true) { return 99 }; return 7 }
            fun finalized(): Int {
                try { check(false) { return 43 } }
                finally { println("finally") }
                return 0
            }
            fun main() {
                Checked(11)
                println(checked("abc"))
                println(checkedType("text"))
                println(recovered("ok"))
                try { recovered(null) }
                catch (failure: IllegalStateException) { println(failure.message) }
                println(returned())
                println(shorted())
                println(finalized())
                try { check(false) { return@check "local" } }
                catch (failure: IllegalStateException) { println(failure.message) }
                val failure: (Any) -> Nothing = ::error
                try { failure("reference") }
                catch (error: IllegalStateException) { println(error.message) }
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", artifact.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "3\n4\n2\nmissing\n41\n7\nfinally\n43\nlocal\nreference\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [
        "fun main() { error(null) }",
        "fun main() { check(false) { null } }",
        "fun main() { val value: Boolean? = true; check(value) }",
        "fun invalid(): Int { val callback: () -> Any = { return 1 }; check(false, callback); return 0 }; fun main() { println(invalid()) }",
    ])
    func ownStdlibCheckAndErrorRejectNullableInputsAndEscapingReturns(source: String) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [library.path])
            #expect(result.0 != 0)
            #expect(!result.1.isEmpty)
        }
    }
}
#endif
