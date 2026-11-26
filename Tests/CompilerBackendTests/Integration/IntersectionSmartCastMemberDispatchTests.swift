@testable import CompilerCore
import Testing

@Suite
struct IntersectionSmartCastMemberDispatchTests {
    @Test
    func prefersMemberWithMoreSpecificReturnType() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2104_intersection_smartcast_member_dispatch.kt", file: #filePath),
            expectedOutput: "OK\n"
        )
    }
}
