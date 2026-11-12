import Foundation

final class GmailAPIService {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let authService: GmailAuthService

    // Known financial sender domains for pre-filtering
    private let financialDomains: Set<String> = [
        // Turkish banks
        "garanti.com.tr", "garantibbva.com.tr",
        "isbank.com.tr",
        "ykb.com", "yapikredi.com.tr",
        "akbank.com",
        "ziraatbank.com.tr",
        "halkbank.com.tr",
        "vakifbank.com.tr",
        "denizbank.com",
        "ing.com.tr",
        "qnbfinansbank.com",
        "fibabanka.com.tr",
        // International
        "wise.com",
        "revolut.com",
        "n26.com",
        "americanexpress.com",
        "amex.com",
        // Investment
        "midas.app",
        "interactivebrokers.com",
        "ibkr.com",
        // Generic financial
        "paypal.com"
    ]

    // Subject keywords typical for bank / card emails. Merchant words like
    // "invoice", "receipt" or "payment" are intentionally excluded: those purchases
    // already show up on the bank or card statement.
    private let financialKeywords: [String] = [
        "ekstre", "hesap özeti", "kredi kartı", "kartınızdan", "harcama",
        "son ödeme", "borç", "havale", "eft", "banka",
        "statement", "credit card", "transaction", "balance", "transfer", "bank"
    ]

    init(authService: GmailAuthService) {
        self.authService = authService
    }

    // MARK: - Fetch message IDs

    /// Returns IDs of all likely-financial emails received after `date`, following every result page.
    /// Filtering happens in the Gmail query itself, so promotions and unrelated mail are never downloaded.
    func fetchMessageIds(after date: Date, limit: Int = 1000) async throws -> [String] {
        let query = financialSearchQuery(after: date)
        var ids: [String] = []
        var pageToken: String?

        repeat {
            guard var components = URLComponents(string: "\(baseURL)/messages") else {
                throw GmailError.fetchFailed("Invalid URL")
            }
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "500")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            guard let url = components.url else { throw GmailError.fetchFailed("Invalid URL") }

            let data = try await get(url: url)
            let response = try JSONDecoder().decode(MessageListResponse.self, from: data)
            ids += response.messages?.map(\.id) ?? []
            pageToken = response.nextPageToken
        } while pageToken != nil && ids.count < limit

