@testable import CompilerCore
import Foundation
import XCTest

extension XCTestCase {
    func assertSequenceMemberResolves(
        source: String,
        memberName: String,
        expectedLinkName: String,
        diagnosticContext: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected \(diagnosticContext) surface to resolve cleanly, " +
                    "got: \(diagnosticSummary)",
                file: file, line: line
            )

            let sema = try XCTUnwrap(ctx.sema, file: file, line: line)
            let memberFQName = ["kotlin", "sequences", "Sequence", memberName]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains(expectedLinkName),
                "Expected '\(expectedLinkName)' in resolved link names " +
                    "\(links.sorted()) for \(diagnosticContext)",
                file: file, line: line
            )
        }
    }
}
