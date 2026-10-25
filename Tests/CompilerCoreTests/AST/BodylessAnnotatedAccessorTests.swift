import Foundation
@testable import CompilerCore
import Testing

@Suite
struct BodylessAnnotatedAccessorTests {
    @Test(arguments: [
        "fun make() = object { var size = 1\n private set }",
        "enum class Probe { ENTRY { var size = 1\n private set } }",
    ])
    func visibilitySetterRemainsInAnonymousMemberBody(source: String) {
        let parsed = parse(source)
        #expect(!parsed.diagnostics.hasError, "\(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.count { $0.kind == .propertyAccessor } == 1)
    }

    @Test(arguments: [("get", ""), ("get", "() = 1"), ("set", ""), ("set", "(value) {}")])
    func accessorKeywordAnnotationNameIsNotAnAccessor(name: String, body: String) throws {
        let (ast, context) = try buildASTModule(from: """
        annotation class `\(name)`
        class Probe {
            var size = 1
                @`\(name)` \(name)\(body)
        }
        """, includeStdlib: false)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let property = try #require(memberProperty(named: "size", ofClass: "Probe", in: ast, interner: context.interner))
        let accessor = try #require(name == "get" ? property.getter : property.setter)
        #expect(accessor.annotations.map(\.name) == [name])
        #expect((accessor.body == .unit) == body.isEmpty)
    }

    @Test(arguments: ["get", "set"])
    func annotatedDefaultAccessorStaysOnExpectProperty(accessor: String) throws {
        let (ast, context) = try buildASTModule(from: """
        expect open class Probe {
            var size: Int
                @JvmName("accessSize")
                \(accessor)
            fun after()
        }
        """, includeStdlib: false)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let property = try #require(memberProperty(named: "size", ofClass: "Probe", in: ast, interner: context.interner))
        let parsedAccessor = try #require(accessor == "get" ? property.getter : property.setter)
        #expect(parsedAccessor.body == .unit)
        #expect(parsedAccessor.annotations.map(\.name) == ["JvmName"])
        #expect(firstFunDecl(named: "after", in: ast, interner: context.interner) != nil)
    }

    @Test
    func annotatedGetterAndSetterKeepTheirOwnAnnotations() throws {
        let (ast, context) = try buildASTModule(from: """
        expect class Probe {
            var size: Int
                @JvmName("readSize") get
                @JvmName("writeSize") set
        }
        """, includeStdlib: false)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let property = try #require(memberProperty(named: "size", ofClass: "Probe", in: ast, interner: context.interner))
        #expect(property.getter?.body == .unit)
        #expect(property.setter?.body == .unit)
        #expect(property.getter?.annotations.first?.arguments.first == "\"readSize\"")
        #expect(property.setter?.annotations.first?.arguments.first == "\"writeSize\"")
    }

    @Test
    func followingAnnotatedDeclarationIsNotAnAccessor() throws {
        let (ast, context) = try buildASTModule(from: """
        class Probe {
            val size = 1
            @Marker fun after() {}
        }
        """, includeStdlib: false)
        #expect(!context.diagnostics.hasError)
        let property = try #require(memberProperty(named: "size", ofClass: "Probe", in: ast, interner: context.interner))
        #expect(property.getter == nil)
        #expect(property.setter == nil)
        let after = try #require(firstFunDecl(named: "after", in: ast, interner: context.interner))
        #expect(after.annotations.map(\.name) == ["Marker"])
    }

    @Test(arguments: ["get", "set"])
    func followingAccessorNamedCallIsNotAbsorbed(name: String) {
        let parsed = parse("fun main() { val value = 1\n\(name)() }")
        #expect(!parsed.diagnostics.hasError)
        #expect(parsed.arena.nodes.count { $0.kind == .propertyAccessor } == 0)
        #expect(parsed.arena.nodes.count { $0.kind == .callExpr } == 1)
    }

    @Test(arguments: ["get", "set"], ["", "@Suppress(\"x\") "])
    func followingAccessorNamedReferenceRemainsLambdaResult(name: String, prefix: String) throws {
        let (ast, context) = try buildASTModule(from: """
        fun result(\(name): Int): Int = run {
            val unused = 0
            \(prefix)\(name)
        }
        """, includeStdlib: false)
        #expect(!context.diagnostics.hasError)
        #expect(ast.arena.exprs.contains { expression in
            guard case let .nameRef(reference, _) = expression else { return false }
            return context.interner.resolve(reference) == name
        })
    }

    @Test
    func annotatedExpectGetterLinksToActualProperty() throws {
        let sources = [
            """
            package kotlin.jvm
            annotation class JvmName(val name: String)
            """,
            """
            package repro
            import kotlin.jvm.JvmName
            expect open class Probe {
                val size: Int
                    @JvmName("size")
                    get
            }
            """,
            """
            package repro
            import kotlin.jvm.JvmName
            actual open class Probe {
                actual val size: Int
                    @JvmName("size")
                    get() = 0
            }
            """,
        ]
        let paths = sources.indices.map { "/virtual/accessor-\($0).kt" }
        let context = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let names = ["repro", "Probe", "size"].map(context.interner.intern)
        let properties = sema.symbols.lookupAll(fqName: names).compactMap { sema.symbols.symbol($0) }
        let expected = try #require(properties.first { $0.flags.contains(.expectDeclaration) })
        let actual = try #require(properties.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expected.id) == actual.id)
    }
}
