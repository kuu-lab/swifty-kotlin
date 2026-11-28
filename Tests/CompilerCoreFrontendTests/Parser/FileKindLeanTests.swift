#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", false, 0),
        ("import p.A", false, 0),
        ("fun f() {}; val x = 1", false, 0),
        ("println(1)", true, 0),
        ("import p.A\nprintln(1)", true, 0),
        ("package p\nprintln(1)", false, 1),
        ("println(1)\npackage p", false, 1),
        ("private package p\nprintln(1)", true, 1),
        ("@file:Suppress(\"unused\") package p\nprintln(1)", true, 1),
        ("private package p\nprintln(1)\npackage q", false, 2),
    ])
    func fileKindDependsOnStatementAndDirectPackage(source: String, script: Bool, packageHeaders: Int) {
        let parsed = parse(source)
        #expect(parsed.arena.node(parsed.root).kind == (script ? .script : .kotlinFile))
        #expect(parsed.arena.nodes.count { $0.kind == .packageHeader } == packageHeaders)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
