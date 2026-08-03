#if os(macOS)
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// Settings → Displays → "Groups" (Issue #39). Display-agnostic, so it renders once at the bottom of
/// the Displays tab rather than per display: create/rename/delete a group, tick which displays belong
/// to it, and nudge each member's offset. The per-display "Synced with <group>" caption lives in
/// `DisplayDetailView`.
struct DisplayGroupsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ODCard(title: "Groups",
               footnote: "Moving any member\u{2019}s brightness moves the rest, each at its own offset. "
                       + "Nudging a display right after it follows re-teaches that offset instead of "
                       + "moving the group. Grouped displays are left out of Adaptive Display.") {
            if model.settings.displayGroups.isEmpty {
                Text("Group displays to move their brightness together.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 11).padding(.vertical, 10)
            } else {
                ForEach(model.settings.displayGroups) { group in
                    DisplayGroupSection(group: group)
                    ODDivider()
                }
            }
            NewDisplayGroupRow()
        }
    }
}

private struct DisplayGroupSection: View {
    @EnvironmentObject private var model: AppModel
    let group: DisplayGroup
    @State private var draftName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ODRow(group.name) {
                HStack(spacing: ODSpacing.sm) {
                    TextField("Group name", text: $draftName)
                        .textFieldStyle(.roundedBorder).frame(width: 140)
                        .onSubmit { commitName() }
                    Button(role: .destructive) {
                        model.deleteDisplayGroup(group)
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            ODDivider()
            ODRow("Sync") {
                HStack(spacing: ODSpacing.md) {
                    Toggle("Brightness", isOn: Binding(
                        get: { group.syncBrightness },
                        set: { model.setDisplayGroupSyncBrightness($0, for: group) }))
                    Toggle("Contrast", isOn: Binding(
                        get: { group.syncContrast },
                        set: { model.setDisplayGroupSyncContrast($0, for: group) }))
                }
            }
            ForEach(candidateMembers, id: \.self) { member in
                ODDivider()
                DisplayGroupMemberRow(group: group, member: member)
            }
        }
        .onAppear { draftName = group.name }
    }

    /// Every display that could sit in this group: the ones connected right now, plus members that
    /// aren't present (unplugged, turned off) so their membership stays visible and removable.
    private var candidateMembers: [DisplayRecordID] {
        let live = model.displays.map(\.recordID)
        return live + group.memberRecordIDs.filter { !live.contains($0) }
    }

    /// Renaming can be refused (blank, or a name another group already holds) — put the field back to
    /// the stored name rather than leaving the user looking at a name that didn't take.
    private func commitName() {
        if !model.renameDisplayGroup(group, to: draftName) { draftName = group.name }
    }
}

private struct DisplayGroupMemberRow: View {
    @EnvironmentObject private var model: AppModel
    let group: DisplayGroup
    let member: DisplayRecordID

    var body: some View {
        ODRow(model.groupMemberName(for: member), secondary: membershipNote) {
            HStack(spacing: ODSpacing.sm) {
                if isMember, group.syncBrightness {
                    Text(offsetLabel)
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Slider(value: offsetBinding, in: offsetRange).frame(width: 110)
                }
                Toggle("", isOn: Binding(
                    get: { isMember },
                    set: { model.setDisplayGroupMembership(member, in: group, isMember: $0) }))
                    .labelsHidden()
            }
        }
    }

    private var isMember: Bool { group.contains(member) }

    /// Names the two states worth explaining: a member that isn't plugged in, and a display another
    /// group already owns (ticking this one moves it here, since a display belongs to one group).
    private var membershipNote: String? {
        if isMember, !model.displays.contains(where: { $0.recordID == member }) { return "Not connected" }
        if !isMember, let other = model.displayGroup(containing: member) { return "In \(other.name)" }
        return nil
    }

    private var offsetLabel: String {
        let percent = Int((group.offset(for: member) * 100).rounded())
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    /// The nominal ±50% span, widened when a learned offset already sits outside it — otherwise the
    /// slider would snap a real learned value back the moment the row appeared.
    private var offsetRange: ClosedRange<Double> {
        let learned = abs(Double(group.offset(for: member)))
        let bound = max(Double(DisplayGroup.nominalOffsetLimit), learned)
        return -bound...bound
    }

    private var offsetBinding: Binding<Double> {
        Binding(get: { Double(group.offset(for: member)) },
                set: { model.setDisplayGroupOffset(Float($0), for: member, in: group) })
    }
}

private struct NewDisplayGroupRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftName = ""

    var body: some View {
        ODRow("New group") {
            HStack(spacing: ODSpacing.sm) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder).frame(width: 140)
                    .onSubmit { create() }
                Button("Add") { create() }
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func create() {
        if model.createDisplayGroup(named: draftName) { draftName = "" }
    }
}
#endif
