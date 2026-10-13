// The former sample did not compile on either diff target as written.
// Keep only the unresolved-name diagnostics until a target-supported logging surface exists.
fun main() {
    MDC.put("requestId", "abc-123")
    AdvancedLogger.getLogger("com.example.MyService")
    StructuredAppender.stdout()
}
