@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrivateNestedWildcardImportTests {
    @Test
    func nestedClassifierStarImportIsAvailableInsideItsPrivateOwner() throws {
        let source = """
        package sample
        import sample.A.B.*

        class A {
            private class B { class D }
            fun make(): String {
                D()
                return "OK"
            }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let fileID = try #require(ctx.sourceManager.fileID(forPath: paths[0]))
            let scope = try #require(TypeCheckScopeBuilder().buildFileScopes(
                ast: ast,
                sema: sema,
                interner: ctx.interner,
                sourceManager: ctx.sourceManager
            )[fileID.rawValue])
            let nestedType = try #require(sema.symbols.lookup(fqName: ["sample", "A", "B", "D"].map(ctx.interner.intern)))
            #expect(scope.lookup(ctx.interner.intern("D")).contains(nestedType))
        }
    }

    @Test
    func nestedClassifierStarImportStillRejectsUseOutsideItsPrivateOwner() throws {
        let declaration = """
        package sample

        class A {
            private class B { class D }
            fun make(): String = D().toString()
        }
        """
        let usage = """
        package client
        import sample.A.B.*

        class Outside { fun outside(): Any = D() }
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            do { try runSema(ctx) } catch {}
            let sema = try #require(ctx.sema)
            let privateOwner = try #require(sema.symbols.lookup(fqName: ["sample", "A", "B"].map(ctx.interner.intern)))
            let nestedType = try #require(sema.symbols.lookup(fqName: ["sample", "A", "B", "D"].map(ctx.interner.intern)))
            #expect(sema.symbols.parentSymbol(for: nestedType) == privateOwner)
            let outside = try #require(sema.symbols.lookup(fqName: ["client", "Outside"].map(ctx.interner.intern)))
            #expect(sema.symbols.parentSymbol(for: outside) == nil)
            let fileID = try #require(ctx.sourceManager.fileID(forPath: paths[1]))
            let ast = try #require(ctx.ast)
            let scope = try #require(TypeCheckScopeBuilder().buildFileScopes(
                ast: ast,
                sema: sema,
                interner: ctx.interner,
                sourceManager: ctx.sourceManager
            )[fileID.rawValue])
            #expect(scope.lookup(ctx.interner.intern("D")).contains(nestedType))
            #expect(!VisibilityChecker(symbols: sema.symbols, sourceManager: ctx.sourceManager)
                .isAccessible(try #require(sema.symbols.symbol(nestedType)), fromFile: fileID, enclosingClass: nil))
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(!errors.isEmpty, "Expected the inaccessible nested type use to be rejected")
            #expect(errors.allSatisfy { ["KSWIFTK-SEMA-0040", "KSWIFTK-SEMA-0023"].contains($0.code) }, "Unexpected diagnostics: \(errors)")
        }
    }

    @Test
    func qualifiedNestedTypeControlNeedsNoImport() throws {
        let source = """
        package sample

        class A {
            private class B { class D }
            fun make(): String {
                B.D()
                return "OK"
            }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func explicitNestedClassifierImportIsCheckedAtItsUseSite() throws {
        let source = """
        package sample
        import sample.Obj.CInObj.Tt

        private object Obj {
            private class CInObj { class Tt }
            fun make(): Any {
                Tt()
                return "OK"
            }
        }

        fun box(): Any = Obj.make()
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
