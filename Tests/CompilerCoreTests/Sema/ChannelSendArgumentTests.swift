@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ChannelSendArgumentTests {
    private func check(
        _ source: String,
        artifact: Bool,
        expectedErrorLines: Set<Int>,
        expectedCodes: [Int: String] = [:]
    ) throws {
        if artifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: artifact
            )
            if artifact { #expect(ctx.options.stdlibLibraryPath != nil) }
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let lines = Set(errors.compactMap { $0.primaryRange?.start }.map {
                ctx.sourceManager.lineColumn(of: $0).line
            })
            #expect(lines == expectedErrorLines, "\(errors)")
            #expect(errors.allSatisfy { $0.primaryRange != nil }, "\(errors)")
            for (line, code) in expectedCodes {
                #expect(errors.contains { diagnostic in
                    diagnostic.code == code && diagnostic.primaryRange.map {
                        ctx.sourceManager.lineColumn(of: $0.start).line == line
                    } == true
                }, "\(errors)")
            }
        }
    }

    @Test(arguments: [false, true])
    func acceptsCompatibleElementsAndContextualArguments(artifact: Bool) throws {
        try check("""
        import kotlinx.coroutines.channels.Channel as KChannel
        suspend fun basic(ch: KChannel<Int>) { ch.send(1); ch.send(element = 2) }
        suspend fun nullable(ch: KChannel<String?>) { ch.send(null); ch.send("ok") }
        suspend fun projected(ch: KChannel<in Int>) { ch.send(1) }
        suspend fun projectedNullable(ch: KChannel<in String?>) { ch.send(null); ch.send("ok") }
        suspend fun output(ch: KChannel<out Int>) { ch.send(throw IllegalStateException()) }
        suspend fun star(ch: KChannel<*>) { ch.send(throw IllegalStateException()) }
        suspend fun <T> generic(ch: KChannel<T>, value: T) { ch.send(value) }
        suspend fun safe(ch: KChannel<Int>?): Unit? = ch?.send(1)
        suspend fun lambda(ch: KChannel<(Int) -> String>) { ch.send { it.toString() } }
        suspend fun narrow(ch: KChannel<Byte>) { ch.send(1) }
        suspend fun nested(ch: KChannel<List<Int>>) { ch.send(emptyList()) }
        class Channel { fun send(value: String): Int = 42 }
        fun user(ch: Channel): Int = ch.send("ok")
        suspend fun <C : KChannel<Int>> genericReceiver(ch: C) { ch.send(1) }
        """, artifact: artifact, expectedErrorLines: [])
    }

    @Test(arguments: [false, true])
    func rejectsIncompatibleElementsAndInvalidCalls(artifact: Bool) throws {
        try check("""
        import kotlinx.coroutines.channels.Channel as KChannel
        suspend fun wrong(ch: KChannel<Int>) { ch.send("wrong") }
        suspend fun nullValue(ch: KChannel<String>) { ch.send(null) }
        suspend fun projected(ch: KChannel<in Int>) { ch.send("wrong") }
        suspend fun projectedNull(ch: KChannel<in Int>) { ch.send(null) }
        suspend fun output(ch: KChannel<out Int>) { ch.send(1) }
        suspend fun star(ch: KChannel<*>) { ch.send(1) }
        suspend fun starNull(ch: KChannel<*>) { ch.send(null) }
        suspend fun <T> generic(ch: KChannel<T>) { ch.send(1) }
        suspend fun safe(ch: KChannel<Int>?) { ch?.send("wrong") }
        suspend fun unsafe(ch: KChannel<Int>?) { ch.send(1) }
        suspend fun explicit(ch: KChannel<Int>) { ch.send<Int>(1) }
        suspend fun named(ch: KChannel<Int>) { ch.send(value = 1) }
        suspend fun lambda(ch: KChannel<(Int) -> String>) { ch.send { 1 } }
        class Channel { fun send(value: String): Int = 42 }
        fun user(ch: Channel): Int = ch.send(1)
        suspend fun <C : KChannel<Int>> genericReceiver(ch: C) { ch.send("wrong") }
        """, artifact: artifact, expectedErrorLines: Set(2...14).union([16, 17]))
    }

    @Test(arguments: [false, true])
    func sendRequiresSuspensionContext(artifact: Bool) throws {
        try check("""
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.channels.Channel as KChannel
        fun ordinary(ch: KChannel<Int>) { ch.send(1) }
        fun nullable(ch: KChannel<Int>?) { ch?.send(1) }
        fun consume(action: () -> Unit) { action() }
        suspend fun nested(ch: KChannel<Int>) { consume { ch.send(1) } }
        suspend fun permitted(ch: KChannel<Int>) { ch.send(1) }
        fun coroutine(ch: KChannel<Int>) { runBlocking { ch.send(1) } }
        class Channel { fun send(value: Int) {} }
        fun user(ch: Channel) { ch.send(1) }
        """, artifact: artifact, expectedErrorLines: [3, 4, 6])
    }

    @Test(arguments: [false, true])
    func inapplicableMemberAllowsApplicableExtensions(artifact: Bool) throws {
        try check("""
        import kotlinx.coroutines.channels.Channel
        fun Channel<Int>.send(value: String): Int = 42
        fun Channel<Int>.send(action: (Int) -> String): Int = action(5).length
        fun Channel<Int>?.send(value: Boolean): Int = 44
        fun Channel<Int>.send(value: Int): Int = 45
        fun scalar(ch: Channel<Int>): Int = ch.send("x")
        fun named(ch: Channel<Int>): Int = ch.send(value = "x")
        fun lambda(ch: Channel<Int>): Int = ch.send { it.toString() }
        fun safe(ch: Channel<Int>?): Int? = ch?.send("x")
        fun nullable(ch: Channel<Int>?): Int = ch.send(true)
        suspend fun member(ch: Channel<Int>): Unit = ch.send(1)
        """, artifact: artifact, expectedErrorLines: [])
    }

    @Test(arguments: [false, true])
    func extensionAmbiguityVisibilityAndMemberPrecedenceArePreserved(artifact: Bool) throws {
        try check("""
        import kotlinx.coroutines.channels.Channel
        interface Left
        interface Right
        class Both : Left, Right
        fun Channel<Int>.send(value: Left): Int = 1
        fun Channel<Int>.send(value: Right): Int = 2
        class Holder { private fun Channel<Int>.send(value: String): Int = 3 }
        fun ambiguous(ch: Channel<Int>, value: Both) = ch.send(value)
        fun invisible(ch: Channel<Int>): Int = ch.send("x")
        fun wrong(ch: Channel<Int>): Int = ch.send(false)
        fun nonsuspend(ch: Channel<Int>) { ch.send(1) }
        """, artifact: artifact, expectedErrorLines: [8, 9, 10, 11],
            expectedCodes: [8: "KSWIFTK-SEMA-0003", 11: "KSWIFTK-SEMA-0308"])
    }
}
