import SwiftUI

struct QRCodeContentView: View {
    let selfieImage: UIImage
    let qrCodeImage: UIImage?
    let isVerified: Bool
    let similarity: Double  // Already in [0.0 ... 1.0] or [0...100] depending on usage
    let realProb: Double
    let realProbAppleAPI: Double

    @Environment(\.presentationMode) var presentationMode

    init(
        selfieImage: UIImage,
        qrCodeImage: UIImage?,
        isVerified: Bool,
        similarity: Double = 0.0,
        realProb: Double = 0.0,
        realProbAppleAPI: Double = 0.0
    ) {
        self.selfieImage = selfieImage
        self.qrCodeImage = qrCodeImage
        self.isVerified = isVerified
        self.similarity = similarity
        self.realProb = realProb
        self.realProbAppleAPI = realProbAppleAPI
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)

            VStack(spacing: 12) {
                // Selfie image with verification icon overlay (bottom-right)
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: selfieImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(16)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.4)

                    ZStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Color.gray.opacity(0.3))
                        Image(systemName: isVerified ? "checkmark.circle.fill" : "octagon.fill")
                            .foregroundColor(isVerified ? .green : .red)
                            .font(.system(size: 30))
                    }
                    .padding(8)
                }

                // HStack with Similarity, Real, and API labels side-by-side
                HStack(spacing: 16) {
                    infoLabel(title: "Similarity", value: similarity)
                    infoLabel(title: "Real", value: realProb)
                    infoLabel(title: "API", value: realProbAppleAPI)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)

                // QR code (if present)
                if let qrCodeImage = qrCodeImage {
                    Image(uiImage: qrCodeImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.3)
                        .padding(.top, 8)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.9)

            // Dismiss button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: .qrCodeDismissed, object: nil)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }

    // Helper view for labeled values
    @ViewBuilder
    private func infoLabel(title: String, value: Double) -> some View {
        Text("\(title): \(String(format: "%.0f", value * 100))%")
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

// Notification extension
extension Notification.Name {
    static let qrCodeDismissed = Notification.Name("qrCodeDismissed")
}

