// EXPECT-REJECT
typealias Forward<T> = Consumer<out T>
typealias Consumer<T> = (T) -> Unit
