//
// Copyright (c) 2022 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

@_spi(AdyenInternal) @testable import Adyen
@testable import AdyenComponents
import AdyenDropIn
import XCTest


class OnlineBankingComponentUITests: XCTestCase {

    private var paymentMethod: OnlineBankingPaymentMethod!
    private var context: AdyenContext!
    private var style: FormComponentStyle!
    private var sut: OnlineBankingComponent!
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        paymentMethod = try! Coder.decode(onlineBankingDictionary) as OnlineBankingPaymentMethod
        context = AdyenContext(apiContext: Dummy.apiContext, payment: nil)
        style = FormComponentStyle()
        sut = OnlineBankingComponent(paymentMethod: paymentMethod,
                                     context: context,
                                     configuration: OnlineBankingComponent.Configuration(style: style))
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        paymentMethod = nil
        context = nil
        style = nil
        sut = nil
        try super.tearDownWithError()
    }

    func testUIElements() {
        // Assert
        XCTAssertNotNil(sut.viewController.view.findView(with: "AdyenDropIn.OnlineBankingComponent.issuersList"))
        XCTAssertNotNil(sut.viewController.view.findView(with: "AdyenDropIn.OnlineBankingComponent.continueButtonItem"))
        XCTAssertNotNil(sut.viewController.view.findView(with: "AdyenDropIn.OnlineBankingComponent.OnlineBankingTAndCLabel"))
    }

    func testPressContinueButton() {
        // Given
        let delegate = PaymentComponentDelegateMock()
        sut.delegate = delegate

        // Then
        let button: SubmitButton! = sut.viewController.view.findView(with: "AdyenDropIn.OnlineBankingComponent.continueButtonItem.button")
        button.sendActions(for: .touchUpInside)

        let didContnueExpectation = XCTestExpectation(description: "Dummy Expectation")

        delegate.onDidSubmit = { data, component in
            // Assert
            XCTAssertTrue(component === self.sut)
            let details = data.paymentMethod as! OnlineBankingDetails
            XCTAssertEqual(details.type, .onlineBankingCZ)
            XCTAssertEqual(details.issuer!, "jp")
            self.sut.stopLoadingIfNeeded()
            didContnueExpectation.fulfill()
        }
        wait(for: .milliseconds(300))
    }

    func testExample() throws {
        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        func testContinueButtonLoading() {
            // Given
            UIApplication.shared.mainKeyWindow?.rootViewController = sut.viewController

            // Then
            let button: SubmitButton! = sut.viewController.view.findView(with: "AdyenDropIn.OnlineBankingComponent.continueButtonItem.button")

            // Assert
            XCTAssertFalse(button.showsActivityIndicator)

            // Then
            sut.startLoading(for: sut)
            wait(for: .milliseconds(300))

            //Assert
            XCTAssertTrue(button.showsActivityIndicator)

            // Then
            self.sut.stopLoadingIfNeeded()

            //Assert
            XCTAssertFalse(button.showsActivityIndicator)
        }
    }

}
