package java.lang

public class Boolean private constructor() {
    public companion object {
        public val TRUE: kotlin.Boolean get() = true
        public val FALSE: kotlin.Boolean get() = false

        public fun parseBoolean(value: String?): kotlin.Boolean =
            value?.equals("true", ignoreCase = true) == true

        public fun valueOf(value: String?): kotlin.Boolean = parseBoolean(value)

        public fun valueOf(value: kotlin.Boolean): kotlin.Boolean = value

        public fun toString(value: kotlin.Boolean): String = value.toString()

        public fun hashCode(value: kotlin.Boolean): Int = if (value) 1231 else 1237

        public fun compare(first: kotlin.Boolean, second: kotlin.Boolean): Int =
            if (first == second) 0 else if (first) 1 else -1

        public fun logicalAnd(first: kotlin.Boolean, second: kotlin.Boolean): kotlin.Boolean = first && second

        public fun logicalOr(first: kotlin.Boolean, second: kotlin.Boolean): kotlin.Boolean = first || second

        public fun logicalXor(first: kotlin.Boolean, second: kotlin.Boolean): kotlin.Boolean = first xor second
    }
}
