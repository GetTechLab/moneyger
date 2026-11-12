import Foundation

/// Snapshot of exchange rates relative to a single base currency.
struct ExchangeRates: Codable, Equatable {
    let base: String
    /// Units of each currency per 1 unit of `base`.
    let rates: [String: Double]
    /// When the provider last published these rates.
    let updatedAt: Date
    /// When the app downloaded them; drives cache expiry.
    let fetchedAt: Date

    /// Converts `amount` between any two currencies by going through the base currency.
    func convert(_ amount: Double, from source: String, to target: String) -> Double? {
        if source == target { return amount }
        guard let sourceRate = rate(for: source), let targetRate = rate(for: target), sourceRate > 0 else {
            return nil
        }
        return amount / sourceRate * targetRate
    }

    private func rate(for code: String) -> Double? {
        code == base ? 1 : rates[code]
    }
}

/// Fetches live rates from open.er-api.com (free, no API key) and caches them on disk
/// so the dashboard still converts amounts when offline.
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    private let cacheKey = "exchangeRates.cache"
    private let maxAge: TimeInterval = 12 * 60 * 60
    private let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    private struct Response: Decodable {
        let result: String
        let base_code: String
        let time_last_update_unix: TimeInterval
        let rates: [String: Double]
    }

    var cachedRates: ExchangeRates? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ExchangeRates.self, from: data)
    }

    /// Returns fresh rates when the cache is stale (or `force` is set), falling back to the cache on failure.
    func latestRates(force: Bool = false) async -> ExchangeRates? {
        let cached = cachedRates
        if !force, let cached, Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.result == "success" else { return cached }

            let rates = ExchangeRates(
                base: response.base_code,
                rates: response.rates,
                updatedAt: Date(timeIntervalSince1970: response.time_last_update_unix),
                fetchedAt: Date()
            )
            if let encoded = try? JSONEncoder().encode(rates) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            return rates
        } catch {
            print("ExchangeRateService fetch error: \(error)")
            return cached
        }
    }
}
