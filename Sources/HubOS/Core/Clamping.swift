extension Comparable {
    /// Constrains the value to `range`. Replaces the nested `min(max(_, lo), hi)`
    /// idiom the persisted-preference setters repeated for every clamped value.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
