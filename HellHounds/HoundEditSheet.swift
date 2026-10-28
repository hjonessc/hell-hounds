//
//  HoundEditSheet.swift
//  HellHounds
//
//  Renaming a hound and picking its symbol or photo, plus the avatar the
//  card shows for it.
//

import PhotosUI
import SwiftUI
import UIKit

struct HoundEditSheet: View {
    let houndIndex: Int
    @State var look: HoundLook
    let save: @MainActor (HoundLook) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Hound \(houndIndex + 1)", text: $look.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("edit-name")
                }
                Section("Photo") {
                    HStack(spacing: 16) {
                        HoundAvatar(systemImage: look.symbol, photoData: look.photoData, isOn: true, size: 64)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(look.photoData == nil ? "Choose Photo" : "Change Photo", selection: $photoItem, matching: .images)
                            if look.photoData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    look.photoData = nil
                                    photoItem = nil
                                }
                            }
                        }
                    }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(HoundLook.symbols, id: \.self) { symbol in
                            let isSelected = look.symbol == symbol
                            Button {
                                look.symbolName = symbol == HoundLook.defaultSymbol ? nil : symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(isSelected ? .white : .orange)
                                    .background(isSelected ? Color.orange : Color.orange.opacity(0.12), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Symbol")
                } footer: {
                    Text("Shown when the hound has no photo.")
                }
                Section {
                    Button("Reset to Default", role: .destructive) {
                        look = HoundLook()
                        photoItem = nil
                    }
                    .disabled(look == HoundLook())
                }
            }
            .navigationTitle(look.title(houndIndex: houndIndex))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        save(look)
                        dismiss()
                    }
                    .accessibilityIdentifier("edit-save")
                }
            }
            .task(id: photoItem) {
                guard let photoItem,
                      let data = try? await photoItem.loadTransferable(type: Data.self),
                      let jpeg = await Self.downscaledJPEG(data)
                else { return }
                look.photoData = jpeg
            }
        }
        // Sheets don't inherit the tab view's tint.
        .tint(.orange)
    }

    /// Photos sync through iCloud, so keep them small: at most 512 px, JPEG.
    /// Redrawing also drops the photo's metadata, location included.
    nonisolated static func downscaledJPEG(_ data: Data, maxPixels: CGFloat = 512) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxPixels / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// A hound's photo in a circle, or its symbol.
struct HoundAvatar: View {
    let systemImage: String
    var photoData: Data?
    let isOn: Bool
    var size: CGFloat = 28

    var body: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(isOn ? Color.orange : Color.secondary, lineWidth: 2) }
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemImage)
                .font(size > 40 ? .largeTitle : .body)
                .foregroundStyle(isOn ? .orange : .secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    HoundEditSheet(houndIndex: 2, look: HoundLook(name: "Cerberus", symbolName: "flame.fill")) { _ in }
}
