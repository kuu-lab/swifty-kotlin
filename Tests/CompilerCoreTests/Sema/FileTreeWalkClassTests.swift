@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-TYPE-004: kotlin.io.FileTreeWalk class
//
// Focused coverage for the synthetic `kotlin.io.FileTreeWalk` class.
// The class is registered by `HeaderHelpers+SyntheticFileTreeWalkStubs.swift`
// via `registerSyntheticFileTreeWalkStubs`, which also registers:
// - `FileTreeWalk.toList(): List<File>`     → kk_file_tree_walk_to_list
// - `FileTreeWalk.maxDepth(Int): FileTreeWalk` → kk_file_tree_walk_max_depth
// - `File.walkTopDown(): FileTreeWalk`      → kk_file_walkTopDown
// - `File.walkBottomUp(): FileTreeWalk`     → kk_file_walkBottomUp
// - `File.walk(FileWalkDirection): FileTreeWalk` → kk_file_walk_with_direction

final class FileTreeWalkClassTests: XCTestCase {

    // MARK: Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do { try runSema(ctx) } catch {}
        return ctx
    }

    // MARK: - Class declaration shape

    func testFileTreeWalkIsRegisteredAsClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.FileTreeWalk must be registered as a synthetic symbol"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind,
            .class,
            "FileTreeWalk must be registered as class"
        )
    }

    func testFileTreeWalkIsParentedToKotlinIOPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let parent = try XCTUnwrap(
            sema.symbols.parentSymbol(for: symbol),
            "FileTreeWalk must be parented to the kotlin.io package"
        )
        let parentInfo = try XCTUnwrap(sema.symbols.symbol(parent))
        XCTAssertEqual(parentInfo.kind, .package)
        XCTAssertEqual(
            parentInfo.fqName.map { interner.resolve($0) },
            ["kotlin", "io"]
        )
    }

    func testFileTreeWalkHasPropertyTypeSet() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertNotNil(
            sema.symbols.propertyType(for: symbol),
            "FileTreeWalk must have a propertyType set"
        )
    }

    // MARK: - Member functions

    func testFileTreeWalkHasToListMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let walkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: walkFQName))
        let toListFQName = walkFQName + [interner.intern("toList")]
        let toListSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: toListFQName).first,
            "FileTreeWalk.toList must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(toListSymbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: toListSymbol),
            "kk_file_tree_walk_to_list"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: toListSymbol))
        XCTAssertEqual(sig.parameterTypes.count, 0)
        let walkType = sema.types.make(.classType(ClassType(
            classSymbol: walkSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.receiverType, walkType)
    }

    func testFileTreeWalkHasMaxDepthMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let maxDepthFQName = walkFQName + [interner.intern("maxDepth")]
        let maxDepthSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: maxDepthFQName).first,
            "FileTreeWalk.maxDepth must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(maxDepthSymbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: maxDepthSymbol),
            "kk_file_tree_walk_max_depth"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: maxDepthSymbol))
        XCTAssertEqual(sig.parameterTypes.count, 1)
        XCTAssertEqual(sig.parameterTypes.first, sema.types.intType)
    }

    // MARK: - File extension members

    func testWalkTopDownIsRegisteredOnFile() throws {
        let (sema, interner) = try makeSema()
        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let walkTopDownFQName = fileFQName + [interner.intern("walkTopDown")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: walkTopDownFQName).first,
            "File.walkTopDown must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_walkTopDown"
        )
    }

    func testWalkBottomUpIsRegisteredOnFile() throws {
        let (sema, interner) = try makeSema()
        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let walkBottomUpFQName = fileFQName + [interner.intern("walkBottomUp")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: walkBottomUpFQName).first,
            "File.walkBottomUp must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_walkBottomUp"
        )
    }

    func testWalkWithDirectionIsRegisteredOnFile() throws {
        let (sema, interner) = try makeSema()
        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let walkFQName = fileFQName + [interner.intern("walk")]
        // The overload with direction parameter (not the zero-arg walk())
        let overloads = sema.symbols.lookupAll(fqName: walkFQName)
        let directionOverload = overloads.first { sym in
            guard let sig = sema.symbols.functionSignature(for: sym) else { return false }
            return sig.parameterTypes.count == 1
        }
        XCTAssertNotNil(directionOverload, "File.walk(direction:) overload must be registered")
        if let sym = directionOverload {
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                "kk_file_walk_with_direction"
            )
        }
    }

    // MARK: - Return type correctness

    func testWalkTopDownReturnTypeIsFileTreeWalk() throws {
        let (sema, interner) = try makeSema()
        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let walkTopDownFQName = fileFQName + [interner.intern("walkTopDown")]
        let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: walkTopDownFQName).first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let walkClassSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: walkFQName))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: walkClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.returnType, expectedReturnType, "walkTopDown() must return FileTreeWalk")
    }

    // MARK: - Source-level type checking

    func testWalkTopDownReturnsFileTreeWalk() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkTopDown()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown() returning FileTreeWalk must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testWalkBottomUpReturnsFileTreeWalk() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkBottomUp()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkBottomUp() returning FileTreeWalk must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFileTreeWalkToListChainResolves() throws {
        let source = """
        import java.io.File

        fun f(): List<File> = File("/tmp").walkTopDown().toList()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().toList() chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFileTreeWalkMaxDepthChainResolves() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkTopDown().maxDepth(2)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().maxDepth(2) chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Builder member functions (filter / onEnter / onLeave / onFail / forEach)

    func testFileTreeWalkHasFilterMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let filterFQName = walkFQName + [interner.intern("filter")]
        let filterSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: filterFQName).first,
            "FileTreeWalk.filter must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(filterSymbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: filterSymbol),
            "kk_file_tree_walk_filter"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: filterSymbol))
        XCTAssertEqual(sig.parameterTypes.count, 1, "filter takes one predicate parameter")
    }

    func testFileTreeWalkHasOnEnterMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let onEnterFQName = walkFQName + [interner.intern("onEnter")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: onEnterFQName).first,
            "FileTreeWalk.onEnter must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_tree_walk_onEnter"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(sig.parameterTypes.count, 1)
    }

    func testFileTreeWalkHasOnLeaveMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let onLeaveFQName = walkFQName + [interner.intern("onLeave")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: onLeaveFQName).first,
            "FileTreeWalk.onLeave must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_tree_walk_onLeave"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(sig.parameterTypes.count, 1)
    }

    func testFileTreeWalkHasOnFailMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let onFailFQName = walkFQName + [interner.intern("onFail")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: onFailFQName).first,
            "FileTreeWalk.onFail must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_tree_walk_onFail"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(sig.parameterTypes.count, 1, "onFail takes (File, Throwable) -> Unit")
    }

    func testFileTreeWalkHasForEachMember() throws {
        let (sema, interner) = try makeSema()
        let walkFQName = ["kotlin", "io", "FileTreeWalk"].map { interner.intern($0) }
        let forEachFQName = walkFQName + [interner.intern("forEach")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: forEachFQName).first,
            "FileTreeWalk.forEach must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_file_tree_walk_forEach"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(sig.parameterTypes.count, 1, "forEach takes (File) -> Unit")
        XCTAssertEqual(sig.returnType, sema.types.unitType, "forEach returns Unit")
    }

    // MARK: - Builder chain type-checking

    func testFilterChainResolves() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkTopDown().filter { it.isDirectory }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().filter{} chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testOnEnterChainResolves() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkTopDown().onEnter { it.name != "skip" }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().onEnter{} chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testOnLeaveChainResolves() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileTreeWalk

        fun f(): FileTreeWalk = File("/tmp").walkTopDown().onLeave { _ -> }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().onLeave{} chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testForEachTerminalChainResolves() throws {
        let source = """
        import java.io.File

        fun f() {
            File("/tmp").walkTopDown().maxDepth(3).forEach { println(it.name) }
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "walkTopDown().maxDepth().forEach{} chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFullBuilderChainResolves() throws {
        let source = """
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
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "full builder chain must type-check, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
