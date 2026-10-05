@testable import CompilerCore
import Testing

@Suite
struct PublicInlineVisibilityTests {
    @Test
    func checksPublicAPIInlineCalls() throws {
        let samples: [(source: String, rejected: Bool)] = [
            ("""
            inline fun around(block: () -> Unit) { block() }
            private inline fun hidden(): Int {
                try { around { return 55 } } finally { println("hidden-finally") }
                return -1
            }
            inline fun exposed(): Int = hidden()
            fun main() { println(exposed()) }
            """, true),
            ("private fun hidden(): Int = 1\ninline fun exposed(): Int = hidden()", true),
            ("internal inline fun hidden(): Int = 1\ninline fun exposed(): Int = hidden()", true),
            ("internal fun hidden(): Int = 1\ninline fun exposed(): Int = hidden()", true),
            ("class Hidden private constructor()\ninline fun exposed(): Hidden = Hidden()", true),
            ("""
            private fun hidden(): Int = 1
            @PublishedApi internal inline fun exposed(): Int = hidden()
            """, true),
            ("""
            class Owner {
                private inline fun hidden(): Int = 1
                inline fun exposed(): Int = hidden()
            }
            """, true),
            ("""
            class Owner {
                internal fun hidden(): Int = 1
                inline fun exposed(): Int = this.hidden()
            }
            """, true),
            ("""
            private class Hidden { fun value(): Int = 1 }
            inline fun exposed(): Int = Hidden().value()
            """, true),
            ("""
            open class Owner {
                protected fun hidden(): Int = 1
                inline fun exposed(): Int = hidden()
            }
            """, true),
            ("""
            private fun hidden(): Int = 1
            inline fun exposed(block: () -> Int): Int = block()
            inline fun wrapper(): Int = exposed { hidden() }
            """, true),
            ("""
            private fun hidden(): Int = 1
            inline fun exposed(value: Int = hidden()): Int = value
            """, true),
            ("""
            @PublishedApi internal inline fun hidden(): Int = 55
            inline fun exposed(): Int = hidden()
            """, false),
            ("""
            @kotlin.PublishedApi internal fun hidden(): Int = 55
            inline fun exposed(): Int = hidden()
            """, false),
            ("""
            private inline fun hidden(): Int = 1
            internal inline fun exposed(): Int = hidden()
            """, false),
            ("""
            private inline fun hidden(): Int = 1
            private inline fun exposed(): Int = hidden()
            fun ordinary(): Int = hidden()
            """, false),
            ("""
            private class Owner {
                private fun hidden(): Int = 1
                inline fun exposed(): Int = hidden()
            }
            """, false),
            ("""
            internal class Owner {
                private fun hidden(): Int = 1
                inline fun exposed(): Int = hidden()
            }
            """, false),
            ("""
            @PublishedApi internal class Owner {
                @PublishedApi internal fun hidden(): Int = 1
                inline fun exposed(): Int = this.hidden()
            }
            """, false),
            ("""
            @PublishedApi internal class Owner
            inline fun exposed(): Any = Owner()
            """, false),
            ("""
            class Owner {
                class Nested @PublishedApi internal constructor()
            }
            inline fun exposed(): Any = Owner.Nested()
            """, false),
            ("""
            inline fun around(block: () -> Unit) { block() }
            fun helper(): Int = 1
            inline fun exposed(): Int = helper()
            """, false),
            ("""
            inline fun exposed(crossinline block: () -> Int): Int {
                val local = { block() }
                return local()
            }
            """, false),
            ("""
            @Suppress("NON_PUBLIC_CALL_FROM_PUBLIC_INLINE")
            inline fun exposed(): Int = hidden()
            private fun hidden(): Int = 1
            """, false),
        ]
        let sources = samples.enumerated().map { "package sample\($0.offset)\n" + $0.element.source }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, sample) in samples.enumerated() {
                let errors = diagnosticsForPath(paths[index], in: ctx).filter { $0.severity == .error }
                if sample.rejected {
                    #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0045" },
                            "Sample \(index): \(errors)")
                    #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0045" },
                            "Sample \(index): unrelated errors \(errors)")
                } else {
                    #expect(errors.isEmpty, "Sample \(index): \(errors)")
                }
            }
        }
    }
}
