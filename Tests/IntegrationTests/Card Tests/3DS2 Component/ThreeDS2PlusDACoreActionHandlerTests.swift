//
// Copyright (c) 2024 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import XCTest

#if canImport(AdyenAuthentication)
    @_spi(AdyenInternal) @testable import Adyen
    import Adyen3DS2
    @_spi(AdyenInternal) @testable import AdyenActions
    import AdyenAuthentication
    import Foundation
    import UIKit

    @available(iOS 16.0, *)
    final class ThreeDS2PlusDACoreActionHandlerTests: XCTestCase {
        var authenticationRequestParameters: AnyAuthenticationRequestParameters!

        var fingerprintAction: ThreeDS2FingerprintAction!

        var challengeAction: ThreeDS2ChallengeAction!
        
        static let relyingPartyIdentifier = "test-authentication-adyen.netlify.app"
        
        static var delegatedAuthenticationConfigurations: ThreeDS2Component.Configuration.DelegatedAuthentication {
            .init(relyingPartyIdentifier: relyingPartyIdentifier)
        }
    
        lazy var analyticsEvent: Analytics.Event = .init(
            component: "Dropin",
            flavor: .dropin,
            context: Dummy.apiContext
        )
        
        override func setUp() {
            super.setUp()

            authenticationRequestParameters = AuthenticationRequestParametersMock(
                deviceInformation: "device_info",
                sdkApplicationIdentifier: "sdkApplicationIdentifier",
                sdkTransactionIdentifier: "sdkTransactionIdentifier",
                sdkReferenceNumber: "sdkReferenceNumber",
                sdkEphemeralPublicKey: sdkPublicKey,
                messageVersion: "messageVersion"
            )

            fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: fingerprintToken,
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )

            challengeAction = ThreeDS2ChallengeAction(challengeToken: challengeToken, authorisationToken: "authToken", paymentData: "paymentData")
        }

        func testSettingThreeDSRequestorAppURL() throws {
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                appearanceConfiguration: ADYAppearanceConfiguration(),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations
            )
            sut.threeDSRequestorAppURL = URL(string: "https://google.com")
            XCTAssertEqual(sut.threeDSRequestorAppURL, URL(string: "https://google.com"))
        }
        
        func testWrappedComponent() throws {
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                appearanceConfiguration: ADYAppearanceConfiguration(),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations
            )
            XCTAssertEqual(sut.context.apiContext.clientKey, Dummy.apiContext.clientKey)
        
            XCTAssertEqual(sut.context.apiContext.environment.baseURL, Dummy.apiContext.environment.baseURL)

            sut._isDropIn = false
            XCTAssertEqual(sut._isDropIn, false)

            sut._isDropIn = true
            XCTAssertEqual(sut._isDropIn, true)
        }

        func testFingerprintFlowSuccess() throws {
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
        
            let expectedFingerprint = try ThreeDS2Component.Fingerprint(
                authenticationRequestParameters: authenticationRequestParameters,
                delegatedAuthenticationSDKOutput: nil,
                deleteDelegatedAuthenticationCredential: nil
            )
        
            let authenticationServiceMock = AuthenticationServiceMock()
        
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            sut.handle(fingerprintAction, event: analyticsEvent) { fingerprintResult in
                switch fingerprintResult {
                case let .success(fingerprintString):
                    let fingerprint: ThreeDS2Component.Fingerprint = try! AdyenCoder.decodeBase64(fingerprintString)
                    XCTAssertEqual(fingerprint, expectedFingerprint)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }
        
            waitForExpectations(timeout: 20, handler: nil)
        }

        func testInvalidFingerprintToken() throws {
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
        
            let authenticationServiceMock = AuthenticationServiceMock()

            let fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: "Invalid-token",
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )

            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            sut.handle(
                fingerprintAction,
                event: analyticsEvent
            ) { result in
                switch result {
                case .success:
                    XCTFail()
                case let .failure(error):
                    let decodingError = error as? DecodingError
                    switch decodingError {
                    case .dataCorrupted?: ()
                    default:
                        XCTFail()
                    }
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }

        func testChallengeFlowSuccess() throws {
            
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters

            let transaction = AnyADYTransactionMock(parameters: authenticationRequestParameters)
            transaction.onPerformChallenge = { params, completion in
                XCTAssertEqual(params.threeDSRequestorAppURL, URL(string: "https://google.com"))
                completion(AnyChallengeResultMock(sdkTransactionIdentifier: "sdkTxId", transactionStatus: "Y"), nil)
            }
            service.mockedTransaction = transaction
        
            let authenticationServiceMock = AuthenticationServiceMock()
        
            authenticationServiceMock.onRegister = { _ in
                self.expectedSDKRegistrationOutput
            }
        
            let expectedResult = try! ThreeDSResult(
                from: AnyChallengeResultMock(
                    sdkTransactionIdentifier: "sdkTransactionIdentifier",
                    transactionStatus: "Y"
                ),
                delegatedAuthenticationSDKOutput: expectedSDKRegistrationOutput,
                authorizationToken: "authToken",
                threeDS2SDKError: nil
            )
            
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .register, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock,
                deviceSupportCheckerService: DeviceSupportCheckerMock(isDeviceSupported: true)
            )
            sut.threeDSRequestorAppURL = URL(string: "https://google.com")
            sut.transaction = transaction
            sut.delegatedAuthenticationState.attemptRegistration = true
            sut.handle(challengeAction, event: analyticsEvent) { challengeResult in
                switch challengeResult {
                case let .success(result):
                    XCTAssertEqual(result, expectedResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }
    
        func testChallengeFlowFailure() throws {
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
            let mockedTransaction = AnyADYTransactionMock(parameters: authenticationRequestParameters)
            service.mockedTransaction = mockedTransaction

            mockedTransaction.onPerformChallenge = { parameters, completion in
                completion(nil, Dummy.error)
            }

            let authenticationServiceMock = AuthenticationServiceMock()
        
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            sut.transaction = mockedTransaction

            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")

            sut.handle(challengeAction, event: analyticsEvent) { result in
                switch result {
                case let .success(result):
                    
                    struct Payload: Codable {
                        let threeDS2SDKError: String?
                    }

                    let payload: Payload? = try? AdyenCoder.decodeBase64(result.payload)
                    XCTAssertNotNil(payload?.threeDS2SDKError)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }

        func testChallengeFlowMissingTransaction() throws {
            let service = AnyADYServiceMock()
        
            let authenticationServiceMock = AuthenticationServiceMock()
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )

            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            sut.handle(challengeAction, event: analyticsEvent) { result in
                switch result {
                case .success:
                    XCTFail()
                case let .failure(error):
                    let componentError = error as? ThreeDS2Component.Error
                    switch componentError {
                    case .missingTransaction?: ()
                    default:
                        XCTFail()
                    }
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }

        func testInvalidChallengeToken() throws {
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
            let mockedTransaction = AnyADYTransactionMock(parameters: authenticationRequestParameters)
            service.mockedTransaction = mockedTransaction

            mockedTransaction.onPerformChallenge = { parameters, completion in
                XCTFail()
            }

            let authenticationServiceMock = AuthenticationServiceMock()

            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                presenter: ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            sut.transaction = mockedTransaction

            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")

            let challengeAction = ThreeDS2ChallengeAction(challengeToken: "Invalid-token", authorisationToken: "AuthToken", paymentData: "paymentData")
            sut.handle(challengeAction, event: analyticsEvent) { result in
                switch result {
                case .success:
                    XCTFail()
                case let .failure(error):
                    let decodingError = error as? DecodingError
                    switch decodingError {
                    case .dataCorrupted?: ()
                    default:
                        XCTFail()
                    }
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }
        
        // MARK: - Delegated Authentication tests

        // The approval flow of delegated authentication
        func testDelegatedAuthenticationApprovalFlowWhenUserApproves() throws {
            
            // The token and result are base 64 encoded.
            enum TestData {
                static let fingerprintToken = "ewogICJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES0lucHV0IjogIiMjU29tZWRlbGVnYXRlZEF1dGhlbnRpY2F0aW9uU0RLSW5wdXQjIyIsCiAgImRpcmVjdG9yeVNlcnZlcklkIjogIkYwMTMzNzEzMzciLAogICJkaXJlY3RvcnlTZXJ2ZXJQdWJsaWNLZXkiOiAiI0RpcmVjdG9yeVNlcnZlclB1YmxpY0tleSMiLAogICJkaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIjogIiMjRGlyZWN0b3J5U2VydmVyUm9vdENlcnRpZmljYXRlcyMjIiwKICAidGhyZWVEU01lc3NhZ2VWZXJzaW9uIjogIjIuMi4wIiwKICAidGhyZWVEU1NlcnZlclRyYW5zSUQiOiAiMTUwZmEzYjgtZTZjOC00N2ExLTk2ZTAtOTEwNzYzYmVlYzU3IiwKICAicGF5bWVudEluZm8iOiB7CiAgICAiYW1vdW50IjogewogICAgICAiY3VycmVuY3kiOiAiRVVSIiwKICAgICAgInZhbHVlIjogMQogICAgfSwKICAgICJicmFuZCI6ICJ2aXNhY3JlZGl0IiwKICAgICJsYXN0Rm91ciI6ICI2NzQ2IgogIH0KfQ=="
                            
                static let expectedFingerprintResult = "eyJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES091dHB1dCI6Ik9uQXV0aGVudGljYXRlIiwic2RrQXBwSUQiOiJzZGtBcHBsaWNhdGlvbklkZW50aWZpZXIiLCJzZGtFbmNEYXRhIjoiZGV2aWNlX2luZm8iLCJzZGtFcGhlbVB1YktleSI6eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6IjNiM21QZldodU94d09XeWRMZWpTM0RKRVVQaU1WRnh0ekdDVjY5MDZyZmMiLCJ5IjoienYwa3oxU0tmTnZUM3FsNzVMMjE3ZGU2WnN6eGZMQThMVUtPSUtlNVpmNCJ9LCJzZGtSZWZlcmVuY2VOdW1iZXIiOiJzZGtSZWZlcmVuY2VOdW1iZXIiLCJzZGtUcmFuc0lEIjoic2RrVHJhbnNhY3Rpb25JZGVudGlmaWVyIn0="
            }

            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
                
            let authenticationServiceMock = AuthenticationServiceMock()
            authenticationServiceMock.onAuthenticate = { input in
                "OnAuthenticate"
            }
            var capturedCardDetails: (number: String?, type: Adyen.CardType?)?
            var capturedAmount: Amount?
            let presenterMock = ThreeDS2DAScreenPresenterMock(
                showRegistrationReturnState: .fallback,
                showApprovalScreenReturnState: .approve
            )
            presenterMock.onShowApprovalScreen = {
                capturedCardDetails = $0
                capturedAmount = $1
            }
            
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: presenterMock,
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            
            let fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: TestData.fingerprintToken,
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )
            sut.handle(fingerprintAction, event: analyticsEvent) { fingerprintResult in
                switch fingerprintResult {
                case let .success(fingerprintString):
                    XCTAssertEqual(fingerprintString, TestData.expectedFingerprintResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }
        
            waitForExpectations(timeout: 20, handler: nil)
            
            let shownCardDetails = try XCTUnwrap(capturedCardDetails)
            let shownAmount = try XCTUnwrap(capturedAmount)
            XCTAssertEqual(shownCardDetails.number, "•••• 6746")
            XCTAssertEqual(shownAmount, Amount(value: 1, currencyCode: "EUR"))
        }

        func testDelegatedAuthenticationApprovalFlowWhenUserApprovesButVerificationFails() throws {
            // The token and result are base 64 encoded.
            enum TestData {
                static let fingerprintToken = "eyJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES0lucHV0IjoiIyNTb21lZGVsZWdhdGVkQXV0aGVudGljYXRpb25TREtJbnB1dCMjIiwiZGlyZWN0b3J5U2VydmVySWQiOiJGMDEzMzcxMzM3IiwiZGlyZWN0b3J5U2VydmVyUHVibGljS2V5IjoiI0RpcmVjdG9yeVNlcnZlclB1YmxpY0tleSMiLCJkaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIjoiIyNEaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIyMiLCJ0aHJlZURTTWVzc2FnZVZlcnNpb24iOiIyLjIuMCIsInRocmVlRFNTZXJ2ZXJUcmFuc0lEIjoiMTUwZmEzYjgtZTZjOC00N2ExLTk2ZTAtOTEwNzYzYmVlYzU3In0="
                // Result without delegatedAuthenticationSDKOutput
                static let expectedFingerprintResult = "eyJzZGtBcHBJRCI6InNka0FwcGxpY2F0aW9uSWRlbnRpZmllciIsInNka0VuY0RhdGEiOiJkZXZpY2VfaW5mbyIsInNka0VwaGVtUHViS2V5Ijp7ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4IjoiM2IzbVBmV2h1T3h3T1d5ZExlalMzREpFVVBpTVZGeHR6R0NWNjkwNnJmYyIsInkiOiJ6djBrejFTS2ZOdlQzcWw3NUwyMTdkZTZac3p4ZkxBOExVS09JS2U1WmY0In0sInNka1JlZmVyZW5jZU51bWJlciI6InNka1JlZmVyZW5jZU51bWJlciIsInNka1RyYW5zSUQiOiJzZGtUcmFuc2FjdGlvbklkZW50aWZpZXIifQ=="
            }

            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
                
            let authenticationServiceMock = AuthenticationServiceMock()
            authenticationServiceMock.onAuthenticate = { input in
                throw NSError(domain: "Error during Authentication", code: 123)
            }
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(
                    showRegistrationReturnState: .fallback,
                    showApprovalScreenReturnState: .approve
                ),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            
            let fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: TestData.fingerprintToken,
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )
            sut.handle(fingerprintAction, event: analyticsEvent) { fingerprintResult in
                switch fingerprintResult {
                case let .success(fingerprintString):
                    XCTAssertEqual(fingerprintString, TestData.expectedFingerprintResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }
        
            waitForExpectations(timeout: 20, handler: nil)
        }

        func testDelegatedAuthenticationApprovalFlowWhenUserDoesntConsentToApprove() throws {
            // The token and result are base 64 encoded.
            enum TestData {
                // Token with delegatedAuthenticationSDKInput
                static let fingerprintToken = "eyJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES0lucHV0IjoiIyNTb21lZGVsZWdhdGVkQXV0aGVudGljYXRpb25TREtJbnB1dCMjIiwiZGlyZWN0b3J5U2VydmVySWQiOiJGMDEzMzcxMzM3IiwiZGlyZWN0b3J5U2VydmVyUHVibGljS2V5IjoiI0RpcmVjdG9yeVNlcnZlclB1YmxpY0tleSMiLCJkaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIjoiIyNEaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIyMiLCJ0aHJlZURTTWVzc2FnZVZlcnNpb24iOiIyLjIuMCIsInRocmVlRFNTZXJ2ZXJUcmFuc0lEIjoiMTUwZmEzYjgtZTZjOC00N2ExLTk2ZTAtOTEwNzYzYmVlYzU3In0="
                            
                // Result without delegatedAuthenticationSDKOutput
                static let expectedFingerprintResult = "eyJzZGtBcHBJRCI6InNka0FwcGxpY2F0aW9uSWRlbnRpZmllciIsInNka0VuY0RhdGEiOiJkZXZpY2VfaW5mbyIsInNka0VwaGVtUHViS2V5Ijp7ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4IjoiM2IzbVBmV2h1T3h3T1d5ZExlalMzREpFVVBpTVZGeHR6R0NWNjkwNnJmYyIsInkiOiJ6djBrejFTS2ZOdlQzcWw3NUwyMTdkZTZac3p4ZkxBOExVS09JS2U1WmY0In0sInNka1JlZmVyZW5jZU51bWJlciI6InNka1JlZmVyZW5jZU51bWJlciIsInNka1RyYW5zSUQiOiJzZGtUcmFuc2FjdGlvbklkZW50aWZpZXIifQ=="
            }

            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
                
            let authenticationServiceMock = AuthenticationServiceMock()
            authenticationServiceMock.onAuthenticate = { input in
                "OnAuthenticate"
            }
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(
                    showRegistrationReturnState: .fallback,
                    showApprovalScreenReturnState: .fallback
                ),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            
            let fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: TestData.fingerprintToken,
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )
            sut.handle(fingerprintAction, event: analyticsEvent) { fingerprintResult in
                switch fingerprintResult {
                case let .success(fingerprintString):
                    XCTAssertEqual(fingerprintString, TestData.expectedFingerprintResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }
        
            waitForExpectations(timeout: 20, handler: nil)
        }
        
        func testDelegatedAuthenticationFingerPrintResultWhenRemovingCredentials() {
            // The token and result are base 64 encoded.
            enum TestData {
                // Token with delegatedAuthenticationSDKInput
                static let fingerprintToken = "eyJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES0lucHV0IjoiIyNTb21lZGVsZWdhdGVkQXV0aGVudGljYXRpb25TREtJbnB1dCMjIiwiZGlyZWN0b3J5U2VydmVySWQiOiJGMDEzMzcxMzM3IiwiZGlyZWN0b3J5U2VydmVyUHVibGljS2V5IjoiI0RpcmVjdG9yeVNlcnZlclB1YmxpY0tleSMiLCJkaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIjoiIyNEaXJlY3RvcnlTZXJ2ZXJSb290Q2VydGlmaWNhdGVzIyMiLCJ0aHJlZURTTWVzc2FnZVZlcnNpb24iOiIyLjIuMCIsInRocmVlRFNTZXJ2ZXJUcmFuc0lEIjoiMTUwZmEzYjgtZTZjOC00N2ExLTk2ZTAtOTEwNzYzYmVlYzU3In0="
                            
                // Result with delegatedAuthenticationSDKOutput & the deleteCredentials flag
                static let expectedFingerprintResult = "eyJkZWxlZ2F0ZWRBdXRoZW50aWNhdGlvblNES091dHB1dCI6Im9uQXV0aGVudGljYXRlLXNka091dHB1dCIsImRlbGV0ZURlbGVnYXRlZEF1dGhlbnRpY2F0aW9uQ3JlZGVudGlhbCI6dHJ1ZSwic2RrQXBwSUQiOiJzZGtBcHBsaWNhdGlvbklkZW50aWZpZXIiLCJzZGtFbmNEYXRhIjoiZGV2aWNlX2luZm8iLCJzZGtFcGhlbVB1YktleSI6eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6IjNiM21QZldodU94d09XeWRMZWpTM0RKRVVQaU1WRnh0ekdDVjY5MDZyZmMiLCJ5IjoienYwa3oxU0tmTnZUM3FsNzVMMjE3ZGU2WnN6eGZMQThMVUtPSUtlNVpmNCJ9LCJzZGtSZWZlcmVuY2VOdW1iZXIiOiJzZGtSZWZlcmVuY2VOdW1iZXIiLCJzZGtUcmFuc0lEIjoic2RrVHJhbnNhY3Rpb25JZGVudGlmaWVyIn0="
            }

            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters
                
            let onAuthenticateExpectation = expectation(description: "Expect onReset to be called")
            let authenticationServiceMock = AuthenticationServiceMock()
            authenticationServiceMock.onAuthenticate = { input in
                onAuthenticateExpectation.fulfill()
                return "onAuthenticate-sdkOutput"
            }
            
            let onResetExpectation = expectation(description: "Expect onReset to not be called")
            onResetExpectation.isInverted = true
            authenticationServiceMock.onReset = {
                onResetExpectation.fulfill()
            }
            
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")

            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(
                    showRegistrationReturnState: .fallback,
                    showApprovalScreenReturnState: .removeCredentials
                ),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock
            )
            
            let fingerprintAction = ThreeDS2FingerprintAction(
                fingerprintToken: TestData.fingerprintToken,
                authorisationToken: "AuthToken",
                paymentData: "paymentData"
            )
            sut.handle(fingerprintAction, event: analyticsEvent) { fingerprintResult in
                switch fingerprintResult {
                case let .success(fingerprintString):
                    XCTAssertEqual(fingerprintString, TestData.expectedFingerprintResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }
        
            waitForExpectations(timeout: 20, handler: nil)
        }
        
        func testDelegatedAuthenticationChallengeResultWhenRemovingCredentials() throws {
            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters

            let transaction = AnyADYTransactionMock(parameters: authenticationRequestParameters)
            transaction.onPerformChallenge = { params, completion in
                completion(AnyChallengeResultMock(sdkTransactionIdentifier: "sdkTxId", transactionStatus: "Y"), nil)
            }
            service.mockedTransaction = transaction
        
            let authenticationServiceMock = AuthenticationServiceMock()
        
            authenticationServiceMock.onRegister = { _ in
                XCTFail("On Register should not be called when the user doesn't consent to register")
                return self.expectedSDKRegistrationOutput
            }
        
            let expectedResult = try XCTUnwrap(try? ThreeDSResult(
                from: AnyChallengeResultMock(sdkTransactionIdentifier: "sdkTransactionIdentifier", transactionStatus: "Y"),
                delegatedAuthenticationSDKOutput: nil,
                authorizationToken: "authToken",
                threeDS2SDKError: nil
            ))
                        
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: ThreeDS2DAScreenPresenterMock(
                    showRegistrationReturnState: .fallback,
                    showApprovalScreenReturnState: .fallback
                ),
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock,
                deviceSupportCheckerService: DeviceSupportCheckerMock(isDeviceSupported: true)
            )
            sut.transaction = transaction
            sut.delegatedAuthenticationState.attemptRegistration = true
            sut.handle(challengeAction, event: analyticsEvent) { challengeResult in
                switch challengeResult {
                case let .success(result):
                    XCTAssertEqual(result, expectedResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
        }

        func testDelegatedAuthenticationRegistrationFlowWhenUserDoesntConsentToRegister() throws {

            let service = AnyADYServiceMock()
            service.authenticationRequestParameters = authenticationRequestParameters

            let transaction = AnyADYTransactionMock(parameters: authenticationRequestParameters)
            transaction.onPerformChallenge = { params, completion in
                XCTAssertEqual(params.threeDSRequestorAppURL, URL(string: "https://google.com"))
                completion(AnyChallengeResultMock(sdkTransactionIdentifier: "sdkTxId", transactionStatus: "Y"), nil)
            }
            service.mockedTransaction = transaction
        
            let authenticationServiceMock = AuthenticationServiceMock()
        
            authenticationServiceMock.onRegister = { _ in
                XCTFail("On Register should not be called when the user doesn't consent to register")
                return self.expectedSDKRegistrationOutput
            }
        
            let expectedResult = try XCTUnwrap(try? ThreeDSResult(
                from: AnyChallengeResultMock(sdkTransactionIdentifier: "sdkTransactionIdentifier", transactionStatus: "Y"),
                delegatedAuthenticationSDKOutput: nil, // // We shouldn't receive
                authorizationToken: "authToken",
                threeDS2SDKError: nil
            ))
            
            let presenterMock = ThreeDS2DAScreenPresenterMock(showRegistrationReturnState: .fallback, showApprovalScreenReturnState: .fallback)
            var capturedCardDetails: (number: String?, type: Adyen.CardType?)?
            presenterMock.onShowRegistrationScreen = {
                capturedCardDetails = $0
            }
            
            let resultExpectation = expectation(description: "Expect ThreeDS2ActionHandler completion closure to be called.")
            let sut = ThreeDS2PlusDACoreActionHandler(
                context: Dummy.context,
                service: service,
                presenter: presenterMock,
                delegatedAuthenticationConfiguration: Self.delegatedAuthenticationConfigurations,
                delegatedAuthenticationService: authenticationServiceMock,
                deviceSupportCheckerService: DeviceSupportCheckerMock(isDeviceSupported: true)
            )
            sut.threeDSRequestorAppURL = URL(string: "https://google.com")
            sut.transaction = transaction
            sut.delegatedAuthenticationState.attemptRegistration = true
            sut.handle(challengeAction, event: analyticsEvent) { challengeResult in
                switch challengeResult {
                case let .success(result):
                    XCTAssertEqual(result, expectedResult)
                case .failure:
                    XCTFail()
                }
                resultExpectation.fulfill()
            }

            waitForExpectations(timeout: 2, handler: nil)
            let shownCardDetails = try XCTUnwrap(capturedCardDetails)
            XCTAssertEqual(shownCardDetails.number, "•••• 6746")
        }
    }

    internal struct DeviceSupportCheckerMock: AdyenAuthentication.DeviceSupportCheckerProtocol {
        var isDeviceSupported: Bool
    
        func checkSupport() throws -> String {
            ""
        }
    }

#endif
