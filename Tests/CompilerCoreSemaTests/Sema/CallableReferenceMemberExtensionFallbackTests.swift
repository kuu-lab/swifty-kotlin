import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct CallableReferenceMemberExtensionFallbackTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test
    func prefersTheMoreSpecificReceiverWithoutStdlib() throws {
        let source = """
        interface Visible
        class Box : Visible { fun render(): String = "member" }
        fun Visible.render(value: Int): String = "broad"
        fun Box.render(value: Int): String = "specific"
        val selected: (Box, Int) -> String = Box::render
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .callableRef(_, member, _) = expression,
                      context.interner.resolve(member) == "render" else { return nil }
                return ExprID(rawValue: Int32(index))
            }.first)
            let target = try #require(sema.bindings.identifierSymbol(for: reference))
            let receiver = try #require(sema.symbols.functionSignature(for: target)?.receiverType)
            guard case let .classType(owner) = sema.types.kind(of: receiver) else {
                Issue.record("Expected a nominal extension receiver")
                return
            }
            let symbol = try #require(sema.symbols.symbol(owner.classSymbol))
            #expect(context.interner.resolve(symbol.name) == "Box")
        }
    }

    @Test
    func selectsExtensionWhenMemberReturnTypeDoesNotMatch() throws {
        let source = """
        class Box { fun render(value: Int): Int = value }
        fun Box.render(value: Int): String = "extension"
        val selected: (Box, Int) -> String = Box::render
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .callableRef(_, member, _) = expression,
                      context.interner.resolve(member) == "render" else { return nil }
                return ExprID(rawValue: Int32(index))
            }.first)
            let target = try #require(sema.bindings.identifierSymbol(for: reference))
            let signature = try #require(sema.symbols.functionSignature(for: target))
            #expect(signature.returnType == sema.types.stringType)
        }
    }

    @Test(arguments: [false, true])
    func selectsApplicableMemberOrExtension(fromSource: Bool) throws {
        let fixture = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/callable_ref_overloaded_member_expected_type.kt"), encoding: .utf8)
        let source = fixture + """

        interface Visible
        class Box : Visible { fun render(): String = "member" }
        fun Box.render(): String = "shadowed"
        fun Visible.render(radix: Int): String = "less specific"
        fun Box.render(radix: Int): String = "extension"
        fun select(box: Box) {
            val unboundMember: (Box) -> String = Box::render
            val unboundExtension: (Box, Int) -> String = Box::render
            val boundMember: () -> String = box::render
            val boundExtension: (Int) -> String = box::render
        }
        """
        let context = try frontend(source, fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let references = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context),
                  case let .callableRef(_, member, _) = expression,
                  context.interner.resolve(member) == "render" else { return nil }
            return id
        }
        let signatures = references.compactMap { id in
            sema.bindings.identifierSymbol(for: id).flatMap { sema.symbols.functionSignature(for: $0) }
        }
        #expect(references.count == 4)
        #expect(signatures.filter { $0.parameterTypes.isEmpty }.count == 2)
        #expect(signatures.filter { $0.parameterTypes.count == 1 }.count == 2)
        #expect(signatures.filter { $0.parameterTypes.count == 1 }.allSatisfy {
            guard let receiver = $0.receiverType,
                  case let .classType(owner) = sema.types.kind(of: receiver),
                  let symbol = sema.symbols.symbol(owner.classSymbol) else { return false }
            return context.interner.resolve(symbol.name) == "Box"
        })
    }

    @Test(arguments: [false, true])
    func rejectsIncompatibleAndAmbiguousExtensions(fromSource: Bool) throws {
        let source = """
        interface A
        interface B
        class Box : A, B { fun render(): String = "member" }
        fun A.render(radix: Int): String = "a"
        fun B.render(radix: Int): String = "b"
        val incompatible: (Box, Boolean) -> String = Box::render
        val ambiguous: (Box, Int) -> String = Box::render
        """
        let context = try frontend(source, fromSource: fromSource)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" }, "\(errors)")
    }

    private func frontend(_ source: String, fromSource: Bool) throws -> CompilationContext {
        let path = "/tmp/callable-reference-member-extension-fallback.kt"
        let stdlib: String?
        if fromSource {
            stdlib = nil
        } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "CallableReferenceMemberExtensionFallback", inputs: [path],
            outputPath: "/tmp/callable-reference-member-extension-fallback", emit: .kirDump,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [path: Data(source.utf8)]).context
    }
}
