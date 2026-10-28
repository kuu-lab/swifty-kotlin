#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-1927: retain the infix suffix after `when` without absorbing declarations.
@Suite
struct WhenInfixDeclarationBoundaryTests {
    struct TestCase: CustomTestStringConvertible {
        let member: Bool
        let following: String
        let expectedFunCount: Int
        let expectedClassCount: Int
        let expectedPropertyCount: Int

        var testDescription: String {
            "member=\(member), following='\(following)'"
        }
    }

    private static let testCases: [TestCase] = [
        TestCase(member: false, following: "fun after() = 4", expectedFunCount: 2, expectedClassCount: 0, expectedPropertyCount: 0),
        TestCase(member: false, following: "class After", expectedFunCount: 1, expectedClassCount: 1, expectedPropertyCount: 0),
        TestCase(member: false, following: "val after = 4", expectedFunCount: 1, expectedClassCount: 0, expectedPropertyCount: 1),
        TestCase(member: true, following: "fun after() = 4", expectedFunCount: 2, expectedClassCount: 1, expectedPropertyCount: 0),
        TestCase(member: true, following: "class After", expectedFunCount: 1, expectedClassCount: 2, expectedPropertyCount: 0),
        TestCase(member: true, following: "val after = 4", expectedFunCount: 1, expectedClassCount: 1, expectedPropertyCount: 1),
    ]

    @Test(arguments: testCases)
    func whenInfixKeepsItsSuffixAndFollowingDeclaration(testCase: TestCase) throws {
        let prefix = testCase.member ? "class Demo {\nprivate " : ""
        let function = """
        fun choose(flag: Boolean): Pair<Int, Int> = when (flag) {
            true -> 1
            false -> 2
        } to 3
        """
        let source = prefix + function + "\n" + testCase.following + (testCase.member ? "\n}" : "")
        let parsed = parse(source)
        let choose = try #require(parsed.arena.nodes.first { $0.kind == .funDecl })

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(choose.range.end.offset == prefix.utf8.count + function.utf8.count)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == testCase.expectedFunCount)
        #expect(parsed.arena.nodes.count { $0.kind == .classDecl } == testCase.expectedClassCount)
        #expect(parsed.arena.nodes.count { $0.kind == .propertyDecl } == testCase.expectedPropertyCount)
    }
}
#endif
