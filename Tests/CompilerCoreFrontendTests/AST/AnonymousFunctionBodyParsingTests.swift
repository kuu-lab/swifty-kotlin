#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnonymousFunctionBodyParsingTests {
    @Test(arguments: [
        "fun main() { val g = fun(x: Int) = x * 2 }",
        "val f = fun() = 1",
        "val f = named@ fun(): String = \"ok\"",
    ])
    func acceptsPlainExpressionBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test func expressionBodyInsideArrayLambdaIsPreserved() throws {
        let (ast, context) = try buildASTModule(from: """
        fun main() {
            val funcs = Array(3) { fun(): Int = it * it }
        }
        """, includeStdlib: false)

        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0426"
        }, "\(context.diagnostics.diagnostics)")

        let snapshot = ast.arena.snapshot()
        let anonymousFunctionBodies = snapshot.expressions.enumerated().compactMap { entry -> FunctionBody? in
            let (index, expression) = entry
            let expressionID = ExprID(rawValue: Int32(index))
            guard snapshot.anonymousFunctionExpressions.contains(expressionID),
                  case let .localFunDecl(_, _, _, _, body, _, _, _, _) = expression
            else {
                return nil
            }
            return body
        }
        #expect(anonymousFunctionBodies.contains { body in
            if case .expr = body { return true }
            return false
        })
    }

    @Test(arguments: [
        "@file:OptIn(kotlin.ExperimentalContextParameters::class)\nval y = context(p: String) fun() = p",
        "val y = fun String.(): String = this",
        "@file:OptIn(kotlin.ExperimentalContextParameters::class)\nval y = context(p: String) fun String.() = p",
    ])
    func acceptsContextReceiverExpressionBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func newlineBetweenContextPrefixAndAnonymousFunctionParses() throws {
        let (_, context) = try buildASTModule(from: """
        @file:OptIn(kotlin.ExperimentalContextParameters::class)
        fun main() {
            with("O") {
                val f = context(a: String)
                fun(y: String): String = a + y
            }
        }
        """, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func newlineBetweenContextPrefixAndAnonymousFunctionParsesInUnbracedIfBranch() throws {
        let (_, context) = try buildASTModule(from: """
        @file:OptIn(kotlin.ExperimentalContextParameters::class)
        fun main() {
            with("O") {
                if (true) context(a: String)
                fun(y: String): String = a + y
            }
        }
        """, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func malformedContextPrefixInUnbracedIfBranchIsRejected() throws {
        let (_, context) = try buildASTModule(from: """
        fun context(x: Int) {}
        fun main() {
            if (true) context(42)
            fun(y: String): String = y
        }
        """, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0030"
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func newlineBetweenContextPrefixAndAnonymousFunctionParsesInTopLevelInitializer() throws {
        let (_, context) = try buildASTModule(from: """
        @file:OptIn(kotlin.ExperimentalContextParameters::class)
        val f = context(a: String)
        fun(y: String): String = a + y
        """, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func semicolonBetweenContextPrefixAndAnonymousFunctionDoesNotParseAsContextualFunction() throws {
        let (_, context) = try buildASTModule(from: """
        @file:OptIn(kotlin.ExperimentalContextParameters::class)
        fun main() {
            val f = context(a: String);
            fun(y: String): String = a + y
        }
        """, includeStdlib: false)

        #expect(context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val g = fun(x: Int) { return x * 2 } }",
        "val f = fun() { return 1 }",
    ])
    func acceptsBlockBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val f = fun(): Int",
        "val f = fun()",
        "val f = fun String.(x: Int): Int",
        "fun main() { val f = fun(): Int }",
        "fun main() { val f = l@ fun(): Int }",
        "fun main() { fun(): Int }",
        "fun foo(x: () -> Int) {}\nfun main() { foo(fun(): Int) }",
        "fun main() { val f = fun(): Int\n    f() }",
        "class C { fun m() { val h = fun(): Int } }",
        "fun main() { val f = fun(): List<Int> }",
        "fun main() { val f = fun(): Int; f() }",
        "fun foo(block: () -> () -> Int) {}\nfun main() { foo { fun(): Int } }",
    ])
    func bodilessAnonymousFunctionReportsMustHaveBody(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0426"
                && $0.message == "function 'anonymous' must have a body."
        }, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" || $0.code == "KSWIFTK-PARSE-0001"
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val f = fun <T>(x: T) = x",
        "val f = fun <T>(): Int",
        "fun main() { val f = fun <T> String.(x: T): T = x }",
    ])
    func genericAnonymousFunctionReportsProhibitedTypeParameters(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0001"
                && $0.message == "type parameters are prohibited here."
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val f = Array(3) { fun(): Int = it * it } }",
        "fun main() { val f = run { fun(): Int = 7 } }",
        "fun main() { listOf(1).forEach { fun(): Int = it } }",
        "fun main() { val f = { fun(x: Int): Int = x + 1 }() }",
        "fun main() { val f = Array(2) { val b = it + 1\n    fun(): Int = b * 2 } }",
    ])
    func lambdaBodyExpressionBodyAnonymousFunction(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val f = run { fun(): Int } }",
        "fun main() { listOf(1).forEach { fun(): Int } }",
    ])
    func lambdaBodyBodilessAnonymousFunctionReportsMustHaveBody(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0426"
                && $0.message == "function 'anonymous' must have a body."
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { fun Int.(): Int = this * 2 }",
        "fun main() { val f = { fun Int.(): Int = this * 2 } }",
        "fun main() { listOf(1).forEach { fun Int.(): Int = this * it } }",
        "fun main() { fun <T>(x: T) = x }",
    ])
    func statementPositionNamelessAnonymousFunctions(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        if source.contains("<T>") {
            #expect(context.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-PARSE-0001"
                    && $0.message == "type parameters are prohibited here."
            }, "\(context.diagnostics.diagnostics)")
        } else {
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
#endif
