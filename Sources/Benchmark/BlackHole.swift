@inline(never)
public func blackHole<T>(_ value: T) {
  withUnsafePointer(to: value) { pointer in
    _ = pointer
  }
  _fixLifetime(value)
}
