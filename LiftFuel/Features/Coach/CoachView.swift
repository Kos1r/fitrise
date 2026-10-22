import PhotosUI
import SwiftData
import SwiftUI

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachEngine.self) private var coach
    @Environment(AppRouter.self) private var router
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]

    @State private var draft = ""
    @State private var pendingImage: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var editingMeal: MealEditorTarget?
    @State private var showManualAdd = false
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        [
            String(localized: "How many calories and protein do I still need today?"),
            String(localized: "What should I eat for dinner to hit my protein?"),
            String(localized: "Give me a high-protein snack idea for after training.")
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.m) {
                        if !CoachConnection.isConfigured && !LaunchFlags.isUITesting {
                            setupBanner
                        }
                        if messages.isEmpty {
                            welcome
                        }
                        ForEach(messages) { message in
                            ChatRow(
                                message: message,
                                onRetry: { coach.retry(message, in: modelContext) },
                                onEditMeal: { editingMeal = .edit($0) },
                                onRemoveMeal: { coach.removeMeal(for: message, in: modelContext) }
                            )
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if coach.isResponding {
                            if coach.streamingText.isEmpty {
                                TypingIndicator()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                AssistantBubble(text: coach.streamingText)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.m)
                    .animation(.snappySpring, value: messages.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: coach.streamingText) { _, _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: coach.isResponding) { _, _ in scrollToBottom(proxy) }
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Add meal manually", systemImage: "square.and.pencil") { showManualAdd = true }
                        Button("Clear conversation", systemImage: "trash", role: .destructive) { clearChat() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .sheet(item: $editingMeal) { MealEditorView(target: $0) }
            .sheet(isPresented: $showManualAdd) { MealEditorView(target: .new(day: .now)) }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    pendingImage = ImageProcessor.preparedJPEG(from: image)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        pendingImage = ImageProcessor.preparedJPEG(from: data)
                    }
                    photoItem = nil
                }
            }
        }
    }

    // MARK: Sections

    private var welcome: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.brand)
                .padding(Spacing.l)
                .background(Color.brand.opacity(0.12), in: Circle())
            VStack(spacing: Spacing.xs) {
                Text("Your nutrition coach").font(.title2.weight(.bold))
                Text("Tell me what you ate or send a photo — I'll estimate calories and macros and log it for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Spacing.s) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        coach.send(text: suggestion, imageData: nil, in: modelContext)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.m)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Spacing.xl)
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "bolt.horizontal.circle.fill").font(.title2).foregroundStyle(Color("ShouldersColor"))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Connect the coach").font(.subheadline.weight(.semibold))
                Text("Add your proxy URL and app token in Settings. Until then you can log meals manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Settings") { router.showSettings = true }
                    Button("Add manually") { showManualAdd = true }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.m)
        .background(Color("ShouldersColor").opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private var inputBar: some View {
        VStack(spacing: Spacing.s) {
            if let pendingImage, let image = UIImage(data: pendingImage) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                self.pendingImage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo")
                        }
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: Spacing.s) {
                Menu {
                    Button("Take photo", systemImage: "camera") { showCamera = true }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color.cardElevated, in: Circle())
                }
                .accessibilityLabel("Add meal photo")
                .accessibilityIdentifier("coach.photo")

                TextField("What did you eat?", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s + 2)
                    .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .submitLabel(.send)
                    .accessibilityIdentifier("coach.input")

                Button {
                    send()
                } label: {
                    Image(systemName: coach.isResponding ? "stop.fill" : "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 42, height: 42)
                        .background(Color.brand, in: Circle())
                }
                .disabled(!coach.isResponding && draft.trimmingCharacters(in: .whitespaces).isEmpty && pendingImage == nil)
                .accessibilityLabel(coach.isResponding ? "Stop" : "Send")
                .accessibilityIdentifier("coach.send")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }

    // MARK: Actions

    private func send() {
        if coach.isResponding {
            coach.cancel()
            return
        }
        coach.send(text: draft, imageData: pendingImage, in: modelContext)
        draft = ""
        pendingImage = nil
        Haptics.impact(.light)
    }

    private func clearChat() {
        for message in messages { modelContext.delete(message) }
        modelContext.saveQuietly()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.snappySpring) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Rows

struct ChatRow: View {
    let message: ChatMessage
    var onRetry: () -> Void
    var onEditMeal: (PersistentIdentifier) -> Void
    var onRemoveMeal: () -> Void

    var body: some View {
        switch (message.role, message.kind) {
        case (.user, _):
            UserBubble(message: message, onRetry: onRetry)
        case (.assistant, .mealCard):
            MealCardView(card: message, onEdit: onEditMeal, onRemove: onRemoveMeal)
        case (.assistant, .text):
            AssistantBubble(text: message.text)
        }
    }
}

struct UserBubble: View {
    let message: ChatMessage
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            if let data = message.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .accessibilityLabel("Meal photo")
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s + 2)
                    .foregroundStyle(Color.onAccent)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            if message.status == .failed {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(message.errorDescription ?? String(localized: "Not sent"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Button("Retry", action: onRetry)
                        .font(.caption.weight(.bold))
                        .accessibilityIdentifier("coach.retry")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .opacity(message.status == .sending ? 0.7 : 1)
    }
}

struct AssistantBubble: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.brand)
                .frame(width: 26, height: 26)
                .background(Color.brand.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(markdown)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s + 2)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 32)
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(reduceMotion ? 0.6 : 0.3 + 0.7 * abs(sin(phase + Double(index) * 0.6)))
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Color.cardBackground, in: Capsule())
        .padding(.leading, 34)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
        .accessibilityLabel("Coach is typing")
    }
}

