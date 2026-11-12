import Foundation
import PDFKit
import Vision
import UIKit

/// Turns PDFs and screenshots into plain text on device, so the AI only receives
/// text (far cheaper than image input and works with every text-only model).
enum DocumentTextExtractor {
    /// Upper bound on pages read from one PDF; statements rarely exceed this.
    static let maxPages = 30

    enum ExtractionError: LocalizedError {
        case unreadable
        case noText

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file couldn't be opened."
            case .noText: return "No text could be read from this file."
            }
        }
    }

    /// Returns the text of each page. Each page uses its embedded text when that is usable,
    /// otherwise it is OCR'd: scanned pages, and pages whose fonts decode to gibberish.
    static func pages(fromPDF url: URL) async throws -> [String] {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadable }
        let pageCount = min(document.pageCount, maxPages)

        var pages: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let embedded = rowText(of: page)
            // Fewer than ~40 readable characters means a scanned image with at most a watermark
            if embedded.count >= 40, !looksGarbled(embedded) {
                pages.append(embedded)
            } else if let image = render(page) {
                pages.append(try await recognizeText(in: image))
            }
        }
        return pages
    }

    static func text(fromImage data: Data) async throws -> String {
        guard let image = UIImage(data: data).flatMap(upscaledIfSmall)?.cgImage else {
            throw ExtractionError.unreadable
        }
        return try await recognizeText(in: image)
    }

    // MARK: - Embedded PDF text

    /// Rebuilds visual rows from the position of each text run. `PDFPage.string` follows the
    /// PDF's internal drawing order, which for many bank statements lists a whole column
    /// (all dates, then all descriptions, then all amounts) and breaks row pairing.
    private static func rowText(of page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: bounds) else { return tidy(page.string ?? "") }
        let runs = selection.selectionsByLine().compactMap { line -> (text: String, box: CGRect)? in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return (text, line.bounds(for: page))
        }
        // PDF space also has its origin at the bottom left, so the OCR row grouping applies as is
        return runs.isEmpty ? tidy(page.string ?? "") : joinIntoLines(runs)
    }

    /// Detects text from PDFs with broken font encodings (CID glyphs, replacement characters,
    /// random symbols) where OCR gives a far better result.
    private static func looksGarbled(_ text: String) -> Bool {
        if text.contains("\u{FFFD}") || text.contains("(cid:") { return true }
        let allowedPunctuation = CharacterSet(charactersIn: ".,:;-–/()₺$€£%+*'\"#&@|")
        let visible = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !visible.isEmpty else { return true }
        let readable = visible.filter { CharacterSet.alphanumerics.contains($0) || allowedPunctuation.contains($0) }
        return Double(readable.count) / Double(visible.count) < 0.85
    }

    // MARK: - OCR

    /// OCRs an image. On iOS 26+ Vision's document recognizer reads tables cell by cell;
    /// otherwise (or if it finds no table) plain text recognition with row rebuilding is used.
    static func recognizeText(in image: CGImage) async throws -> String {
        if #available(iOS 26.0, *), let structured = try? await recognizeDocument(in: image) {
            return structured
        }
        return try await recognizeLines(in: image)
    }

    /// Uses `RecognizeDocumentsRequest` to keep table structure: text outside tables first,
    /// then each table row as "cell | cell | cell". Returns nil when no table is found so the
    /// caller falls back to line recognition, which handles free-form layouts better.
    @available(iOS 26.0, *)
    private static func recognizeDocument(in image: CGImage) async throws -> String? {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        request.textRecognitionOptions.useLanguageCorrection = false

        guard let document = try await request.perform(on: image).first?.document else { return nil }
        let tables = document.tables.filter { $0.rows.count >= 2 }
        guard !tables.isEmpty else { return nil }

        // Paragraphs inside a table would repeat its cells
        let outside = document.paragraphs.filter { paragraph in
            let box = paragraph.boundingRegion.normalizedPath.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            return !tables.contains { $0.boundingRegion.normalizedPath.contains(center) }
        }

        var sections = outside.map(\.transcript).filter { !$0.isEmpty }
        for table in tables {
            let rows = table.rows.map { row in
                row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: " | ")
            }
            sections.append(rows.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n")
    }

    /// Runs Vision text recognition off the main thread and rebuilds the visual rows,
    /// so a statement line like "03.11  MIGROS  452,30 TL" stays on one line.
    private static func recognizeLines(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US"]
            // Language correction "fixes" merchant names and numbers into dictionary words
            request.usesLanguageCorrection = false

            try VNImageRequestHandler(cgImage: image).perform([request])
            let observations = request.results ?? []
            return joinIntoLines(observations.compactMap { observation in
                observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) }
            })
        }.value
    }

    /// Groups recognized fragments whose vertical centers are close into one line, left to right.
    private static func joinIntoLines(_ fragments: [(text: String, box: CGRect)]) -> String {
        // Vision's origin is bottom-left, so higher midY means higher on the page
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }
        var lines: [[(text: String, box: CGRect)]] = []

        for fragment in sorted {
            if let last = lines.last?.last,
               abs(last.box.midY - fragment.box.midY) < min(last.box.height, fragment.box.height) * 0.6 {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
            .joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Renders a PDF page at roughly 2x so small statement fonts stay legible for OCR.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImage
    }

    /// Small or heavily compressed screenshots lose thin digits; doubling them helps recognition.
    private static func upscaledIfSmall(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth < 1200 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: pixelWidth * 2, height: image.size.height * image.scale * 2)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Collapses runs of spaces and blank lines that PDF text extraction tends to produce.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
