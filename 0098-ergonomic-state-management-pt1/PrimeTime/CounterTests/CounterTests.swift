import ComposableArchitecture
import ComposableArchitectureTestSupport
@testable import Counter
import PrimeAlert
import SnapshotTesting
import SwiftUI
import XCTest

class CounterTests: XCTestCase {
  func testSnapshots() {
    let store = Store(
      initialValue: CounterFeatureState(),
      reducer: counterFeatureReducer,
      environment: { _ in .sync { 17 } }
    )
    let view = CounterView(store: store)

    let vc = UIHostingController(rootView: view)
    vc.view.frame = UIScreen.main.bounds

    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.incrTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.incrTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.nthPrimeButtonTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    var expectation = self.expectation(description: "wait")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 0.5)
    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.alertDismissButtonTapped)
    expectation = self.expectation(description: "wait")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 0.5)
    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.isPrimeButtonTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    store.view.send(.primeModal(.saveFavoritePrimeTapped))
    assertSnapshot(matching: vc, as: .windowedImage)

    view.viewStore.send(.primeModalDismissed)
    assertSnapshot(matching: vc, as: .windowedImage)
  }

  func testIncrDecrButtonTapped() {
    assert(
      initialValue: CounterFeatureState(count: 2),
      reducer: counterFeatureReducer,
      environment: { _ in .sync { 17 } },
      steps:
      Step(.send, .counter(.incrTapped)) { $0.count = 3 },
      Step(.send, .counter(.incrTapped)) { $0.count = 4 },
      Step(.send, .counter(.decrTapped)) { $0.count = 3 }
    )
  }

  func testNthPrimeButtonHappyFlow() {
    assert(
      initialValue: CounterFeatureState(
        alertNthPrime: nil,
        count: 7,
        isNthPrimeRequestInFlight: false
      ),
      reducer: counterFeatureReducer,
      environment: { _ in .sync { 17 } },
      steps:
      Step(.send, .counter(CounterAction.requestNthPrime)) {
        $0.isNthPrimeRequestInFlight = true
      },
      Step(.receive, .counter(.nthPrimeResponse(n: 7, prime: 17))) {
        $0.alertNthPrime = PrimeAlert(n: $0.count, prime: 17)
        $0.isNthPrimeRequestInFlight = false
      },
      Step(.send, .counter(.alertDismissButtonTapped)) {
        $0.alertNthPrime = nil
      }
    )
  }

  func testNthPrimeButtonUnhappyFlow() {
    assert(
      initialValue: CounterFeatureState(
        alertNthPrime: nil,
        count: 7,
        isNthPrimeRequestInFlight: false
      ),
      reducer: counterFeatureReducer,
      environment: { _ in .sync { nil } },
      steps:
      Step(.send, .counter(.requestNthPrime)) {
        $0.isNthPrimeRequestInFlight = true
      },
      Step(.receive, .counter(.nthPrimeResponse(n: 7, prime: nil))) {
        $0.isNthPrimeRequestInFlight = false
      }
    )
  }

  func testPrimeModal() {
    assert(
      initialValue: CounterFeatureState(
        count: 1,
        favoritePrimes: [3, 5]
      ),
      reducer: counterFeatureReducer,
      environment: { _ in .sync { 17 } },
      steps:
      Step(.send, .counter(.incrTapped)) {
        $0.count = 2
      },
      Step(.send, .primeModal(.saveFavoritePrimeTapped)) {
        $0.favoritePrimes = [3, 5, 2]
      },
      Step(.send, .primeModal(.removeFavoritePrimeTapped)) {
        $0.favoritePrimes = [3, 5]
      }
    )
  }
}
