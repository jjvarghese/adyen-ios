//
// Copyright (c) 2023 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

@_spi(AdyenInternal) import Adyen
import Foundation
import UIKit

/// A generic component for "issuer-based" payment methods, such as iDEAL and MOLPay.
/// This component will provide a list in which the user can select their issuer.
public final class IssuerListComponent: PaymentComponent, PaymentAware, PresentableComponent, LoadingComponent {
    
    /// The context object for this component.
    @_spi(AdyenInternal)
    public let context: AdyenContext
    
    /// The issuer list payment method.
    public var paymentMethod: PaymentMethod {
        issuerListPaymentMethod
    }
    
    /// The delegate of the component.
    public weak var delegate: PaymentComponentDelegate?
    
    /// Component's configuration.
    public var configuration: Configuration
    
    /// Initializes the issuer list component.
    ///
    /// - Parameter paymentMethod: The issuer list payment method.
    /// - Parameter context: The context object for this component.
    /// - Parameter configuration: The configuration for the component.
    public init(paymentMethod: IssuerListPaymentMethod,
                context: AdyenContext,
                configuration: Configuration = .init()) {
        self.issuerListPaymentMethod = paymentMethod
        self.context = context
        self.configuration = configuration
        viewController.title = paymentMethod.displayInformation(using: configuration.localizationParameters).title
    }
    
    private let issuerListPaymentMethod: IssuerListPaymentMethod

    // MARK: - Presentable Component Protocol
    
    public var viewController: UIViewController {
        searchViewController
    }

    private lazy var searchViewController: SearchViewController = {
        let searchViewController = SearchViewController(
            style: configuration.style,
            emptyView: IssuerListEmptyView(),
            localizationParameters: configuration.localizationParameters
        ) { [weak self] searchText, handler in
            guard let self else { return }
            
            if searchText.isEmpty {
                handler(listItems(for: issuerListPaymentMethod.issuers))
            } else {
                let filteredIssuers = issuerListPaymentMethod.issuers.filter {
                    $0.name.range(of: searchText, options: .caseInsensitive) != nil
                }
                handler(listItems(for: filteredIssuers))
            }
        }
        
        return searchViewController
    }()

    public func stopLoading() {
        searchViewController.resultsListViewController.stopLoading()
    }
    
    public var requiresModalPresentation: Bool = true

    // MARK: - Private

    private func listItems(for issuers: [Issuer]) -> [ListItem] {
        issuers.map { issuer -> ListItem in

            let logoUrl = LogoURLProvider.logoURL(
                for: issuer,
                localizedParameters: configuration.localizationParameters,
                paymentMethod: issuerListPaymentMethod,
                environment: context.apiContext.environment
            )
            let listItem = ListItem(
                title: issuer.name,
                icon: .init(url: logoUrl),
                style: configuration.style.listItem
            )
            listItem.identifier = ViewIdentifierBuilder.build(
                scopeInstance: self,
                postfix: listItem.title
            )
            listItem.selectionHandler = { [weak self] in
                guard let self = self else { return }
                let details = IssuerListDetails(paymentMethod: self.issuerListPaymentMethod,
                                                issuer: issuer.identifier)
                self.submit(data: PaymentComponentData(paymentMethodDetails: details,
                                                       amount: self.payment?.amount,
                                                       order: self.order))
                searchViewController.resultsListViewController.startLoading(for: listItem)
            }
            return listItem
        }
    }
}

@_spi(AdyenInternal)
extension IssuerListComponent: ViewControllerDelegate {

    public func viewWillAppear(viewController: UIViewController) {
        sendTelemetryEvent()
    }
}

@_spi(AdyenInternal)
extension IssuerListComponent: TrackableComponent {}

extension IssuerListComponent {
    
    /// Configuration for Issuer List type components.
    public struct Configuration: AnyBasicComponentConfiguration {
        
        /// The UI style of the component.
        public var style: ListComponentStyle
        
        public var localizationParameters: LocalizationParameters?
        
        /// Initializes the configuration for Issuer list type components.
        /// - Parameters:
        ///   - style: The UI style of the component.
        ///   - localizationParameters: Localization parameters.
        public init(style: ListComponentStyle = .init(),
                    localizationParameters: LocalizationParameters? = nil) {
            self.style = style
            self.localizationParameters = localizationParameters
        }
    }
}

/// Provides an issuer selection list for iDEAL payments.
public typealias IdealComponent = IssuerListComponent

/// Provides an issuer selection list for MOLPay payments.
public typealias MOLPayComponent = IssuerListComponent

/// Provides an issuer selection list for Dotpay payments.
public typealias DotpayComponent = IssuerListComponent

/// Provides an issuer selection list for EPS payments.
public typealias EPSComponent = IssuerListComponent

/// Provides an issuer selection list for Entercash payments.
public typealias EntercashComponent = IssuerListComponent

/// Provides an issuer selection list for OpenBanking payments.
public typealias OpenBankingComponent = IssuerListComponent

/// Provides an issuer selection list for onlineBanking Poland .
public typealias OnlineBankingPolandComponent = IssuerListComponent
