import CasePaths
import Combine
import SwiftUI

public typealias Reducer<Value, Action, Environment> = (inout Value, Action, Environment) -> [Effect<Action>]

public func combine<Value, Action, Environment>(
  _ reducers: Reducer<Value, Action, Environment>...
) -> Reducer<Value, Action, Environment> {
  return { value, action, environment in
    let effects = reducers.flatMap { $0(&value, action, environment) }
    return effects
  }
}

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction, LocalEnvironment, GlobalEnvironment>(
  _ reducer: @escaping Reducer<LocalValue, LocalAction, LocalEnvironment>,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action: CasePath<GlobalAction, LocalAction>,
  environment: @escaping (GlobalEnvironment) -> LocalEnvironment
) -> Reducer<GlobalValue, GlobalAction, GlobalEnvironment> {
  return { globalValue, globalAction, globalEnvironment in
    guard let localAction = action.extract(from: globalAction) else { return [] }
    let localEffects = reducer(&globalValue[keyPath: value], localAction, environment(globalEnvironment))
    
    return localEffects.map { localEffect in
      localEffect.map(action.embed)
        .eraseToEffect()
    }
  }
}

public func logging<Value, Action, Environment>(
  _ reducer: @escaping Reducer<Value, Action, Environment>
) -> Reducer<Value, Action, Environment> {
  return { value, action, environment in
    let effects = reducer(&value, action, environment)
    let newValue = value
    return [.fireAndForget {
      print("Action: \(action)")
      print("Value:")
      dump(newValue)
      print("---")
      }] + effects
  }
}

public final class ViewStore<Value, Action>: ObservableObject {
  @Published public fileprivate(set) var value: Value
  fileprivate var cancellable: Cancellable?
  public let send: (Action) -> Void
  
  public init(
    initialValue value: Value,
    send: @escaping (Action) -> Void
  ) {
    self.value = value
    self.send = send
  }
  
  //  public func send(_ action: Action) {
  //
  //  }
}

extension Store where Value: Equatable {
  public var view: ViewStore<Value, Action> {
    self.view(removeDuplicates: ==)
  }
}

extension Store {
  public func view(
    removeDuplicates predicate: @escaping (Value, Value) -> Bool
  ) -> ViewStore<Value, Action> {
    let viewStore = ViewStore(
      initialValue: self.value,
      send: self.send
    )
    
    viewStore.cancellable = self.$value
      .removeDuplicates(by: predicate)
      .sink(receiveValue: { [weak viewStore] value in
        viewStore?.value = value
        //        self
      })
    
    return viewStore
  }
}

public final class Store<Value, Action> /*: ObservableObject */ {
  private let reducer: Reducer<Value, Action, Any>
  private let environment: Any
  @Published private var value: Value
  private var effectCancellables: Set<AnyCancellable> = []
  
  public init<Environment>(
    initialValue: Value,
    reducer: @escaping Reducer<Value, Action, Environment>,
    environment: Environment
  ) {
    self.reducer = { value, action, environment in
      reducer(&value, action, environment as! Environment)
    }
    self.value = initialValue
    self.environment = environment
  }
  
  private func send(_ action: Action) {
    let effects = self.reducer(&self.value, action, self.environment)
    effects.forEach { effect in
      var effectCancellable: AnyCancellable?
      var didComplete = false
      effectCancellable = effect.sink(
        receiveCompletion: { [weak self, weak effectCancellable] _ in
          didComplete = true
          guard let effectCancellable = effectCancellable else { return }
          self?.effectCancellables.remove(effectCancellable)
        },
        receiveValue: { [weak self] in self?.send($0) }
      )
      if !didComplete, let effectCancellable = effectCancellable {
        self.effectCancellables.insert(effectCancellable)
      }
    }
  }
}

extension ViewStore {
  
  public func scope<LocalValue, LocalAction>(
    value toLocalValue: @escaping (Value) -> LocalValue,
    action toGlobalAction: @escaping (LocalAction) -> Action,
    removeDuplicates predicate: @escaping (LocalValue, LocalValue) -> Bool
  ) -> ViewStore<LocalValue, LocalAction> {
    let localStore = ViewStore<LocalValue, LocalAction>(
      initialValue: toLocalValue(self.value),
      send: { self.send(toGlobalAction($0)) }
    )
    
    localStore.cancellable = self.$value
      .sink(receiveValue: { [weak localStore] value in
        guard let localStore = localStore else { return }
        let localValue = toLocalValue(value)
        if !predicate(localStore.value, localValue) {
          localStore.value = localValue
        }
      })
    return localStore
  }
  
  public func scope<LocalValue, LocalAction>(
    value toLocalValue: @escaping (Value) -> LocalValue,
    action toGlobalAction: @escaping (LocalAction) -> Action
  )-> ViewStore<LocalValue, LocalAction> where LocalValue : Equatable {
    scope(value: toLocalValue, action: toGlobalAction, removeDuplicates: ==)
  }
  
}

extension ViewStore {
  public func bind<T>(_ get: KeyPath<Value,T>, _ set: CasePath<Action,T>)->Binding<T> {
    return Binding(get: { self.value[keyPath: get] },
                   set: { self.send( set.embed($0) ) })
  }
  
  public func curry(_ action:Action)->()->Void {
    return  { self.send( action ) }
  }

}
