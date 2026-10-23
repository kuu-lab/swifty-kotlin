package java.lang

public class Thread private constructor() {
    public companion object {
        private val current = Thread()

        public fun currentThread(): Thread = current
    }
}