        return Array(ids.prefix(limit))
    }

    /// Gmail search: (known bank sender OR financial subject keyword), after the date,
    /// across all mail (including archived/labelled), excluding spam, trash and promotions.
    private func financialSearchQuery(after date: Date) -> String {
        let senders = financialDomains.sorted().map { "from:\($0)" }
        let subjects = financialKeywords.map { keyword in
            keyword.contains(" ") ? "subject:\"\(keyword)\"" : "subject:\(keyword)"
        }
        let anyOf = "{" + (senders + subjects).joined(separator: " ") + "}"
        let timestamp = Int(date.timeIntervalSince1970)
        return "\(anyOf) after:\(timestamp) -in:spam -in:trash -category:promotions -category:social"
    }

    // MARK: - Fetch single message

    func fetchMessage(id: String) async throws -> EmailContent {
        let url = URL(string: "\(baseURL)/messages/\(id)?format=full")!
        let data = try await get(url: url)
        let message = try JSONDecoder().decode(GmailMessage.self, from: data)
        return try parseMessage(message)
    }

    // MARK: - Batch fetch (sequential to respect rate limits)

    func fetchMessages(ids: [String]) async throws -> [EmailContent] {
        var emails: [EmailContent] = []
        for id in ids {
            let email = try await fetchMessage(id: id)
            emails.append(email)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms rate limit delay
        }
        return emails
    }

    // MARK: - Private helpers

    private func get(url: URL) async throws -> Data {
        let token = try await authService.currentAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GmailError.fetchFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    private func parseMessage(_ message: GmailMessage) throws -> EmailContent {
        let headers = message.payload.headers
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? ""
        let from = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
        let dateStr = headers.first { $0.name.lowercased() == "date" }?.value ?? ""

        let senderEmail = extractEmail(from: from)
        let senderDomain = extractDomain(from: senderEmail)
        let body = extractBody(from: message.payload)
        let date = parseDate(dateStr) ?? Date()

        return EmailContent(
            messageId: message.id,
            subject: subject,
            sender: from,
            senderDomain: senderDomain,
            body: body,
            receivedDate: date
        )
    }

    private func extractEmail(from header: String) -> String {
        if let range = header.range(of: "<(.+?)>", options: .regularExpression) {
            return String(header[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        return header.trimmingCharacters(in: .whitespaces)
    }

    private func extractDomain(from email: String) -> String {
        let parts = email.split(separator: "@")
        return parts.last.map(String.init) ?? ""
    }

    private func extractBody(from payload: GmailPayload) -> String {
        // Try plain text first, then HTML
        if let text = extractPart(from: payload, mimeType: "text/plain") {
            return text
        }
        if let html = extractPart(from: payload, mimeType: "text/html") {
            return stripHTML(html)
        }
        // Fallback: decode body directly
        if let bodyData = payload.body.data,
           let decoded = Data(base64Encoded: bodyData.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) {
            return String(data: decoded, encoding: .utf8) ?? ""
        }
        return ""
    }

    private func extractPart(from payload: GmailPayload, mimeType: String) -> String? {
        if payload.mimeType == mimeType {
            if let data = payload.body.data,
               let decoded = Data(base64Encoded: data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) {
                return String(data: decoded, encoding: .utf8)
            }
        }
        for part in payload.parts ?? [] {
            if let result = extractPart(from: part, mimeType: mimeType) {
                return result
            }
        }
        return nil
    }

    /// Turns HTML into readable text while keeping row structure, so statement tables
    /// stay one transaction per line for the AI.
    private func stripHTML(_ html: String) -> String {
        var text = html
            // Drop non-visible content entirely (CSS, scripts, head metadata, comments)
            .replacingOccurrences(of: "(?is)<(style|script|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?s)<!--.*?-->", with: " ", options: .regularExpression)
            // Block-level ends become line breaks; table cells become separators
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|div|tr|li|h[1-6]|table)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</t[dh]>", with: " | ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        text = decodeHTMLEntities(text)

        return text
            .replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "( ?\\| ?)+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes numeric entities (e.g. `&#252;` → ü, common in Turkish bank emails) and the usual named ones.
    private func decodeHTMLEntities(_ text: String) -> String {
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&ccedil;": "ç", "&Ccedil;": "Ç", "&ouml;": "ö", "&Ouml;": "Ö", "&uuml;": "ü", "&Uuml;": "Ü",
            "&euro;": "€", "&pound;": "£"
        ]
        var result = text
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return result }
        let source = result as NSString
        var decoded = ""
        var lastEnd = 0
        for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)) {
            decoded += source.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let isHex = source.substring(with: match.range(at: 1)) == "x"
            let digits = source.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                decoded.unicodeScalars.append(scalar)
            } else {
                decoded += source.substring(with: match.range)
            }
            lastEnd = match.range.location + match.range.length
        }
        decoded += source.substring(from: lastEnd)
        return decoded
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formatters {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    func isLikelyFinancial(domain: String, subject: String) -> Bool {
        // Match subdomains too, e.g. "bilgi.garanti.com.tr"
        let lowerDomain = domain.lowercased()
        if financialDomains.contains(where: { lowerDomain == $0 || lowerDomain.hasSuffix(".\($0)") }) {
            return true
        }

        let lowerSubject = subject.lowercased()
        return financialKeywords.contains { lowerSubject.contains($0) }
    }
}

// MARK: - Gmail API Response Models

struct MessageListResponse: Decodable {
    let messages: [MessageRef]?
    let nextPageToken: String?

    struct MessageRef: Decodable {
        let id: String
        let threadId: String
    }
}

struct GmailMessage: Decodable {
    let id: String
    let threadId: String
    let payload: GmailPayload
}

struct GmailPayload: Decodable {
    let mimeType: String
    let headers: [GmailHeader]
    let body: GmailBody
    let parts: [GmailPayload]?
}

struct GmailHeader: Decodable {
    let name: String
    let value: String
}

struct GmailBody: Decodable {
    let data: String?
    let size: Int
}
