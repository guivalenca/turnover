/// How big a conversion's output will be, or how long it will take. Always approximate.
public enum Estimate: Sendable, Hashable {
    /// The output's size, in bytes. Image targets carry this.
    case size(Int)
}
