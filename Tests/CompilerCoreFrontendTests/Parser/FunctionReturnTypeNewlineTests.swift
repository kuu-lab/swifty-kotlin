#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-4083: the `:` introducing a function return type may start a new line
/// (`fun R.unique()\n    : R`), which kotlinc accepts — clikt uses this style.
/// The break is only observable when the signature tail already holds tokens
/// before the newline (a qualified receiver name leaves `.unique()` there);
/// a `:` that is the tail's first token was always consumed.
@Suite
struct FunctionReturnTypeNewlineTests {
    @Test(arguments: [
        // The ticket repro: qualified receiver name + colon on the next line.
        """
        class R
        fun R.unique()
                : R {
            return this
        }
        """,
        // clikt shape: type parameters, generic receiver, generic return type.
        """
        class OptionWithValues<T>
        class TransformEach<T>
        fun <T> TransformEach<T>.unique()
                : OptionWithValues<T> {
            return this as OptionWithValues<T>
        }
        """,
        // The body brace on the line after the return type.
        """
        class R
        fun R.unique()
            : R
        {
            return this
        }
        """,
        // An expression body after the return type.
        """
        class R
        fun R.unique()
            : R = this
        """,
        // `=` on the line after the return type.
        """
        fun Int.twice()
            : Int
            = this * 2
        """,
        // A following declaration must not be swallowed.
        """
        class R
        fun R.unique()
            : R {
            return this
        }
        fun after() = 1
        val x = 2
        """,
        // Local functions inside a block follow the same rule.
        """
        fun outer() {
            class R
            fun R.unique()
                : R {
                return this
            }
        }
        """,
        // Class members too.
        """
        class C {
            fun f()
                : Int {
                return 1
            }
        }
        """,
    ])
    func returnTypeColonOnNextLineParses(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.contains { $0.kind == .funDecl })
    }

    @Test
    func returnTypeColonNewlineKeepsBodyInsideFunction() throws {
        let parsed = parse("""
        class R
        fun R.unique()
            : R {
            return this
        }
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        let index = try #require(parsed.arena.nodes.firstIndex { $0.kind == .funDecl })
        let children = parsed.arena.children(of: NodeID(rawValue: Int32(index)))
        #expect(children.contains { child in
            guard case let .node(id) = child else { return false }
            return parsed.arena.node(id).kind == .block
        })
    }

    @Test
    func colonAfterExpressionBodyStaysOutsideFunction() throws {
        // A `:` on the next line is only the return-type colon before `=`;
        // after an expression body it must not be absorbed into the function.
        // (The driver rejects the stray tokens with KSWIFTK-PARSE-0025; at
        // parse level the check is that `fun f` ends before the `:`.)
        let parsed = parse("""
        fun f() = 1
            : Int
        fun g() = 2
        """)

        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 2)
        let colonToken = try #require(parsed.tokens.first { $0.kind == .symbol(.colon) })
        let colonOffset = colonToken.range.start.offset
        let fIndex = try #require(parsed.arena.nodes.firstIndex { $0.kind == .funDecl })
        #expect(parsed.arena.nodes[fIndex].range.end.offset <= colonOffset)
    }
}
#endif
