import Combine
import SwiftUI

public struct Effect<Output>: Publisher {
  public typealias Failure = Never

  let publisher: AnyPublisher<Output, Failure>

  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Failure == S.Failure, Output == S.Input {
    self.publisher.receive(subscriber: subscriber)
  }
}

extension Effect {
  public static func fireAndForget(work: @escaping () -> Void) -> Effect {
    return Deferred { () -> Empty<Output, Never> in
      work()
      return Empty(completeImmediately: true)
    }.eraseToEffect()
  }

  public static func sync(work: @escaping () -> Output) -> Effect {
    return Deferred {
      Just(work())
    }.eraseToEffect()
  }
}

extension Publisher where Failure == Never {
  public func eraseToEffect() -> Effect<Output> {
    return Effect(publisher: self.eraseToAnyPublisher())
  }
}

public typealias Reducer<Value, Action> = (inout Value, Action) -> [Effect<Action>]

public final class ViewStore<Value, Action>: ObservableObject {
  @Published public fileprivate(set) var value: Value
  fileprivate var viewCancellable: Cancellable?
  public let send: (Action) -> Void

  public init(
    initialValue: Value,
    send: @escaping (Action) -> Void
    ) {
    self.value = initialValue
    self.send = send
  }
}


public final class Store<Value, Action> {
  private let reducer: Reducer<Value, Action>
  @Published private(set) var value: Value
  private var viewCancellable: Cancellable?
  private var effectCancellables: Set<AnyCancellable> = []

  public init(initialValue: Value, reducer: @escaping Reducer<Value, Action>) {
    self.reducer = reducer
    self.value = initialValue
  }

//  func removeDuplicates() -> Store<Value, Action> {
//    
//  }

  private func send(_ action: Action) {
    let effects = self.reducer(&self.value, action)
    effects.forEach { effect in
      var effectCancellable: AnyCancellable?
      var didComplete = false
      effectCancellable = effect.sink(
        receiveCompletion: { [weak self] _ in
          didComplete = true
          guard let effectCancellable = effectCancellable else { return }
          self?.effectCancellables.remove(effectCancellable)
      },
        receiveValue: self.send
      )
      if !didComplete, let effectCancellable = effectCancellable {
        self.effectCancellables.insert(effectCancellable)
      }
    }
  }

//  public func view<LocalValue: Equatable, LocalAction>(
//    value toLocalValue: @escaping (Value) -> LocalValue,
//    action toGlobalAction: @escaping (LocalAction) -> Action
//  ) -> ViewStore<LocalValue, LocalAction> {
//    self.view(value: toLocalValue, action: toGlobalAction, removeDuplicates: ==)
//  }
//
//  public func view<LocalValue, LocalAction>(
//    value toLocalValue: @escaping (Value) -> LocalValue,
//    action toGlobalAction: @escaping (LocalAction) -> Action,
//    removeDuplicates isDuplicate: @escaping (LocalValue, LocalValue) -> Bool
//  ) -> ViewStore<LocalValue, LocalAction> {
//    let vs = ViewStore(
//      initialValue: toLocalValue(self.value),
//      send: { localAction in
//        // TODO: memory management
//        self.send(toGlobalAction(localAction))
//    })
//    vs.viewCancellable = self.$value
//      .map(toLocalValue)
//      .removeDuplicates(by: isDuplicate)
//      .sink { [weak vs] newValue in vs?.value = newValue }
//    return vs
//  }

  public func scope<LocalValue, LocalAction>(
    value toLocalValue: @escaping (Value) -> LocalValue,
    action toGlobalAction: @escaping (LocalAction) -> Action
  ) -> Store<LocalValue, LocalAction> {
    let localStore = Store<LocalValue, LocalAction>(
      initialValue: toLocalValue(self.value),
      reducer: { localValue, localAction in
        self.send(toGlobalAction(localAction))
        localValue = toLocalValue(self.value)
        return []
    }
    )
    localStore.viewCancellable = self.$value
//      .map(toLocalValue)
//      .removeDuplicates(by: isDuplicate)
      .sink { [weak localStore] newValue in
      localStore?.value = toLocalValue(newValue)
    }
    return localStore
  }
}

public func combine<Value, Action>(
  _ reducers: Reducer<Value, Action>...
) -> Reducer<Value, Action> {
  return { value, action in
    let effects = reducers.flatMap { $0(&value, action) }
    return effects
  }
}


extension Store where Value: Equatable {
  public var view: ViewStore<Value, Action> {
    self.view { $0.removeDuplicates() }
  }
}

extension Store {
  public func view<P: Publisher>(_ transform: (Published<Value>.Publisher) -> P) -> ViewStore<Value, Action> where P.Output == Value, P.Failure == Never {
    let vs = ViewStore(
      initialValue: self.value,
      send: self.send
    )
    vs.viewCancellable = transform(self.$value)
      .sink { [weak vs] newValue in vs?.value = newValue }
    return vs
  }


  public func view(removeDuplicates predicate: @escaping (Value, Value) -> Bool) -> ViewStore<Value, Action> {
    self.view { $0.removeDuplicates(by: predicate) }
  }
}

//struct CasePath<Root, Value> {
//  let extract: (Root) -> Value?
//  let embed: (Value) -> Root
//}

import CasePaths

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction>(
  _ reducer: @escaping Reducer<LocalValue, LocalAction>,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action: CasePath<GlobalAction, LocalAction>
) -> Reducer<GlobalValue, GlobalAction> {
  return { globalValue, globalAction in
    guard let localAction = action.extract(from: globalAction) else { return [] }
    let localEffects = reducer(&globalValue[keyPath: value], localAction)

    return localEffects.map { localEffect in
      localEffect.map(action.embed)
        .eraseToEffect()
    }
  }
}

public func logging<Value, Action>(
  _ reducer: @escaping Reducer<Value, Action>
) -> Reducer<Value, Action> {
  return { value, action in
    let effects = reducer(&value, action)
    let newValue = value
    return [.fireAndForget {
      print("Action: \(action)")
      print("Value:")
      dump(newValue)
      print("---")
      }] + effects
  }
}

extension Publisher {
  func cancellable<Id: Hashable>(id: Id) -> AnyPublisher<Output, Failure> {
    return Deferred { () -> PassthroughSubject<Output, Failure> in
      cancellables[id]?.cancel()
      let subject = PassthroughSubject<Output, Failure>()
      cancellables[id] = self.subscribe(subject)
      return subject
    }
    .eraseToAnyPublisher()
  }
}

private var cancellables: [AnyHashable: AnyCancellable] = [:]