#if canImport(Testing)
import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite
struct LocalClassSuperConstructorOuterCaptureTests {
    /// KUU-3226 (JetBrains kt4174): a local class's superclass constructor
    /// arguments are evaluated inside its generated `<init>` — an independent
    /// KIR function — so a bare reference to an enclosing-class member must
    /// record the outer receiver as captured, or `<init>` reads the member
    /// off its own (uninitialized) receiver and produces `null`.
    @Test(arguments: [false, true])
    func superConstructorArgumentCapturesMutableOuterReceiver(useLibrary: Bool) throws {
        let ctx = try makeContext(
            """
            open class C(val value: String)
            class B(var x: String) {
                fun box(): String {
                    class Y : C(x) {}
                    return Y().value
                }
            }
            """,
            useLibrary: useLibrary
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Local super ctor arg on outer member should resolve: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localClass = try classSymbol(named: "Y", sema: sema, interner: ctx.interner)

        // The bare `x` must resolve through the enclosing `this` receiver so
        // capture analysis records it (before the fix the ref bound straight
        // to `B.x` via scope, no receiver mark — and nothing was captured).
        let xRef = try #require(superConstructorArgumentNameRef(
            localClass: localClass, sema: sema, ast: ast
        ))
        let outerReceiver = try #require(
            sema.bindings.implicitReceiverOuterReceiver(for: xRef)
        )
        // The marked receiver is the enclosing class's `this` (its synthetic
        // receiver parameter symbol — absent from the symbol table by
        // design), not the local class's own.
        #expect(outerReceiver != localClass)

        // And that receiver must be a captured field on the local class.
        let captures = sema.bindings.objectLiteralCaptureSymbols(for: localClass)
        #expect(captures.contains(outerReceiver))
        #expect(sema.symbols.nominalLayout(for: localClass)?.fieldOffsets[outerReceiver] != nil)
        #expect(sema.bindings.capturedLocalType(for: outerReceiver) != nil)
    }

    /// Same capture path for a labeled `this@Outer` reference inside the
    /// superclass constructor argument (the label resolves against the kept
    /// enclosing receiver entries even with `implicitReceiverType` nil).
    @Test(arguments: [false, true])
    func superConstructorArgumentCapturesQualifiedOuterThis(useLibrary: Bool) throws {
        let ctx = try makeContext(
            """
            open class C(val value: String)
            class B(val x: String) {
                fun box(): String {
                    class Y : C(this@B.x) {}
                    return Y().value
                }
            }
            """,
            useLibrary: useLibrary
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "this@Outer in a local super ctor arg should resolve: \(errors)")

        let sema = try #require(ctx.sema)
        let outerClass = try classSymbol(named: "B", sema: sema, interner: ctx.interner)
        let localClass = try classSymbol(named: "Y", sema: sema, interner: ctx.interner)

        let captures = sema.bindings.objectLiteralCaptureSymbols(for: localClass)
        #expect(captures.contains(outerClass))
        #expect(sema.symbols.nominalLayout(for: localClass)?.fieldOffsets[outerClass] != nil)
    }

    private func makeContext(_ source: String, useLibrary: Bool) throws -> CompilationContext {
        if useLibrary {
            TestStdlibCache.shared.prepare()
        }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            stdlibLibraryPath: useLibrary ? CompilerOptions.defaultStdlibLibraryPath : nil
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func classSymbol(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        try #require(sema.symbols.symbols(ofKind: .class).first { symbol in
            sema.symbols.symbol(symbol).map { interner.resolve($0.name) == name } ?? false
        })
    }

    /// Finds the bare `x` name-reference inside `class Y : C(x)`'s superclass
    /// constructor arguments by walking the class decl registered for the
    /// local class symbol.
    private func superConstructorArgumentNameRef(
        localClass: SymbolID,
        sema: SemaModule,
        ast: ASTModule
    ) -> ExprID? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl
                else { continue }
                for memberFunctionID in classDecl.memberFunctions {
                    guard let memberDecl = ast.arena.decl(memberFunctionID),
                          case let .funDecl(functionDecl) = memberDecl,
                          case let .block(statements, _) = functionDecl.body
                    else { continue }
                    for statement in statements {
                        guard let expr = ast.arena.expr(statement),
                              case let .localNominalDecl(nestedDeclID, _) = expr,
                              sema.bindings.declSymbol(for: nestedDeclID) == localClass,
                              let nestedDecl = ast.arena.decl(nestedDeclID),
                              case let .classDecl(nestedClass) = nestedDecl,
                              let argExpr = nestedClass.superTypeEntries
                                  .flatMap(\.constructorArgs).map(\.expr).first,
                              let arg = ast.arena.expr(argExpr),
                              case .nameRef = arg
                        else { continue }
                        return argExpr
                    }
                }
            }
        }
        return nil
    }
}
#endif
