import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var model: OnboardingFlowModel
    @StateObject private var photoLibrary = PhotoLibraryService()

    var body: some View {
        Group {
            switch model.stage {
            case .welcome: welcome
            case .photoAccess: photoAccess
            case .generationTime: generationTime
            case .todayJournal: todayJournal
            case .historyInvitation: historyInvitation
            case .backfillRange, .backfillScanning, .backfillConfirmation, .backfillQueue, .backfillComplete:
                BackfillFlowView(model: model, isOnboarding: true)
            case .finished: TimelineHomeView()
            }
        }
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .tint(HetkiaPalette.amber)
    }

    private var welcome: some View {
        page(symbol: "book.closed", eyebrow: "onboarding.eyebrow", title: "onboarding.welcome.title", detail: "onboarding.welcome.detail") {
            Spacer()
            action("onboarding.start") { model.begin() }
        }
    }

    private var photoAccess: some View {
        page(symbol: "photo.on.rectangle.angled", eyebrow: "onboarding.step.photos", title: "onboarding.photos.title", detail: "onboarding.photos.detail") {
            VStack(alignment: .leading, spacing: 12) {
                Label(photoAccessTitle, systemImage: photoAccessSymbol)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(HetkiaPalette.ink)
                Text(photoAccessDetail).font(.system(size: 12)).lineSpacing(3)
                    .foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if photoLibrary.authorizationStatus == .notDetermined || photoLibrary.authorizationStatus == .denied || photoLibrary.authorizationStatus == .restricted {
                    Button("onboarding.photos.request") {
                        Task {
                            let status = await photoLibrary.requestAuthorization()
                            model.choosePhotoAccess(status == .authorized ? .full : status == .limited ? .limited : .denied)
                        }
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
                }
            }
            .padding(15).background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 15))
            .padding(.vertical, 10)
            footnote("onboarding.photos.permission-note")
            action("common.continue") {
                let status = photoLibrary.authorizationStatus
                model.choosePhotoAccess(status == .authorized ? .full : status == .limited ? .limited : .denied)
                model.continueFromPhotoAccess()
            }
        }
        .onAppear { photoLibrary.refreshAuthorization() }
    }

    private var generationTime: some View {
        page(symbol: "clock", eyebrow: "onboarding.step.schedule", title: "onboarding.schedule.title", detail: "onboarding.schedule.detail") {
            DatePicker("onboarding.schedule.time", selection: Binding(get: { model.preferredTime }, set: model.setPreferredTime), displayedComponents: .hourAndMinute)
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.wheel)
                #endif
                .frame(maxHeight: 150)
                .padding(.vertical, 10)
            footnote("onboarding.schedule.note")
            action("common.continue") { model.continueToToday() }
        }
    }

    private var todayJournal: some View {
        page(symbol: "sun.horizon", eyebrow: "onboarding.step.today", title: "onboarding.today.title", detail: "onboarding.today.detail") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    ProgressView(value: model.todayProgress)
                        .tint(HetkiaPalette.amber)
                    Text(statusTitle(model.todayStatus))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                }
                if [.noPhotos, .modelUnavailable, .failed, .existing].contains(model.todayStatus) {
                    Label(statusDetail(model.todayStatus), systemImage: statusSymbol(model.todayStatus))
                        .font(.system(size: 13))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.vertical, 12)
            HStack(spacing: 12) {
                if model.todayStatus == .failed || model.todayStatus == .modelUnavailable || model.todayStatus == .noPhotos {
                    Button("onboarding.today.manual") { model.continueManuallyWithoutAI() }
                        .buttonStyle(.bordered)
                }
                if model.todayStatus == .failed || model.todayStatus == .modelUnavailable {
                    Button("onboarding.today.retry") { model.retryToday() }
                        .buttonStyle(.bordered)
                }
                action("common.continue") { model.continueFromToday() }
            }
        }
    }

    private var historyInvitation: some View {
        page(symbol: "calendar.badge.clock", eyebrow: "onboarding.step.history", title: "onboarding.history.title", detail: "onboarding.history.detail") {
            Spacer()
            Button("onboarding.history.skip") { model.skipHistory() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    private func page<Content: View>(symbol: String, eyebrow: LocalizedStringKey, title: LocalizedStringKey, detail: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(HetkiaPalette.amber)
                    .frame(width: 48, height: 48).background(.white.opacity(0.8), in: Circle())
                Spacer()
                Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            Text(title).font(.system(size: 30, weight: .regular, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(detail).font(.system(size: 14)).lineSpacing(4).foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(24)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private func action(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15).background(HetkiaPalette.amber, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func footnote(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func statusTitle(_ status: TodayJournalStatus) -> LocalizedStringKey {
        switch status {
        case .idle: return "onboarding.today.status.idle"
        case .existing: return "onboarding.today.status.existing"
        case .scanning: return "onboarding.today.status.scanning"
        case .preparing: return "onboarding.today.status.preparing"
        case .writing: return "onboarding.today.status.writing"
        case .ready: return "onboarding.today.status.ready"
        case .noPhotos: return "onboarding.today.status.no-photos"
        case .modelUnavailable: return "onboarding.today.status.model-unavailable"
        case .failed: return "onboarding.today.status.failed"
        }
    }

    private func statusDetail(_ status: TodayJournalStatus) -> LocalizedStringKey {
        switch status {
        case .existing: return "onboarding.today.detail.existing"
        case .noPhotos: return "onboarding.today.detail.no-photos"
        case .modelUnavailable: return "onboarding.today.detail.model-unavailable"
        default: return "onboarding.today.detail.failed"
        }
    }

    private func statusSymbol(_ status: TodayJournalStatus) -> String {
        switch status { case .existing: "checkmark.circle"; case .noPhotos: "photo"; case .modelUnavailable: "cpu"; default: "exclamationmark.circle" }
    }

    private var photoAccessTitle: LocalizedStringKey {
        switch photoLibrary.authorizationStatus {
        case .authorized: "onboarding.photos.status.full"
        case .limited: "onboarding.photos.status.limited"
        case .denied: "onboarding.photos.status.denied"
        case .restricted: "onboarding.photos.status.restricted"
        case .notDetermined: "onboarding.photos.status.unknown"
        @unknown default: "onboarding.photos.status.unknown"
        }
    }

    private var photoAccessDetail: LocalizedStringKey {
        switch photoLibrary.authorizationStatus {
        case .authorized: "onboarding.photos.detail.full"
        case .limited: "onboarding.photos.detail.limited"
        case .denied: "onboarding.photos.detail.denied"
        case .restricted: "onboarding.photos.detail.restricted"
        case .notDetermined: "onboarding.photos.detail.unknown"
        @unknown default: "onboarding.photos.detail.unknown"
        }
    }

    private var photoAccessSymbol: String {
        switch photoLibrary.authorizationStatus {
        case .authorized, .limited: "checkmark.circle"
        case .denied, .restricted: "exclamationmark.circle"
        case .notDetermined: "circle.dashed"
        @unknown default: "circle.dashed"
        }
    }

}

struct BackfillFlowView: View {
    @ObservedObject var model: OnboardingFlowModel
    let isOnboarding: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customEnd = Date.now

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("onboarding.backfill.title").font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(HetkiaPalette.ink)
                Spacer()
                if !isOnboarding { Button("common.close") { dismiss() }.foregroundStyle(HetkiaPalette.secondaryInk) }
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            Group {
                switch model.stage {
                case .backfillRange: rangeScreen
                case .backfillScanning: scanningScreen
                case .backfillConfirmation: confirmationScreen
                case .backfillQueue: queueScreen
                case .backfillComplete: completeScreen
                default: rangeScreen
                }
            }
        }
        .frame(maxWidth: 600, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .tint(HetkiaPalette.amber)
    }

    private var rangeScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.backfill.range.detail").font(.system(size: 13)).foregroundStyle(HetkiaPalette.secondaryInk)
            ForEach(BackfillRangePreset.allCases, id: \.self) { range in
                Button { model.selectRange(range) } label: {
                    HStack {
                        Text(rangeTitle(range)).font(.system(size: 14, weight: .medium)).foregroundStyle(HetkiaPalette.ink)
                        Spacer()
                        if model.rangePreset == range { Image(systemName: "checkmark.circle.fill").foregroundStyle(HetkiaPalette.amber) }
                    }.padding(14).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            if model.rangePreset == .custom {
                DatePicker("onboarding.backfill.start", selection: $customStart, displayedComponents: .date)
                DatePicker("onboarding.backfill.end", selection: $customEnd, displayedComponents: .date)
            }
            Spacer()
            primaryAction("onboarding.backfill.scan") {
                if model.rangePreset == .custom { model.setCustomRange(start: customStart, end: customEnd) }
                model.beginBackfillScan()
            }
        }.padding(20)
    }

    private var scanningScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 42, weight: .light)).foregroundStyle(HetkiaPalette.amber)
            Text("onboarding.backfill.scanning").font(.system(size: 17, weight: .medium, design: .serif))
            ProgressView(value: model.scanProgress).tint(HetkiaPalette.amber)
            Text("\(Int(model.scanProgress * 100))%").font(.system(size: 12, design: .rounded)).foregroundStyle(HetkiaPalette.secondaryInk)
            Text("onboarding.backfill.scan.note").font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk)
            Spacer()
        }.padding(28).frame(maxWidth: .infinity)
    }

    private var confirmationScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("onboarding.backfill.selected-count", comment: ""), model.selectedDateCount))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Spacer()
                Button("onboarding.backfill.select-all") { model.setAllDatesSelected(true) }.font(.system(size: 12))
                Button("onboarding.backfill.select-none") { model.setAllDatesSelected(false) }.font(.system(size: 12))
            }
            Text("onboarding.backfill.confirm.note").font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk)
            List {
                ForEach(model.dateGroups) { group in
                    Button { model.toggleDate(group.id) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: group.hasExistingJournal ? "checkmark.circle.fill" : (group.isSelected ? "checkmark.circle.fill" : "circle"))
                                .foregroundStyle(group.hasExistingJournal || group.isSelected ? HetkiaPalette.amber : HetkiaPalette.line)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.date.formatted(date: .long, time: .omitted)).font(.system(size: 13, weight: .medium)).foregroundStyle(HetkiaPalette.ink)
                                Text(String(format: NSLocalizedString("onboarding.backfill.photo-count", comment: ""), group.photoCount)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
                            }
                            Spacer()
                            if group.hasExistingJournal { Text("onboarding.backfill.existing").font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(Color.white.opacity(0.65))
                        .disabled(group.hasExistingJournal)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
            primaryAction("onboarding.backfill.queue") { model.beginQueue() }.padding(.horizontal, 18).padding(.bottom, 12)
        }
    }

    private var queueScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(format: NSLocalizedString("onboarding.backfill.completed-count", comment: ""), model.completedCount, model.queueItems.count), systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Spacer()
                if model.isQueuePaused {
                    Button("onboarding.backfill.resume") { model.resumeQueue() }
                } else {
                    Button("onboarding.backfill.pause") { model.pauseQueue() }
                }
            }
            List {
                ForEach(model.queueItems) { item in
                    HStack(spacing: 10) {
                        queueStatusSymbol(item.status)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.date.formatted(date: .long, time: .omitted)).font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.ink)
                            if item.status == .processing { ProgressView(value: item.progress).tint(HetkiaPalette.amber) }
                            else { Text(queueStatusTitle(item.status)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk) }
                        }
                        Spacer()
                        if item.status == .pending { Button { model.cancelQueueItem(item.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) }
                    }.padding(.vertical, 3).listRowBackground(Color.white.opacity(0.65))
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
            HStack {
                if model.failedCount > 0 { Button("onboarding.backfill.retry") { model.retryFailedQueueItems() }.buttonStyle(.borderedProminent) }
                if model.isQueuePaused && model.failedCount == 0 { Button("onboarding.backfill.continue-later") { if isOnboarding { model.finishFlow() } else { dismiss() } } }
            }.padding(.horizontal, 18).padding(.bottom, 12)
        }.padding(.horizontal, 18)
    }

    private var completeScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal").font(.system(size: 48, weight: .light)).foregroundStyle(HetkiaPalette.amber)
            Text("onboarding.backfill.complete.title").font(.system(size: 25, weight: .regular, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(String(format: NSLocalizedString("onboarding.backfill.complete.summary", comment: ""), model.completedCount, model.failedCount, model.skippedCount))
                .font(.system(size: 13)).foregroundStyle(HetkiaPalette.secondaryInk).multilineTextAlignment(.center)
            Spacer()
            primaryAction("onboarding.backfill.done") { if isOnboarding { model.finishFlow() } else { dismiss() } }
        }.padding(24)
    }

    private func primaryAction(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(HetkiaPalette.amber, in: Capsule()) }.buttonStyle(.plain)
    }

    private func rangeTitle(_ range: BackfillRangePreset) -> LocalizedStringKey {
        switch range { case .sevenDays: "onboarding.backfill.range.week"; case .thirtyDays: "onboarding.backfill.range.month"; case .yearToDate: "onboarding.backfill.range.year"; case .custom: "onboarding.backfill.range.custom" }
    }

    @ViewBuilder private func queueStatusSymbol(_ status: BackfillItemStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(HetkiaPalette.line)
        case .processing: Image(systemName: "arrow.trianglehead.2.clockwise").foregroundStyle(HetkiaPalette.amber)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(HetkiaPalette.amber)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .skipped, .cancelled: Image(systemName: "minus.circle").foregroundStyle(HetkiaPalette.secondaryInk)
        }
    }

    private func queueStatusTitle(_ status: BackfillItemStatus) -> LocalizedStringKey {
        switch status {
        case .pending: "onboarding.backfill.status.pending"
        case .processing: "onboarding.backfill.status.processing"
        case .completed: "onboarding.backfill.status.completed"
        case .failed: "onboarding.backfill.status.failed"
        case .skipped: "onboarding.backfill.status.skipped"
        case .cancelled: "onboarding.backfill.status.cancelled"
        }
    }
}
