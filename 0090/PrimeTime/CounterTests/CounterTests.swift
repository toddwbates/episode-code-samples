import XCTest
@testable import Counter
import SnapshotTesting
@testable import ComposableArchitecture
import SwiftUI


extension Snapshotting where Value: UIViewController, Format == UIImage {
  static var windowedImage: Snapshotting {
    return Snapshotting<UIImage, UIImage>.image.asyncPullback { vc in
      Async<UIImage> { callback in
        UIView.setAnimationsEnabled(false)
        let window = UIApplication.shared.windows.first!
        window.rootViewController = vc
        DispatchQueue.main.async {
          let image = UIGraphicsImageRenderer(bounds: window.bounds).image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
          }
          callback(image)
          UIView.setAnimationsEnabled(true)
        }
      }
    }
  }
}


class CounterTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Current = .mock
  }

  func testSnapshots() {
    let store = Store(initialValue: CounterViewState(), reducer: counterViewReducer)
    let view = CounterView(store: store)
    let counterViewStore = store
      .scope(value: counterViewState, action: counterViewAction)
      .view(removeDuplicates: ==)
    let primeModalViewStore = store
      .scope(value: { ($0.primeModal) }, action: { .primeModal($0) })
      .view(removeDuplicates: ==)

    let vc = UIHostingController(rootView: view)
    vc.view.frame = UIScreen.main.bounds

    diffTool = "ksdiff"
//    record=true
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.incrTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.incrTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.nthPrimeButtonTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    var expectation = self.expectation(description: "wait")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 0.5)
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.alertDismissButtonTapped)
    expectation = self.expectation(description: "wait")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 0.5)
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.isPrimeButtonTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    primeModalViewStore.send(.saveFavoritePrimeTapped)
    assertSnapshot(matching: vc, as: .windowedImage)

    counterViewStore.send(.primeModalDismissed)
    assertSnapshot(matching: vc, as: .windowedImage)
  }

  func testIncrDecrButtonTapped() {
    assert(
      initialValue: CounterViewState(count: 2),
      reducer: counterViewReducer,
      steps:
      Step(.send, .counter(.incrTapped)) { $0.count = 3 },
      Step(.send, .counter(.incrTapped)) { $0.count = 4 },
      Step(.send, .counter(.decrTapped)) { $0.count = 3 }
    )
  }

  func testNthPrimeButtonHappyFlow() {
    Current.nthPrime = { _ in .sync { 17 } }

    assert(
      initialValue: CounterViewState(
        alertNthPrime: nil,
        isNthPrimeRequestInFlight: false
      ),
      reducer: counterViewReducer,
      steps:
      Step(.send, .counter(.requestNthPrime)) {
        $0.isNthPrimeRequestInFlight = true
      },
      Step(.receive, .counter(.nthPrimeResponse(17))) {
        $0.alertNthPrime = PrimeAlert(prime: 17)
        $0.isNthPrimeRequestInFlight = false
      },
      Step(.send, .counter(.alertDismissButtonTapped)) {
        $0.alertNthPrime = nil
      }
    )
  }

  func testNthPrimeButtonUnhappyFlow() {
    Current.nthPrime = { _ in .sync { nil } }

    assert(
      initialValue: CounterViewState(
        alertNthPrime: nil,
        isNthPrimeRequestInFlight: false
      ),
      reducer: counterViewReducer,
      steps:
      Step(.send, .counter(.requestNthPrime)) {
        $0.isNthPrimeRequestInFlight = true
      },
      Step(.receive, .counter(.nthPrimeResponse(nil))) {
        $0.isNthPrimeRequestInFlight = false
      }
    )
  }

  func testPrimeModal() {
    assert(
      initialValue: CounterViewState(
        count: 2,
        favoritePrimes: [3, 5]
      ),
      reducer: counterViewReducer,
      steps:
      Step(.send, .primeModal(.saveFavoritePrimeTapped)) {
        $0.favoritePrimes = [3, 5, 2]
      },
      Step(.send, .primeModal(.removeFavoritePrimeTapped)) {
        $0.favoritePrimes = [3, 5]
      }
    )
  }
}