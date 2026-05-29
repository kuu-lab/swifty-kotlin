@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-022: `FileTreeWalk.iterator()` synthetic member.
final class FileTreeWalkIteratorFunctionTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected FileTreeWalk.iterator surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileTreeWalkIteratorMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fileTreeWalkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileTreeWalk"),
        ]))
        let fileTreeWalkType = sema.types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let iteratorSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ]))
        let iteratorOfFileType = sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(fileType)],
            nullability: .nonNull
        )))
        let iteratorMember = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("FileTreeWalk"),
            interner.intern("iterator"),
        ]))
        let iteratorInfo = try XCTUnwrap(sema.symbols.symbol(iteratorMember))

        XCTAssertEqual(iteratorInfo.kind, .function)
        XCTAssertTrue(iteratorInfo.flags.isSuperset(of: [.synthetic, .operatorFunction, .overrideMember]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: iteratorMember), fileTreeWalkSymbol)
        XCTAssertEqual(sema.symbols.externalLinkName(for: iteratorMember), "kk_file_tree_walk_iterator")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: iteratorMember))
        XCTAssertEqual(signature.receiverType, fileTreeWalkType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, iteratorOfFileType)
    }

    func testFileTreeWalkIteratorResolvesInSource() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.collections.Iterator
        import kotlin.io.FileTreeWalk

        fun fromWalk(walk: FileTreeWalk): Iterator<File> = walk.iterator()
        fun fromFile(file: File): Iterator<File> = file.walk().iterator()
        """)
    }
}
