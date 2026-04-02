@testable import Runtime
import XCTest

private let runtimeBuildListLambda: @convention(c) (UnsafeMutablePointer<Int>?) -> Int = { _ in
    _ = kk_builder_list_add(1)
    _ = kk_builder_list_add(2)
    _ = kk_builder_list_add(3)
    return 0
}

final class RuntimeBuilderDSLTests: IsolatedRuntimeXCTestCase {
    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        return (0..<size).map { kk_list_get(listRaw, $0) }
    }

    func testBuildListCollectsElementsInOrder() {
        var thrown = 0
        let listRaw = kk_build_list(unsafeBitCast(runtimeBuildListLambda, to: Int.self), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(listRaw), [1, 2, 3])
    }

    func testBuildListWithCapacityUsesSameBuilderPath() {
        var thrown = 0
        let listRaw = kk_build_list_with_capacity(
            8,
            unsafeBitCast(runtimeBuildListLambda, to: Int.self),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(listElements(listRaw), [1, 2, 3])
    }

    func testBuildListWithNegativeCapacityThrows() {
        var thrown = 0
        let listRaw = kk_build_list_with_capacity(
            -1,
            unsafeBitCast(runtimeBuildListLambda, to: Int.self),
            &thrown
        )

        XCTAssertEqual(listRaw, 0)
        XCTAssertNotEqual(thrown, 0)
    }
}