/// Confirmation card shown after the coach logs a meal: items + macros, Edit / Remove / Looks good.
struct MealCardView: View {
    let card: ChatMessage
    var onEdit: (PersistentIdentifier) -> Void
    var onRemove: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var confirmed = false

    private var meal: MealEntry? {
        card.mealID.flatMap { modelContext.meal(id: $0) }
    }

    var body: some View {
        Group {
            if card.mealRemoved || meal == nil {
                HStack {
                    Image(systemName: "arrow.uturn.backward.circle")
                    Text("Removed “\(card.text)” from your log").font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 34)
            } else if let meal {
                mealCard(for: meal)
            }
        }
    }

    private func mealCard(for meal: MealEntry) -> some View {
        let totals = meal.totals
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.brand)
                Text("· \(meal.mealType.title) · \(meal.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if meal.confidence == .medium {
                    Chip(title: String(localized: "Estimate"), symbol: "questionmark.circle", tint: Color("ShouldersColor"))
                }
            }
            Text(meal.name).font(.headline)
            VStack(spacing: Spacing.xs) {
                ForEach(meal.orderedItems) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).font(.subheadline.weight(.medium))
                            if !item.quantityDescription.isEmpty {
                                Text("\(item.quantityDescription)\(item.grams > 0 ? " · ~\(Int(item.grams)) g" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(item.calories)) kcal").font(.subheadline.monospacedDigit())
                    }
                }
            }
            Divider()
            HStack(spacing: Spacing.m) {
                macro("Calories", "\(Int(totals.calories))", .brand)
                macro("Protein", "\(Int(totals.protein)) g", .protein)
                macro("Carbs", "\(Int(totals.carbs)) g", .carbs)
                macro("Fat", "\(Int(totals.fat)) g", .fat)
            }
            HStack(spacing: Spacing.s) {
                Button("Edit") { onEdit(meal.persistentModelID) }
                    .buttonStyle(SecondaryButtonStyle(tint: .secondary, compact: true))
                Button("Remove", role: .destructive) {
                    withAnimation(.snappySpring) { onRemove() }
                    Haptics.warning()
                }
                .buttonStyle(SecondaryButtonStyle(tint: .red, compact: true))
                .accessibilityIdentifier("mealCard.remove")
                Spacer()
                Button {
                    withAnimation(.snappySpring) { confirmed = true }
                    Haptics.success()
                } label: {
                    Label(confirmed ? "Saved" : "Looks good", systemImage: confirmed ? "checkmark" : "hand.thumbsup.fill")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(confirmed)
                .accessibilityIdentifier("mealCard.confirm")
            }
        }
        .padding(Spacing.l)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.4), lineWidth: 1)
        )
        .padding(.leading, 34)
    }

    private func macro(_ title: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// UIKit camera wrapper (PhotosPicker covers the library).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
