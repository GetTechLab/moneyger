import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point of the "Moneyger" item in the iOS share sheet.
/// Copies the shared PDFs/images into the App Group inbox; the app imports them when opened.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        Task { await model.save(providers) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State {
        case saving
        case saved(count: Int)
        case failed(String)
    }

    @Published var state: State = .saving

    func save(_ providers: [NSItemProvider]) async {
        do {
            let folder = try SharedInbox.makeShareFolder()
            var saved = 0
            for (index, provider) in providers.enumerated() {
                guard let (data, ext) = await Self.loadData(from: provider) else { continue }
                // Zero-padded index preserves the order the user picked the screenshots in
                let url = folder.appendingPathComponent(String(format: "%03d.%@", index, ext))
                try data.write(to: url)
                saved += 1
            }
            if saved == 0 {
                SharedInbox.remove(folder)
                state = .failed("Only PDFs and images can be imported.")
            } else {
                state = .saved(count: saved)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Loads PDF or image data, preferring PDF when an item offers both.
    private static func loadData(from provider: NSItemProvider) async -> (Data, String)? {
        let candidates: [(UTType, String)] = [(.pdf, "pdf"), (.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.image, "img")]
        for (type, ext) in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data { return (data, ext) }
        }
        return nil
    }
}

private struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                icon
                    .font(.system(size: 52))
                    .frame(height: 64)
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding()
            .navigationTitle("Moneyger")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var isSaving: Bool {
        if case .saving = model.state { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .saving:
            ProgressView().controlSize(.large)
        case .saved:
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.tint)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch model.state {
        case .saving: return "Adding to Moneyger…"
        case .saved(let count): return count == 1 ? "Ready to import" : "\(count) files ready to import"
        case .failed: return "Couldn't add"
        }
    }

    private var message: String {
        switch model.state {
        case .saving: return ""
        case .saved: return "Open Moneyger and it will read the statement and add its transactions automatically."
        case .failed(let error): return error
        }
    }
}
