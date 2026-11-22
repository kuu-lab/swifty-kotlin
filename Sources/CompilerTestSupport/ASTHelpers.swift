@testable import CompilerCore

private func firstTopLevelDecl<T>(
    in ast: ASTModule,
    matching transform: (Decl) -> T?
) -> T? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  let match = transform(decl)
            else {
                continue
            }
            return match
        }
    }
    return nil
}

func topLevelFunction(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> FunDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .funDecl(function) = decl,
              interner.resolve(function.name) == name
        else {
            return nil
        }
        return function
    }
}

func topLevelProperty(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .propertyDecl(property) = decl,
              interner.resolve(property.name) == name
        else {
            return nil
        }
        return property
    }
}

func memberProperty(
    named name: String,
    ofClass className: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .classDecl(classDecl) = decl,
              interner.resolve(classDecl.name) == className
        else {
            return nil
        }
        for propertyDeclID in classDecl.memberProperties {
            guard let propertyDecl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(property) = propertyDecl,
                  interner.resolve(property.name) == name
            else {
                continue
            }
            return property
        }
        return nil
    }
}

func isUserSourceExpr(_ id: ExprID, in ctx: CompilationContext) -> Bool {
    guard let ast = ctx.ast, let range = ast.arena.exprRange(id) else { return false }
    return isUserSourceRange(range, in: ctx)
}

func isUserSourceRange(_ range: SourceRange, in ctx: CompilationContext) -> Bool {
    ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib != true
}

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

func buildASTModule(
    from source: String,
    includeStdlib: Bool = true
) throws -> (ASTModule, CompilationContext) {
    let ctx: CompilationContext
    if includeStdlib {
        ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
    } else {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        ctx = makeCompilationContext(
            inputs: [fakePath], includeStdlib: false, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
    }
    try runFrontend(ctx)
    return (try #require(ctx.ast), ctx)
}

func makeSharedKIRContext(sources: [String]) throws -> CompilationContext {
    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: false)
        try runToKIR(ctx)
        result = ctx
    }
    return try #require(result)
}
#endif
