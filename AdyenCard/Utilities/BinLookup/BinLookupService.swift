//
// Copyright (c) 2021 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Adyen
#if canImport(AdyenEncryption)
    import AdyenEncryption
#endif
import Foundation

/// Provide cardType detection based on BinLookup API.
internal protocol AnyBinLookupService {
    
    /// :nodoc:
    typealias CompletionHandler = (Result<BinLookupResponse, Error>) -> Void
    
    /// :nodoc:
    func requestCardType(for bin: String, supportedCardTypes: [CardType], caller: @escaping CompletionHandler)
}

internal final class BinLookupService: AnyBinLookupService {
    
    private let publicKey: String
    
    private let apiClient: APIClientProtocol

    private var cache = [String: BinLookupResponse]()
    
    internal init(publicKey: String, apiClient: APIClientProtocol) {
        self.publicKey = publicKey
        self.apiClient = apiClient
    }
    
    internal func requestCardType(for bin: String, supportedCardTypes: [CardType], caller: @escaping CompletionHandler) {
        let encryptedBin: String
        do {
            encryptedBin = try CardEncryptor.encrypt(bin: bin, with: publicKey)
        } catch {
            return caller(.failure(error))
        }
        
        let request = BinLookupRequest(encryptedBin: encryptedBin, supportedBrands: supportedCardTypes)
        if let cached = cache[bin] {
            return caller(.success(cached))
        }

        apiClient.perform(request) { [weak self] result in
            switch result {
            case let .success(response):
                self?.cache[bin] = response
                caller(.success(response))
            case let .failure(error):
                caller(.failure(error))
            }
        }
    }
}
