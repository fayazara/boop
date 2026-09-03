//
//  PopupView.swift
//  Boop
//

import AppKit
import SwiftUI

struct PopupView: View {
    @Bindable var controller: PopupController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            body(for: controller)
            Divider().opacity(0.6)
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(.boopMark)
                .resizable()
                .renderingMode(.template)
                .frame(width: 13, height: 13)
                .foregroundStyle(.primary)
            Text("Improve Writing")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            if controller.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            }
            Text(controller.modelName)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for controller: PopupController) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                Group {
                    if let error = controller.errorMessage {
                        errorView(error)
                    } else if controller.output.isEmpty {
                        placeholder
                    } else {
                        Text(controller.output)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Color.clear.frame(height: 1).id(Self.bottomAnchor)
            }
            .onChange(of: controller.output) {
                // Keep the newest tokens in view while the response streams in.
                // Deliberately unanimated: animating once per token makes SwiftUI
                // complain about updating multiple times per frame.
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        HStack(spacing: 6) {
            Text(controller.isReasoning ? "Thinking…" : "Improving…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                controller.regenerate()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Regenerate")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller.original.isEmpty || controller.isStreaming)

            Spacer(minLength: 0)

            Button {
                controller.copyOutput()
            } label: {
                Text(controller.didCopy ? "Copied" : "Copy")
                    .frame(minWidth: 44)
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!controller.canAct)

            Button {
                controller.pasteOutput()
            } label: {
                Text(controller.pasteLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 40)
            }
            .help("Paste into \(controller.targetAppName ?? "the previous app") (↩)")
            .buttonStyle(.borderedProminent)
            .disabled(!controller.canAct)
        }
        .controlSize(.small)
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private static let bottomAnchor = "boop.bottom"
}
