@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AssignmentSuppressAnnotationTests {
    @Test
    func suppressOnAssignmentStatementCoversAssignedValue() throws {
        let ctx = try semaContext(from: """
        class Storage(size: Int) {
            val keys: Array<String>
            val values: Array<String>

            init {
                @Suppress("UNCHECKED_CAST")
                keys = arrayOfNulls<String>(size) as Array<String>
                @Suppress("UNCHECKED_CAST")
                this.values = arrayOfNulls<String>(size) as Array<String>
            }
        }

        fun fill(size: Int, slots: Array<Any?>): Int {
            val local: Array<String>
            @Suppress("UNCHECKED_CAST")
            local = arrayOfNulls<String>(size) as Array<String>
            @Suppress("UNCHECKED_CAST")
            slots[0] = arrayOfNulls<String>(size) as Array<String>
            return local.size
        }
        """)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-UNCHECKED-CAST").isEmpty, "\(ctx.warningDiagnostics)")
    }

    @Test
    func unannotatedAssignmentStillWarns() throws {
        let ctx = try semaContext(from: """
        fun fill(size: Int): Int {
            val local: Array<String>
            local = arrayOfNulls<String>(size) as Array<String>
            return local.size
        }
        """)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-UNCHECKED-CAST").count == 1, "\(ctx.warningDiagnostics)")
    }
}
