extension Validated {
  var valid: Valid? {
    guard case let .valid(value) = self else { return nil }
    return value
  }
  var isValid: Bool {
    return self.valid != nil
  }
  var invalid: [Invalid]? {
    guard case let .invalid(value) = self else { return nil }
    return value
  }
  var isInvalid: Bool {
    return self.invalid != nil
  }
}
extension Node {
  var element: (tag: String, attributes: [String: String], children: [Node])? {
    guard case let .element(value) = self else { return nil }
    return value
  }
  var isElement: Bool {
    return self.element != nil
  }
  var text: String? {
    guard case let .text(value) = self else { return nil }
    return value
  }
  var isText: Bool {
    return self.text != nil
  }
}
extension Loading {
  var loading: Void? {
    guard case .loading = self else { return nil }
    return ()
  }
  var isLoading: Bool {
    return self.loading != nil
  }
  var loaded: A? {
    guard case let .loaded(value) = self else { return nil }
    return value
  }
  var isLoaded: Bool {
    return self.loaded != nil
  }
  var cancelled: Void? {
    guard case .cancelled = self else { return nil }
    return ()
  }
  var isCancelled: Bool {
    return self.cancelled != nil
  }
}