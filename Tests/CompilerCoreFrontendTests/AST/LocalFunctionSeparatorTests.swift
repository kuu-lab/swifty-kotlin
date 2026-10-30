@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalFunctionSeparatorTests {
    @Test(arguments: [
        "fun value(): Int = 7; value()",
        "fun value(): Int = 7; val result = value()",
        "fun value(): Int = 7; fun after() = 8",
        "fun value(): Int = 7; class After",
        "fun value(): Int = 7;; value()",
        "fun value(): Int = 7;;",
        "fun value(): Int = 7;;\nvalue()",
        "fun value(): Int = 7; /*\n*/ value()",
        "fun value(): Int = if (true) { 7 } else { 8 }; value()",
        "fun value(): Int = ((7)); value()",
        "@Suppress(\"unused\") fun value(): Int = 7; value()",
    ], ["function", "localFunction", "lambda"])
    func rejectsSameLineFollower(body: String, context: String) throws {
        let diagnostics = try build(body, in: context)
        #expect(diagnostics.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-PARSE-0006"], "\(diagnostics)")
    }

    @Test(arguments: [
        "fun value(): Int = 7\nvalue()",
        "fun value(): Int = 7;\nvalue()",
        "fun value(): Int = 7\n; value()",
        "fun value(): Int = 7;\n; value()",
        "fun value(): Int = 7;",
        "fun value(): Int = ((7))",
        "fun value(): Int = 7 + (8)",
        "fun value(): Int = (7);\nvalue()",
        "@Suppress(\"unused\") fun value(): Int = 7;\nvalue()",
        "fun value(): Int { return 7 }; value()",
        "class Value; Value()",
        "val value = 7; value",
        "val value = object { fun first() = 7; fun second() = 8 }",
    ], ["function", "localFunction", "lambda"])
    func preservesValidSeparators(body: String, context: String) throws {
        let diagnostics = try build(body, in: context)
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
    }

    @Test(arguments: [
        "fun first() = 7; fun second() = 8",
        "class Value { fun first() = 7; fun second() = 8 }",
        "val value = object { fun first() = 7; fun second() = 8 }",
        "enum class Value { ENTRY { fun first() = 7; fun second() = 8 } }",
    ])
    func preservesNonlocalDeclarations(source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    private func build(_ body: String, in context: String) throws -> [Diagnostic] {
        let source: String
        switch context {
        case "localFunction": source = "fun host() { fun nested() { \(body) } }"
        case "lambda": source = "fun host() { val block = { \(body) } }"
        default: source = "fun host() { \(body) }"
        }
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        return context.diagnostics.diagnostics
    }
}
