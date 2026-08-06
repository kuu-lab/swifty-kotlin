#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-TYPE-004: kotlin.io.FileTreeWalk class
//
// Focused coverage for the synthetic `kotlin.io.FileTreeWalk` class.
// The class is registered by `HeaderHelpers+SyntheticFileTreeWalkStubs.swift`
// via `registerSyntheticFileTreeWalkStubs`, which also registers:
// - `FileTreeWalk.toList(): List<File>`     -> kk_file_tree_walk_to_list
// - `FileTreeWalk.maxDepth(Int): FileTreeWalk` -> kk_file_tree_walk_max_depth
// - `File.walkTopDown(): FileTreeWalk`      -> kk_file_walkTopDown
// - `File.walkBottomUp(): FileTreeWalk`     -> kk_file_walkBottomUp
// - `File.walk(FileWalkDirection): FileTreeWalk` -> kk_file_walk_with_direction

@Suite
struct FileTreeWalkClassTests {

    @Test
    func testFileTreeWalkSema() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
            """
            package sample1
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkTopDown()

            """,
            """
            package sample2
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkBottomUp()

            """,
            """
            package sample3
            import java.io.File

            fun f(): List<File> = File("/tmp").walkTopDown().toList()

            """,
            """
            package sample4
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkTopDown().maxDepth(2)

            """,
            """
            package sample5
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkTopDown().filter { it.isDirectory }

            """,
            """
            package sample6
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkTopDown().onEnter { it.name != "skip" }

            """,
            """
            package sample7
            import java.io.File
            import kotlin.io.FileTreeWalk

            fun f(): FileTreeWalk = File("/tmp").walkTopDown().onLeave { _ -> }

            """,
            """
            package sample8
            import java.io.File

            fun f() {
                File("/tmp").walkTopDown().maxDepth(3).forEach { println(it.name) }
            }

            """,
            """
            package sample9
            import java.io.File

            fun f() {
                File("/tmp")
                    .walkTopDown()
                    .maxDepth(5)
                    .onEnter { d -> d.name != "skip" }
                    .onLeave { _ -> }
                    .forEach { println(it.name) }
            }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            func diagnosticsForPath(_ path: String) -> [Diagnostic] {
                guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
                return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
            }

            // testFileTreeWalkIsRegisteredAsClass
            do {
                let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "kotlin.io.FileTreeWalk must be registered as a synthetic symbol"
                )
                #expect(
                    sema.symbols.symbol(symbol)?.kind == .class,
                    "FileTreeWalk must be registered as class"
                )
            }

            // testFileTreeWalkIsParentedToKotlinIOPackage
            do {
                let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let parent = try #require(
                    sema.symbols.parentSymbol(for: symbol),
                    "FileTreeWalk must be parented to the kotlin.io package"
                )
                let parentInfo = try #require(sema.symbols.symbol(parent))
                #expect(parentInfo.kind == .package)
                #expect(
                    parentInfo.fqName.map { interner.resolve($0) } ==
                    ["kotlin", "io"]
                )
            }

            // testFileTreeWalkHasPropertyTypeSet
            do {
                let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    sema.symbols.propertyType(for: symbol) != nil,
                    "FileTreeWalk must have a propertyType set"
                )
            }

            // testFileTreeWalkHasToListMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let walkSymbol = try #require(sema.symbols.lookup(fqName: walkFQName))
                let toListFQName = walkFQName + [interner.intern("toList")]
                let toListSymbol = try #require(
                    sema.symbols.lookupAll(fqName: toListFQName).first,
                    "FileTreeWalk.toList must be registered"
                )
                #expect(sema.symbols.symbol(toListSymbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: toListSymbol) ==
                    "kk_file_tree_walk_to_list"
                )
                let sig = try #require(sema.symbols.functionSignature(for: toListSymbol))
                #expect(sig.parameterTypes.count == 0)
                let walkType = sema.types.make(.classType(ClassType(
                    classSymbol: walkSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(sig.receiverType == walkType)
            }

            // testFileTreeWalkHasMaxDepthMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let maxDepthFQName = walkFQName + [interner.intern("maxDepth")]
                let maxDepthSymbol = try #require(
                    sema.symbols.lookupAll(fqName: maxDepthFQName).first,
                    "FileTreeWalk.maxDepth must be registered"
                )
                #expect(sema.symbols.symbol(maxDepthSymbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: maxDepthSymbol) ==
                    "kk_file_tree_walk_max_depth"
                )
                let sig = try #require(sema.symbols.functionSignature(for: maxDepthSymbol))
                #expect(sig.parameterTypes.count == 1)
                #expect(sig.parameterTypes.first == sema.types.intType)
            }

            // testWalkTopDownIsRegisteredOnFile
            do {
                let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
                let walkTopDownFQName = fileFQName + [interner.intern("walkTopDown")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: walkTopDownFQName).first,
                    "File.walkTopDown must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_walkTopDown"
                )
            }

            // testWalkBottomUpIsRegisteredOnFile
            do {
                let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
                let walkBottomUpFQName = fileFQName + [interner.intern("walkBottomUp")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: walkBottomUpFQName).first,
                    "File.walkBottomUp must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_walkBottomUp"
                )
            }

            // testWalkWithDirectionIsRegisteredOnFile
            do {
                let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
                let walkFQName = fileFQName + [interner.intern("walk")]
                // The overload with direction parameter (not the zero-arg walk())
                let overloads = sema.symbols.lookupAll(fqName: walkFQName)
                let directionOverload = overloads.first { sym in
                    guard let sig = sema.symbols.functionSignature(for: sym) else { return false }
                    return sig.parameterTypes.count == 1
                }
                #expect(directionOverload != nil, "File.walk(direction:) overload must be registered")
                if let sym = directionOverload {
                    #expect(
                        sema.symbols.externalLinkName(for: sym) ==
                        "kk_file_walk_with_direction"
                    )
                }
            }

            // testWalkTopDownReturnTypeIsFileTreeWalk
            do {
                let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
                let walkTopDownFQName = fileFQName + [interner.intern("walkTopDown")]
                let symbol = try #require(sema.symbols.lookupAll(fqName: walkTopDownFQName).first)
                let sig = try #require(sema.symbols.functionSignature(for: symbol))
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let walkClassSymbol = try #require(sema.symbols.lookup(fqName: walkFQName))
                let expectedReturnType = sema.types.make(.classType(ClassType(
                    classSymbol: walkClassSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(sig.returnType == expectedReturnType, "walkTopDown() must return FileTreeWalk")
            }

            // testWalkTopDownReturnsFileTreeWalk
            do {
                let samplePath = paths[1]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown() returning FileTreeWalk must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testWalkBottomUpReturnsFileTreeWalk
            do {
                let samplePath = paths[2]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkBottomUp() returning FileTreeWalk must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testFileTreeWalkToListChainResolves
            do {
                let samplePath = paths[3]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().toList() chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testFileTreeWalkMaxDepthChainResolves
            do {
                let samplePath = paths[4]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().maxDepth(2) chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testFileTreeWalkHasFilterMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let filterFQName = walkFQName + [interner.intern("filter")]
                let filterSymbol = try #require(
                    sema.symbols.lookupAll(fqName: filterFQName).first,
                    "FileTreeWalk.filter must be registered"
                )
                #expect(sema.symbols.symbol(filterSymbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: filterSymbol) ==
                    "kk_file_tree_walk_filter"
                )
                let sig = try #require(sema.symbols.functionSignature(for: filterSymbol))
                #expect(sig.parameterTypes.count == 1, "filter takes one predicate parameter")
            }

            // testFileTreeWalkHasOnEnterMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let onEnterFQName = walkFQName + [interner.intern("onEnter")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: onEnterFQName).first,
                    "FileTreeWalk.onEnter must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_tree_walk_onEnter"
                )
                let sig = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sig.parameterTypes.count == 1)
            }

            // testFileTreeWalkHasOnLeaveMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let onLeaveFQName = walkFQName + [interner.intern("onLeave")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: onLeaveFQName).first,
                    "FileTreeWalk.onLeave must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_tree_walk_onLeave"
                )
                let sig = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sig.parameterTypes.count == 1)
            }

            // testFileTreeWalkHasOnFailMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let onFailFQName = walkFQName + [interner.intern("onFail")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: onFailFQName).first,
                    "FileTreeWalk.onFail must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_tree_walk_onFail"
                )
                let sig = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sig.parameterTypes.count == 1, "onFail takes (File, Throwable) -> Unit")
            }

            // testFileTreeWalkHasForEachMember
            do {
                let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
                let forEachFQName = walkFQName + [interner.intern("forEach")]
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: forEachFQName).first,
                    "FileTreeWalk.forEach must be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .function)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_file_tree_walk_forEach"
                )
                let sig = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sig.parameterTypes.count == 1, "forEach takes (File) -> Unit")
                #expect(sig.returnType == sema.types.unitType, "forEach returns Unit")
            }

            // testFilterChainResolves
            do {
                let samplePath = paths[5]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().filter{} chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testOnEnterChainResolves
            do {
                let samplePath = paths[6]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().onEnter{} chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testOnLeaveChainResolves
            do {
                let samplePath = paths[7]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().onLeave{} chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testForEachTerminalChainResolves
            do {
                let samplePath = paths[8]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "walkTopDown().maxDepth().forEach{} chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // testFullBuilderChainResolves
            do {
                let samplePath = paths[9]
                let errors = diagnosticsForPath(samplePath).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "full builder chain must type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
#endif
