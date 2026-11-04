import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4154: a bare `get`/`set` on the line after a member or top-level
/// property is Kotlin's default accessor spelling — the parser must attach it
/// as its own `.propertyAccessor` node so accessor diagnostics anchor at the
/// accessor keyword instead of collapsing onto the property's modifier range
/// (kotlinc 2.4.20 reports `protected override var w = 1\n    get` twice: once
/// on the modifier, once on `get`).
///
/// Inside a function body the same line is the next statement's ordinary
/// expression, and a `;` ends the declaration once it is followed by a
/// newline — or ends the accessor list outright after a bare accessor.
@Suite
struct BareAccessorParsingTests {
    @Test(arguments: [
        ("class C { var x = 1\n    get\n}", "member getter"),
        ("class C { var x = 1\n    set\n}", "member setter"),
        ("var top = 1\n    get", "top-level getter"),
        ("var top = 1\n    set", "top-level setter"),
        ("class C { val x = 1\n    set\n}", "val member setter"),
        ("interface I { val x: Int\n    get }", "interface getter"),
        ("class C { var x = 1; get }", "same-line semicolon getter"),
        ("class C { var x = 1; set }", "same-line semicolon setter"),
        ("class C { var x = 1\n    private get\n}", "prefixed getter"),
        ("class C { var x = 1\n    get() = x\n}", "bodied getter"),
    ])
    func bareAccessorAttachesToProperty(source: String, caseLabel: String) {
        let parsed = parse(source)
        #expect(
            parsed.arena.nodes.contains { $0.kind == .propertyAccessor },
            "\(caseLabel): expected a .propertyAccessor node"
        )
    }

    @Test(arguments: [
        ("fun f() { var x = 1\n    get\n}", "local getter"),
        ("fun f() { var x = 1\n    set\n}", "local setter"),
        ("fun f() { val x = 1\n    get\n}", "local getter on val"),
        ("class C { var x = 1;\n    get\n}", "semicolon then newline getter"),
        ("class C { var x = 1;\n    private get\n}", "semicolon then newline prefixed getter"),
        ("class C { var x = 1;\n    get() = x\n}", "semicolon then newline bodied getter"),
        ("class C { var x = get();\n    set\n}", "initializer call then setter"),
        ("class C { var x = get() {};\n    set\n}", "trailing lambda initializer then setter"),
        ("class C { var x = this.get();\n    set\n}", "member call initializer then setter"),
    ])
    func nextLineExpressionIsNotAbsorbed(source: String, caseLabel: String) {
        let parsed = parse(source)
        #expect(
            parsed.arena.nodes.allSatisfy { $0.kind != .propertyAccessor },
            "\(caseLabel): expected no .propertyAccessor node"
        )
    }

    @Test(arguments: [
        ("class C { var x = 1\n    get;\n    set\n}", 1, "bare getter semicolon then setter"),
        ("class C { var x = 1\n    get; set\n}", 1, "bare getter semicolon setter same line"),
        ("class C { var x = 1\n    get() = 1;\n    set\n}", 2, "bodied getter semicolon then bare setter"),
        ("class C { var x = 1\n    private get;\n    set\n}", 2, "prefixed getter semicolon then setter"),
        ("class C { var x: Int get() = x;\n    set(v) {}\n}", 1, "inline tail header keeps absorbing"),
        ("class C { var x = 1\n    get\n    set\n}", 2, "bare getter then bare setter"),
    ])
    func semicolonBoundaryAfterAccessor(source: String, expected: Int, caseLabel: String) {
        let parsed = parse(source)
        #expect(
            parsed.arena.nodes.count { $0.kind == .propertyAccessor } == expected,
            "\(caseLabel): expected \(expected) .propertyAccessor node(s)"
        )
    }

    @Test
    func bareGetterDeclAnchorsAtAccessorKeyword() throws {
        let source = """
        open class B { open var w: Int = 0 }
        class C : B() {
            protected override var w: Int = 1
                get
        }
        """
        let (ast, context) = try buildASTModule(from: source, includeStdlib: false)
        let property = try #require(memberProperty(named: "w", ofClass: "C", in: ast, interner: context.interner))
        let getter = try #require(property.getter)
        #expect(getter.body == .unit)
        // The accessor node's range must cover exactly the `get` keyword —
        // that is the anchor Sema uses for accessor-level diagnostics.
        let keyword = try #require(source.range(of: "get"))
        let start = source.utf8.distance(from: source.utf8.startIndex, to: keyword.lowerBound)
        #expect(getter.range.start.offset == start)
        #expect(getter.range.end.offset == start + 3)
    }

    @Test
    func bareSetterDeclAnchorsAtAccessorKeyword() throws {
        let source = """
        class C {
            var x = 1
                set
        }
        """
        let (ast, context) = try buildASTModule(from: source, includeStdlib: false)
        let property = try #require(memberProperty(named: "x", ofClass: "C", in: ast, interner: context.interner))
        let setter = try #require(property.setter)
        #expect(setter.body == .unit)
        let keyword = try #require(source.range(of: "set"))
        let start = source.utf8.distance(from: source.utf8.startIndex, to: keyword.lowerBound)
        #expect(setter.range.start.offset == start)
        #expect(setter.range.end.offset == start + 3)
    }
}
