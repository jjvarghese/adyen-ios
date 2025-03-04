//
// Copyright (c) 2024 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Adyen3DS2
import Foundation
@_spi(AdyenInternal) import Adyen

internal protocol AnyADYService {
    func service(
        with parameters: ADYServiceParameters,
        appearanceConfiguration: ADYAppearanceConfiguration,
        completionHandler: @escaping (_ service: AnyADYService) -> Void
    )

    func transaction(withMessageVersion: String) throws -> AnyADYTransaction
}

internal final class ADYServiceAdapter: AnyADYService {

    private var service: ADYService?

    internal func service(
        with parameters: ADYServiceParameters,
        appearanceConfiguration: ADYAppearanceConfiguration,
        completionHandler: @escaping (AnyADYService) -> Void
    ) {
        ADYService.service(with: parameters, appearanceConfiguration: appearanceConfiguration) { [weak self] service in
            guard let self else { return }
            self.service = service
            completionHandler(self)
        }
    }

    internal func transaction(withMessageVersion: String) throws -> AnyADYTransaction {
        guard let service else {
            throw UnknownError(errorDescription: "ADYService is nil.")
        }
        return try service.transaction(withMessageVersion: withMessageVersion)
    }
    
}
