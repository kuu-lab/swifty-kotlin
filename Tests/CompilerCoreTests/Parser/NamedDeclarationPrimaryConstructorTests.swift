#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NamedDeclarationPrimaryConstructorTests {
    @Test(arguments: [
        "object O() {}",
        "object O(value: Int) {}",
        "interface I() {}",
        "interface I(value: Int) {}",
    ])
    func rejectsPrimaryConstructorParametersOnObjectsAndInterfaces(source: String) {
        let parsed = parse("\(source)\nfun after() = 1")

        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0006"])
        #expect(parsed.arena.nodes.count { $0.kind == (source.hasPrefix("object") ? .objectDecl : .interfaceDecl) } == 1)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
    }

    @Test(arguments: [
        "class C() {}",
        "class C(value: Int) {}",
        "class C constructor() {}",
    ])
    func acceptsPrimaryConstructorParametersOnClasses(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .classDecl } == 1)
    }
}
#endif
