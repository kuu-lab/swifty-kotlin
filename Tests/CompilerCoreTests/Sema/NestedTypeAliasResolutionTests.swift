@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NestedTypeAliasResolutionTests {
    private func context(_ sources: [String]) throws -> CompilationContext {
        let paths = sources.indices.map { "/nested-typealias/input\($0).kt" }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runSema(ctx)
        return ctx
    }

    private func expectAlias(
        _ aliasPath: [String], target targetPath: [String],
        in ctx: CompilationContext, nullable: Bool = false
    ) throws -> ClassType {
        let sema = try #require(ctx.sema)
        let alias = try #require(sema.symbols.lookup(fqName: aliasPath.map(ctx.interner.intern)))
        let underlying = try #require(sema.symbols.typeAliasUnderlyingType(for: alias))
        guard case let .classType(classType) = sema.types.kind(of: underlying) else {
            Issue.record("Expected nominal alias, got \(sema.types.kind(of: underlying))")
            throw CompilerPipelineError.invalidInput("Expected nominal alias")
        }
        #expect(sema.symbols.symbol(classType.classSymbol)?.fqName == targetPath.map(ctx.interner.intern))
        #expect(classType.nullability == (nullable ? .nullable : .nonNull))
        #expect(sema.symbols.lookupAll(fqName: targetPath.map(ctx.interner.intern)).count == 1)
        return classType
    }

    @Test(arguments: [true, false])
    func aliasAndConstructorResolveRegardlessOfDeclarationOrder(aliasFirst: Bool) throws {
        let owner = "class Outer { class Nested { fun f(): String = \"n\" } }"
        let alias = "typealias Alias = Outer.Nested"
        let source = (aliasFirst ? [alias, owner] : [owner, alias]).joined(separator: "\n")
            + "\nfun result(): String = Alias().f()"
        let ctx = try context([source])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias(["Alias"], target: ["Outer", "Nested"], in: ctx)
    }

    @Test(arguments: [true, false])
    func importedNestedTypesResolveAcrossFiles(ownerFirst: Bool) throws {
        let owner = """
        package model
        class Outer { class Middle { class Nested<T>(val value: T) } }
        """
        let user = """
        package user
        import model.Outer as Renamed
        typealias Alias<T> = Renamed.Middle.Nested<T>
        typealias Nullable = model.Outer.Middle.Nested<String>?
        fun make(): Alias<String> = Alias("n")
        fun nullable(x: Nullable): Nullable = x
        """
        let ctx = try context(ownerFirst ? [owner, user] : [user, owner])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let generic = try expectAlias(["user", "Alias"], target: ["model", "Outer", "Middle", "Nested"], in: ctx)
        #expect(generic.args.count == 1)
        _ = try expectAlias(["user", "Nullable"], target: ["model", "Outer", "Middle", "Nested"], in: ctx, nullable: true)
    }

    @Test(arguments: ["import model.Outer", "import model.*", ""])
    func packageAndImportQualificationResolve(importLine: String) throws {
        let owner = "package model; class Outer { class Nested }"
        let package = importLine.isEmpty ? "model" : "user"
        let ctx = try context([
            "package \(package)\n\(importLine)\ntypealias Alias = Outer.Nested\nfun make(): Alias = Alias()",
            owner,
        ])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias([package, "Alias"], target: ["model", "Outer", "Nested"], in: ctx)
    }

    @Test func interfaceObjectEnumAndCompanionOwnersResolve() throws {
        let ctx = try context(["""
        typealias InInterface = Holder.Nested
        typealias InObject = Singleton.Nested
        typealias NestedObject = Singleton.Item
        typealias InEnum = Choice.Nested
        typealias InCompanion = Outer.Companion.Nested
        typealias InNamedCompanion = Named.Factory.Nested
        interface Holder { class Nested }
        object Singleton { class Nested; object Item }
        enum class Choice { ONLY; class Nested }
        class Outer { companion object { class Nested } }
        class Named { companion object Factory { class Nested } }
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        for (alias, target) in [
            ("InInterface", ["Holder", "Nested"]),
            ("InObject", ["Singleton", "Nested"]),
            ("NestedObject", ["Singleton", "Item"]),
            ("InEnum", ["Choice", "Nested"]),
            ("InCompanion", ["Outer", "Companion", "Nested"]),
            ("InNamedCompanion", ["Named", "Factory", "Nested"]),
        ] {
            _ = try expectAlias([alias], target: target, in: ctx)
        }
    }

    @Test func missingQualifierDoesNotBindSameShortName() throws {
        let ctx = try context(["""
        class Other { class Nested }
        class Outer
        typealias Alias = Outer.Nested
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
    }

    @Test func duplicateNestedDeclarationsRemainErrors() throws {
        let ctx = try context(["class Outer { class Nested; class Nested }"])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
    }
}
