@testable import CompilerCore

/// Search for a top-level function declaration by name in the given AST module.
func topLevelFunction(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> FunDecl? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl
            else {
                continue
            }
            if interner.resolve(function.name) == name {
                return function
            }
        }
    }
    return nil
}

/// Bundled stdlib sources share the AST arena with the test input, so expression
/// scans must skip expressions that originate from bundled `.kt` files.
func isUserSourceExpr(_ id: ExprID, in ctx: CompilationContext) -> Bool {
    guard let ast = ctx.ast, let range = ast.arena.exprRange(id) else { return false }
    return isUserSourceRange(range, in: ctx)
}

/// Whether a source range comes from a user file rather than a bundled
/// stdlib source sharing the arena.
func isUserSourceRange(_ range: SourceRange, in ctx: CompilationContext) -> Bool {
    ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib != true
}

/// Search for a top-level property declaration by name in the given AST module.
func topLevelProperty(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl
            else {
                continue
            }
            if interner.resolve(property.name) == name {
                return property
            }
        }
    }
    return nil
}

/// Names of the `fun` / `class` / `object` declarations directly at the top
/// level of `file`. Used by multi-file tests to assert that declarations landed
/// in the file they were written in.
func topLevelDeclNames(
    of file: ASTFile,
    in ast: ASTModule,
    interner: StringInterner
) -> [String] {
    file.topLevelDecls.compactMap { declID in
        switch ast.arena.decl(declID) {
        case let .funDecl(decl): return interner.resolve(decl.name)
        case let .classDecl(decl): return interner.resolve(decl.name)
        case let .objectDecl(decl): return interner.resolve(decl.name)
        default: return nil
        }
    }
}

// MARK: - Arena-wide declaration lookup

// These scan `arena.declarations()` (all origins, including bundled stdlib),
// unlike the `topLevel*` helpers above which only visit `file.topLevelDecls`.

func firstFunDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
    ast.arena.declarations().lazy.compactMap { decl -> FunDecl? in
        guard case let .funDecl(funDecl) = decl else { return nil }
        return funDecl
    }.first { interner.resolve($0.name) == name }
}

func firstClassDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> ClassDecl? {
    ast.arena.declarations().lazy.compactMap { decl -> ClassDecl? in
        guard case let .classDecl(classDecl) = decl else { return nil }
        return classDecl
    }.first { interner.resolve($0.name) == name }
}

func firstInterfaceDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> InterfaceDecl? {
    ast.arena.declarations().lazy.compactMap { decl -> InterfaceDecl? in
        guard case let .interfaceDecl(interfaceDecl) = decl else { return nil }
        return interfaceDecl
    }.first { interner.resolve($0.name) == name }
}

func firstObjectDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> ObjectDecl? {
    ast.arena.declarations().lazy.compactMap { decl -> ObjectDecl? in
        guard case let .objectDecl(objectDecl) = decl else { return nil }
        return objectDecl
    }.first { interner.resolve($0.name) == name }
}

func firstTypeAliasDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> TypeAliasDecl? {
    ast.arena.declarations().lazy.compactMap { decl -> TypeAliasDecl? in
        guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
        return typeAliasDecl
    }.first { interner.resolve($0.name) == name }
}

#if canImport(Testing)
import Foundation
import Testing

/// Run the frontend over a single in-memory Kotlin source and return its AST.
/// Pass `includeStdlib: false` for tests that enumerate declarations or
/// parameters without bundled-stdlib noise.
func buildASTModule(
    from source: String,
    includeStdlib: Bool = true
) throws -> (ASTModule, CompilationContext) {
    let ctx: CompilationContext
    if includeStdlib {
        ctx = makeContextFromSource(source)
    } else {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    }
    try runFrontend(ctx)
    return (try #require(ctx.ast), ctx)
}

/// Compile `sources` once through KIR. Intended for suite fixtures cached in
/// a static property so a single pipeline run is shared across tests.
func makeSharedKIRContext(sources: [String]) throws -> CompilationContext {
    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths)
        try runToKIR(ctx)
        result = ctx
    }
    return try #require(result)
}
#endif
