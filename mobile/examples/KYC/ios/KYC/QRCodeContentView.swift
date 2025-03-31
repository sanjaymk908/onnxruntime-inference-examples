//
//  QRCodeContentView.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 3/28/25.
//

import SwiftUI

struct QRCodeContentView: View {
    let selfieImage: UIImage
    let qrCodeImage: UIImage
    let isVerified: Bool
    
    // Access presentation mode for dismissing the view
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Selfie image with verification status overlay
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: selfieImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: UIScreen.main.bounds.height * 0.4)
                        .clipped()
                    
                    // Gear icon with checkmark or X mark
                    ZStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Color.gray.opacity(0.3))
                        
                        Image(systemName: isVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isVerified ? .green : .red)
                            .font(.system(size: 30))
                    }
                    .padding(8)
                }
                
                // QR code image
                Image(uiImage: qrCodeImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: UIScreen.main.bounds.height * 0.4)
            }
            .frame(width: UIScreen.main.bounds.width * 0.9)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
            
            // Dismiss button in the upper-right corner
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
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
    }
}

extension Notification.Name {
    static let qrCodeDismissed = Notification.Name("qrCodeDismissed")
}

