@testable import CompilerCore
import Testing

@Suite
struct IntersectionSmartCastMemberDispatchTests {
    @Test
    func prefersMemberWithMoreSpecificReturnType() throws {
        // KUU-2104: the intersection member must dispatch through B.foo(): String.
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2104_intersection_smartcast_member_dispatch.kt", file: #filePath),
            expectedOutput: "OK\n"
        )
    }
}
