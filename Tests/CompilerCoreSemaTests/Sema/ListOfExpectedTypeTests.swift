#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-2029: expected result types must constrain listOf's arguments rather
/// than replace the inferred result without checking the source declaration.
@Suite
struct ListOfExpectedTypeTests {
    private let invalidSources = [
        "fun bad(): List<String> = listOf(1)",
        "fun bad(): List<String> = listOf(1, 2)",
        "fun bad() { val xs: List<String> = listOf(1) }",
        "fun take(xs: List<String>) {}\nfun bad() { take(listOf(1)) }",
        "fun bad(): List<String> = listOf(null)",
        "fun bad(): List<String> = listOf<Int>(1)",
        "fun bad(): List<String> = listOf<Int>()",
        "fun bad(): List<Int> = listOf<Int>(\"x\")",
        "fun bad(xs: Array<Int>): List<String> = listOf(*xs)",
        "fun bad(xs: Array<Int>): List<String> = listOf(\"x\", *xs)",
        "fun bad(): MutableList<String> = listOf(\"x\")",
        "class Box<T>\nfun bad(): Box<String> = listOf(\"x\")",
        "fun bad(): List<Byte> = listOf(128)",
        "fun bad(): List<Byte> = listOf(1L)",
        "fun bad(x: Int): List<Long> = listOf(x)",
        "fun bad(): List<Double> = listOf(1)",
        "fun bad(): Collection<String> = listOf(1)",
        "fun bad(x: Int): Iterable<Long> = listOf(x)",
    ]

    @Test
    func rejectsIncompatibleInput() throws {
        var source = ""
        var ranges: [Range<Int>] = []
        for (index, input) in invalidSources.enumerated() {
            let start = source.utf8.count
            source += input.replacingOccurrences(of: "bad", with: "bad\(index)")
                .replacingOccurrences(of: "take", with: "take\(index)") + "\n"
            ranges.append(start..<source.utf8.count)
        }
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        for (input, range) in zip(invalidSources, ranges) {
            #expect(errors.contains {
                ($0.code.hasPrefix("KSWIFTK-TYPE-") || $0.code == "KSWIFTK-SEMA-0002")
                    && $0.primaryRange.map { range.contains($0.start.offset) } == true
            }, "Expected type/overload mismatch for \(input): \(errors)")
        }
    }

    private let validSources = [
        "fun good(): List<String> = listOf(\"x\")",
        "fun good(): List<String> = listOf(\"x\", \"y\")",
        "fun good(): List<String> = listOf()",
        "fun good(): List<String> = listOf<String>()",
        "fun good(): List<String> = emptyList()",
        "fun good(): List<String?> = listOf(null, \"x\")",
        "fun good(): List<Any> = listOf<String>(\"x\")",
        "fun good(): List<Number> = listOf(1, 2)",
        "fun good(): List<Long> = listOf(1, -2)",
        "fun good(): List<Byte> = listOf(1, -2)",
        "fun good(): List<Short> = listOf(1, -2)",
        "fun good(): List<ULong> = listOf(1u, 2u)",
        "fun good(): List<Long> = listOf<Long>(1)",
        "fun good(): List<out Long> = listOf(1)",
        "fun good(): Collection<Long> = listOf(1)",
        "fun good(): Iterable<Byte> = listOf(1)",
        "fun good(): Collection<String> = listOf()",
        "fun good(xs: Array<String>): List<Array<String>> = listOf(element = xs)",
        "fun good(xs: Array<String>): List<String> = listOf(*xs)",
        "fun good(xs: Array<String>): List<String> = listOf(\"x\", *xs)",
        "fun good(xs: Array<String>): List<Any> = listOf<Any>(*xs)",
        "fun good(xs: Array<String>): List<String> = listOf(elements = xs)",
        "fun good(): List<String> = listOf(element = \"x\")",
        "fun <T> good(x: T): List<T> = listOf(x)",
        "fun good(): List<*> = listOf(1)",
        "fun good(): List<(Int) -> Int> = listOf({ it + 1 }, { it * 2 })",
        "fun take(xs: List<String>) {}\nfun good() { take(listOf(\"x\")) }",
    ]

    @Test
    func acceptsCompatibleInput() throws {
        let source = validSources.enumerated().map { index, input in
            input.replacingOccurrences(of: "good", with: "good\(index)")
                .replacingOccurrences(of: "take", with: "take\(index)")
        }.joined(separator: "\n")
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(source): \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitTypeArgumentPreservesCallResultAndBinding() throws {
        let ctx = makeContextFromSource("fun good(): List<Any> = listOf<String>(\"x\")")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(ast.arena.exprs.indices.compactMap { rawID -> ExprID? in
            let id = ExprID(rawValue: Int32(rawID))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .call(callee, _, _, _) = ast.arena.expr(id),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  name == ctx.interner.intern("listOf")
            else { return nil }
            return id
        }.first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(binding.substitutedTypeArguments == [sema.types.stringType])
        let result = try #require(sema.bindings.exprTypes[call])
        guard case let .classType(classType) = sema.types.kind(of: result) else {
            Issue.record("Expected List<String> result")
            return
        }
        #expect(classType.args == [.invariant(sema.types.stringType)])
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.valueParameterIsVararg == [false])
        #expect(binding.parameterMapping == [0: 0])
    }

    @Test
    func namedVarargExpandsArrayWhileNamedElementPreservesIt() throws {
        let ctx = makeContextFromSource("""
        fun spread(xs: Array<String>): List<String> = listOf(*xs)
        fun named(xs: Array<String>): List<String> = listOf(elements = xs)
        fun scalar(xs: Array<String>): List<Array<String>> = listOf(element = xs)
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        for name in ["spread", "named", "scalar"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_list_of"))
            #expect(callees.contains("__kk_array_size") == (name != "scalar"),
                    "\(name) must use the packed array count only for varargs: \(callees)")
        }
    }
}
#endif
