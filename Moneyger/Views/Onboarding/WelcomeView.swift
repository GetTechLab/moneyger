import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("Moneyger")
                        .font(.largeTitle.bold())

                    Text("Automatically track your spending from bank emails")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    FeatureRow(icon: "envelope.fill", color: .blue, title: "Gmail Integration", description: "Reads bank & credit card emails automatically")
                    FeatureRow(icon: "brain.fill", color: .purple, title: "AI-Powered", description: "Extracts transactions using Gemini, Claude, or GPT-4o")
                    FeatureRow(icon: "chart.bar.fill", color: .green, title: "Smart Analytics", description: "Spending insights across all currencies")
                }
                .padding(.horizontal)

                Spacer()

                NavigationLink {
                    GmailConnectView()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                }

                Spacer().frame(height: 20)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
