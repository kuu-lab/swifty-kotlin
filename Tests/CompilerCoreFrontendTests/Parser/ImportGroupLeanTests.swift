#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", [Int](), [String]()),
        ("package p\nfun f() {}", [], []),
        ("import p.A\nimport p.B", [2], []),
        ("import p.A; import p.B;", [2], []),
        ("import p.A\npackage p\nimport p.B\nimport p.C", [1, 2], []),
        ("import p.A\n@file:Suppress(\"unused\") package p\nimport p.B", [1, 1], []),
        ("import p.A\nval x = 1\nimport p.B\nimport p.C", [1, 2], ["KSWIFTK-PARSE-0017", "KSWIFTK-PARSE-0017"]),
        ("import p.A\nval x = 1", [1], []),
        ("import p.A as ;\nimport p.B\npackage p", [2], ["KSWIFTK-PARSE-0005"]),
    ])
    func groupsConsecutiveImports(source: String, sizes: [Int], diagnosticCodes: [String]) throws {
        let parsed = parse(source)
        let groups = parsed.arena.children(of: parsed.root).compactMap { child -> NodeID? in
            guard case let .node(id) = child, parsed.arena.node(id).kind == .importList else { return nil }
            return id
        }
        #expect(groups.map { parsed.arena.children(of: $0).count } == sizes)
        #expect(parsed.diagnostics.diagnostics.map(\.code) == diagnosticCodes)
        for group in groups {
            let children = parsed.arena.children(of: group)
            let headers = children.compactMap { child -> SyntaxNode? in
                guard case let .node(id) = child else { return nil }
                return parsed.arena.node(id)
            }
            #expect(headers.count == children.count)
            #expect(headers.allSatisfy { $0.kind == .importHeader })
            let first = try #require(headers.first)
            let last = try #require(headers.last)
            #expect(parsed.arena.node(group).range == SourceRange(start: first.range.start, end: last.range.end))
        }
    }
}
#endif
