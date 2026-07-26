import PhotosUI
import simd
import SwiftUI
import UIKit

struct WallPhotosTabView: View {
    @Binding var project: RoomProject
    let onProjectChanged: () -> Void
    let onOpenWall2D: (UUID) -> Void
    let onOpenWall3D: (UUID) -> Void

    @State private var selectedWallID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                introductionCard

                ForEach(Array(project.walls.enumerated()), id: \.element.id) { index, wall in
                    let appearance = resolvedAppearance(for: wall, index: index)
                    Button {
                        selectedWallID = wall.id
                    } label: {
                        WallPhotoCard(
                            projectID: project.id,
                            wall: wall,
                            appearance: appearance,
                            photo: project.primaryPhoto(for: wall.id),
                            segments: project.photographicSegments(for: wall.id),
                            surfaces: projectedSurfaces(on: wall),
                            furniture: projectedFurniture(on: wall),
                            showFurnitureOverlay: project.showsFurnitureWithWallPhotos,
                            points: project.points.filter { $0.wallID == wall.id }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: Binding(
            get: { selectedWall != nil },
            set: { if !$0 { selectedWallID = nil } }
        )) {
            if let wall = selectedWall,
               let wallIndex = project.walls.firstIndex(where: { $0.id == wall.id }) {
                WallPhotoDetailView(
                    projectID: project.id,
                    wall: wall,
                    appearance: resolvedAppearance(for: wall, index: wallIndex),
                    photos: project.photos(for: wall.id),
                    segments: project.photographicSegments(for: wall.id),
                    points: project.points.filter { $0.wallID == wall.id },
                    surfaces: projectedSurfaces(on: wall),
                    furniture: projectedFurniture(on: wall),
                    showFurnitureOverlay: project.showsFurnitureWithWallPhotos,
                    onSaveAppearance: { updated in
                        updateAppearance(updated)
                    },
                    onImportPhoto: { data, source in
                        importPhoto(data, wallID: wall.id, source: source)
                    },
                    onSelectPhoto: { photoID in
                        setPrimaryPhoto(photoID, wallID: wall.id)
                    },
                    onDeletePhoto: { photo in
                        deletePhoto(photo)
                    },
                    onOpenWall2D: {
                        selectedWallID = nil
                        onOpenWall2D(wall.id)
                    },
                    onOpenWall3D: {
                        selectedWallID = nil
                        onOpenWall3D(wall.id)
                    }
                )
            }
        }
        .alert("تعذر تنفيذ العملية", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            project.normalizeWallPhotoMetadata()
            onProjectChanged()
        }
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("صور الجدران", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
            Text(
                "تظهر هنا صور الحوائط وألوانها وتغطية المسح الفوتوغرافي. "
                    + "الأجزاء الخضراء مصورة، والرمادية متخطاة، والزرقاء ما زالت مطلوبة."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Label(
                "صور الحوائط لها طبقة مستقلة في 2D و3D، وتبقى الكهرباء والفتحات والأبعاد فوقها.",
                systemImage: "square.3.layers.3d.top.filled"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.blue)

            Divider()

            Toggle(
                "إظهار مجسمات الفرش فوق صور الحوائط",
                isOn: Binding(
                    get: { project.showsFurnitureWithWallPhotos },
                    set: { newValue in
                        project.showsFurnitureWithWallPhotos = newValue
                        persist()
                    }
                )
            )
            .font(.subheadline.weight(.semibold))

            Text(
                project.showsFurnitureWithWallPhotos
                    ? "سيظهر الفرش الذي اكتشفه RoomPlan فوق معاينة الصور وفي 3D. أوقفه إذا كانت الصور نفسها تحتوي على الفرش وتريد منع التكرار."
                    : "سيُخفى مجسم الفرش عند عرض صور الحوائط، بينما تبقى الحوائط والفتحات والكهرباء ظاهرة."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectedWall: WallSnapshot? {
        guard let selectedWallID else { return nil }
        return project.walls.first { $0.id == selectedWallID }
    }

    private func resolvedAppearance(
        for wall: WallSnapshot,
        index: Int
    ) -> WallAppearance {
        project.wallAppearance(for: wall.id)
            ?? WallAppearance(
                wallID: wall.id,
                displayName: "الحائط \(index + 1)"
            )
    }

    private func updateAppearance(_ updated: WallAppearance) {
        project.normalizeWallPhotoMetadata()
        guard let index = project.wallAppearances?.firstIndex(where: {
            $0.wallID == updated.wallID
        }) else { return }
        project.wallAppearances?[index] = updated
        persist()
    }

    private func importPhoto(
        _ data: Data,
        wallID: UUID,
        source: WallPhotoSource
    ) -> UUID? {
        do {
            let asset = try WallPhotoStorage.importImage(
                data: data,
                projectID: project.id,
                wallID: wallID,
                source: source
            )
            var photos = project.wallPhotos ?? []
            photos.append(asset)
            project.wallPhotos = photos
            project.normalizeWallPhotoMetadata()
            if let index = project.wallAppearances?.firstIndex(where: {
                $0.wallID == wallID
            }) {
                project.wallAppearances?[index].primaryPhotoID = asset.id
                project.wallAppearances?[index].visualMode = .capturedPhotos
            }
            persist()
            return asset.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func setPrimaryPhoto(_ photoID: UUID, wallID: UUID) {
        project.normalizeWallPhotoMetadata()
        guard project.photos(for: wallID).contains(where: { $0.id == photoID }),
              let index = project.wallAppearances?.firstIndex(where: {
                $0.wallID == wallID
              }) else { return }
        project.wallAppearances?[index].primaryPhotoID = photoID
        project.wallAppearances?[index].visualMode = .capturedPhotos
        persist()
    }

    private func deletePhoto(_ photo: WallPhotoAsset) {
        WallPhotoStorage.delete(projectID: project.id, asset: photo)
        project.wallPhotos?.removeAll { $0.id == photo.id }
        project.normalizeWallPhotoMetadata()
        persist()
    }

    private func persist() {
        onProjectChanged()
    }

    private func projectedSurfaces(on wall: WallSnapshot) -> [WallPhotoSurfaceProjection] {
        let inverse = simd_inverse(wall.matrix)
        return project.surfaces.compactMap { surface in
            let local = simd_mul(inverse, surface.matrix.columns.3)
            guard abs(local.z) <= 0.30,
                  abs(local.x) <= wall.width / 2 + surface.width / 2 else {
                return nil
            }
            return WallPhotoSurfaceProjection(
                kind: surface.kind,
                centerX: local.x,
                centerY: local.y,
                width: surface.width,
                height: surface.height
            )
        }
    }

    private func projectedFurniture(on wall: WallSnapshot) -> [WallPhotoFurnitureProjection] {
        let inverseWall = simd_inverse(wall.matrix)
        return (project.objects ?? []).compactMap { object in
            let halfWidth = object.width / 2
            let halfHeight = object.height / 2
            let halfDepth = object.depth / 2
            let localCorners: [SIMD4<Float>] = [
                SIMD4(-halfWidth, -halfHeight, -halfDepth, 1),
                SIMD4(halfWidth, -halfHeight, -halfDepth, 1),
                SIMD4(halfWidth, halfHeight, -halfDepth, 1),
                SIMD4(-halfWidth, halfHeight, -halfDepth, 1),
                SIMD4(-halfWidth, -halfHeight, halfDepth, 1),
                SIMD4(halfWidth, -halfHeight, halfDepth, 1),
                SIMD4(halfWidth, halfHeight, halfDepth, 1),
                SIMD4(-halfWidth, halfHeight, halfDepth, 1)
            ]
            let wallCorners = localCorners.map { corner in
                simd_mul(inverseWall, simd_mul(object.matrix, corner))
            }
            guard let minX = wallCorners.map(\.x).min(),
                  let maxX = wallCorners.map(\.x).max(),
                  let minY = wallCorners.map(\.y).min(),
                  let maxY = wallCorners.map(\.y).max(),
                  let minimumDepth = wallCorners.map({ abs($0.z) }).min(),
                  minimumDepth <= 2.75,
                  maxX >= -wall.width / 2,
                  minX <= wall.width / 2,
                  maxY >= -wall.height / 2,
                  minY <= wall.height / 2 else {
                return nil
            }
            let clippedMinX = max(minX, -wall.width / 2)
            let clippedMaxX = min(maxX, wall.width / 2)
            let clippedMinY = max(minY, -wall.height / 2)
            let clippedMaxY = min(maxY, wall.height / 2)
            guard clippedMaxX - clippedMinX > 0.03,
                  clippedMaxY - clippedMinY > 0.03 else {
                return nil
            }
            return WallPhotoFurnitureProjection(
                id: object.id,
                title: object.title,
                centerX: (clippedMinX + clippedMaxX) / 2,
                centerY: (clippedMinY + clippedMaxY) / 2,
                width: clippedMaxX - clippedMinX,
                height: clippedMaxY - clippedMinY
            )
        }
    }
}

private struct WallPhotoCard: View {
    let projectID: UUID
    let wall: WallSnapshot
    let appearance: WallAppearance
    let photo: WallPhotoAsset?
    let segments: [WallPhotoSegment]
    let surfaces: [WallPhotoSurfaceProjection]
    let furniture: [WallPhotoFurnitureProjection]
    let showFurnitureOverlay: Bool
    let points: [ElectricalPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            WallElevationPreview(
                projectID: projectID,
                wall: wall,
                appearance: appearance,
                photo: photo,
                segments: segments,
                surfaces: surfaces,
                furniture: furniture,
                showFurnitureOverlay: showFurnitureOverlay,
                points: points
            )
            .frame(height: previewHeight)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appearance.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(
                        String(
                            format: "%.2f × %.2f م • %@ • صور %d%%",
                            wall.width,
                            wall.height,
                            appearance.visualMode.title,
                            Int((segmentCoverage * 100).rounded())
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var segmentCoverage: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(segments.filter { $0.state == .captured }.count) / Double(segments.count)
    }

    private var previewHeight: CGFloat {
        let ratio = CGFloat(wall.width / max(wall.height, 0.1))
        return min(max(250 / max(ratio, 0.75), 130), 230)
    }
}

private struct WallPhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let wall: WallSnapshot
    let appearance: WallAppearance
    let photos: [WallPhotoAsset]
    let segments: [WallPhotoSegment]
    let points: [ElectricalPoint]
    let surfaces: [WallPhotoSurfaceProjection]
    let furniture: [WallPhotoFurnitureProjection]
    let showFurnitureOverlay: Bool
    let onSaveAppearance: (WallAppearance) -> Void
    let onImportPhoto: (Data, WallPhotoSource) -> UUID?
    let onSelectPhoto: (UUID) -> Void
    let onDeletePhoto: (WallPhotoAsset) -> Void
    let onOpenWall2D: () -> Void
    let onOpenWall3D: () -> Void

    @State private var displayName: String
    @State private var visualMode: WallVisualMode
    @State private var selectedColor: Color
    @State private var opacity: Double
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedPhotoID: UUID?
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(
        projectID: UUID,
        wall: WallSnapshot,
        appearance: WallAppearance,
        photos: [WallPhotoAsset],
        segments: [WallPhotoSegment],
        points: [ElectricalPoint],
        surfaces: [WallPhotoSurfaceProjection],
        furniture: [WallPhotoFurnitureProjection],
        showFurnitureOverlay: Bool,
        onSaveAppearance: @escaping (WallAppearance) -> Void,
        onImportPhoto: @escaping (Data, WallPhotoSource) -> UUID?,
        onSelectPhoto: @escaping (UUID) -> Void,
        onDeletePhoto: @escaping (WallPhotoAsset) -> Void,
        onOpenWall2D: @escaping () -> Void,
        onOpenWall3D: @escaping () -> Void
    ) {
        self.projectID = projectID
        self.wall = wall
        self.appearance = appearance
        self.photos = photos
        self.segments = segments
        self.points = points
        self.surfaces = surfaces
        self.furniture = furniture
        self.showFurnitureOverlay = showFurnitureOverlay
        self.onSaveAppearance = onSaveAppearance
        self.onImportPhoto = onImportPhoto
        self.onSelectPhoto = onSelectPhoto
        self.onDeletePhoto = onDeletePhoto
        self.onOpenWall2D = onOpenWall2D
        self.onOpenWall3D = onOpenWall3D
        _displayName = State(initialValue: appearance.displayName)
        _visualMode = State(initialValue: appearance.visualMode)
        _selectedColor = State(
            initialValue: Color(uiColor: wallPhotoUIColor(hex: appearance.solidColorHex))
        )
        _opacity = State(initialValue: Double(appearance.opacity))
        _selectedPhotoID = State(initialValue: appearance.primaryPhotoID ?? photos.first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WallElevationPreview(
                        projectID: projectID,
                        wall: wall,
                        appearance: draftAppearance,
                        photo: primaryPhoto,
                        segments: segments,
                        surfaces: surfaces,
                        furniture: furniture,
                        showFurnitureOverlay: showFurnitureOverlay,
                        points: points
                    )
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                }

                Section("بيانات الحائط") {
                    TextField("اسم الحائط", text: $displayName)
                    LabeledContent(
                        "المقاس",
                        value: String(format: "%.2f × %.2f م", wall.width, wall.height)
                    )
                    Button {
                        saveAppearance()
                        onOpenWall2D()
                    } label: {
                        Label("الذهاب إلى الحائط في 2D", systemImage: "square.grid.2x2")
                    }
                    Button {
                        saveAppearance()
                        onOpenWall3D()
                    } label: {
                        Label("الذهاب إلى الحائط في 3D", systemImage: "view.3d")
                    }
                }

                if !segments.isEmpty {
                    Section("تغطية المسح الفوتوغرافي") {
                        LabeledContent("الأجزاء", value: "\(capturedSegmentCount) / \(segments.count)")
                        ProgressView(value: segmentCoverage)
                            .tint(.green)
                        Text("كل صورة ملتقطة مرتبطة بجزء محدد، ويمكن استكمال الأجزاء الناقصة لاحقًا من وضع الكاميرا.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("مظهر الحائط") {
                    Picker("طريقة العرض", selection: $visualMode) {
                        ForEach(WallVisualMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }

                    if visualMode == .solidColor {
                        ColorPicker("لون الحائط", selection: $selectedColor, supportsOpacity: false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "شفافية المظهر",
                            value: "\(Int((opacity * 100).rounded()))%"
                        )
                        Slider(value: $opacity, in: 0.10...1, step: 0.05)
                    }
                }

                Section("صور الحائط") {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            photos.isEmpty ? "اختيار صورة للحائط" : "إضافة أو تبديل الصورة",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .disabled(isImporting)

                    if isImporting {
                        ProgressView("جاري تجهيز الصورة...")
                    }

                    if photos.isEmpty {
                        ContentUnavailableView(
                            "لا توجد صور",
                            systemImage: "photo",
                            description: Text(
                                "اختر صورة مؤقتًا لاختبار المظهر. "
                                    + "التصوير التلقائي من المسح سيضاف في المرحلة الثانية."
                            )
                        )
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(photos) { photo in
                                    WallPhotoAssetTile(
                                        projectID: projectID,
                                        photo: photo,
                                        isSelected: selectedPhotoID == photo.id,
                                        onSelect: {
                                            selectedPhotoID = photo.id
                                            onSelectPhoto(photo.id)
                                            visualMode = .capturedPhotos
                                        },
                                        onDelete: {
                                            onDeletePhoto(photo)
                                            if selectedPhotoID == photo.id {
                                                selectedPhotoID = photos.first(where: {
                                                    $0.id != photo.id
                                                })?.id
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)

                        if let primaryPhoto,
                           let fileURL = WallPhotoStorage.fileURL(
                            projectID: projectID,
                            asset: primaryPhoto
                           ) {
                            ShareLink(item: fileURL) {
                                Label(
                                    "حفظ أو إرسال صورة الحائط للتعديل",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                            Text(
                                "بعد تعديل الصورة خارج التطبيق، استخدم «إضافة أو تبديل الصورة» "
                                    + "لإرجاع النسخة المعدلة وتعيينها كصورة الحائط."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(appearance.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        saveAppearance()
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                importSelectedItem(newItem)
            }
            .alert("تعذر استيراد الصورة", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var capturedSegmentCount: Int {
        segments.filter { $0.state == .captured }.count
    }

    private var segmentCoverage: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(capturedSegmentCount) / Double(segments.count)
    }

    private var primaryPhoto: WallPhotoAsset? {
        if let primaryID = selectedPhotoID,
           let selected = photos.first(where: { $0.id == primaryID }) {
            return selected
        }
        return photos.first
    }

    private var draftAppearance: WallAppearance {
        var updated = appearance
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.visualMode = visualMode
        updated.solidColorHex = selectedColor.wallPhotoHexValue
        updated.opacity = Float(opacity)
        updated.primaryPhotoID = selectedPhotoID
        return updated
    }

    private func saveAppearance() {
        var updated = draftAppearance
        if updated.displayName.isEmpty {
            updated.displayName = appearance.displayName
        }
        if updated.visualMode == .capturedPhotos,
           selectedPhotoID == nil {
            updated.visualMode = .defaultMaterial
        }
        onSaveAppearance(updated)
    }

    private func importSelectedItem(_ item: PhotosPickerItem) {
        isImporting = true
        Task { @MainActor in
            defer {
                isImporting = false
                pickerItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WallPhotoStorageError.invalidImage
                }
                let source: WallPhotoSource = photos.isEmpty
                    ? .manualImport
                    : .editedReplacement
                if let importedPhotoID = onImportPhoto(data, source) {
                    selectedPhotoID = importedPhotoID
                    visualMode = .capturedPhotos
                } else {
                    errorMessage = "تعذر حفظ الصورة داخل المشروع."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WallPhotoAssetTile: View {
    let projectID: UUID
    let photo: WallPhotoAsset
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Button(action: onSelect) {
                Group {
                    if let image = WallPhotoStorage.image(
                        projectID: projectID,
                        asset: photo,
                        thumbnail: true
                    ) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, height: 82)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                if isSelected {
                    Label("الحالية", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Text("اختيار")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct WallElevationPreview: View {
    let projectID: UUID
    let wall: WallSnapshot
    let appearance: WallAppearance
    let photo: WallPhotoAsset?
    let segments: [WallPhotoSegment]
    let surfaces: [WallPhotoSurfaceProjection]
    let furniture: [WallPhotoFurnitureProjection]
    let showFurnitureOverlay: Bool
    let points: [ElectricalPoint]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                appearanceBackground
                    .frame(width: size.width, height: size.height)
                    .clipped()

                gridOverlay
                segmentCoverageOverlay

                if showFurnitureOverlay {
                    ForEach(furniture) { item in
                        furnitureView(item, size: size)
                    }
                }

                ForEach(Array(surfaces.enumerated()), id: \.offset) { _, surface in
                    openingView(surface, size: size)
                }

                ForEach(points) { point in
                    electricalPointView(point, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.28), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var appearanceBackground: some View {
        switch appearance.visualMode {
        case .capturedPhotos:
            if let photo,
               let image = WallPhotoStorage.image(
                projectID: projectID,
                asset: photo,
                thumbnail: true
               ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(Double(appearance.opacity))
            } else {
                defaultBackground
            }
        case .solidColor:
            Color(uiColor: wallPhotoUIColor(hex: appearance.solidColorHex))
                .opacity(Double(appearance.opacity))
        case .defaultMaterial:
            defaultBackground
        }
    }

    private var defaultBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .secondarySystemBackground),
                Color(uiColor: .tertiarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var gridOverlay: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [0.25, 0.50, 0.75] {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for fraction in [0.33, 0.66] {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(
                path,
                with: .color(.white.opacity(0.16)),
                lineWidth: 0.7
            )
        }
        .allowsHitTesting(false)
    }

    private var segmentCoverageOverlay: some View {
        Canvas { context, size in
            for segment in segments {
                let rect = previewRect(
                    centerX: segment.centerX,
                    centerY: segment.centerY,
                    width: segment.width,
                    height: segment.height,
                    size: size
                ).insetBy(dx: 1.5, dy: 1.5)
                let color: Color
                switch segment.state {
                case .captured: color = .green
                case .skipped: color = .gray
                case .pending: color = .blue
                }
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(color.opacity(0.10))
                )
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(color.opacity(0.65)),
                    lineWidth: 0.8
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func furnitureView(
        _ item: WallPhotoFurnitureProjection,
        size: CGSize
    ) -> some View {
        let rect = previewRect(
            centerX: item.centerX,
            centerY: item.centerY,
            width: item.width,
            height: item.height,
            size: size
        )
        return RoundedRectangle(cornerRadius: 5)
            .fill(Color.brown.opacity(0.16))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.brown.opacity(0.78), lineWidth: 1.5)
            }
            .overlay {
                Text(item.title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func openingView(
        _ surface: WallPhotoSurfaceProjection,
        size: CGSize
    ) -> some View {
        let rect = previewRect(
            centerX: surface.centerX,
            centerY: surface.centerY,
            width: surface.width,
            height: surface.height,
            size: size
        )
        let color: Color = surface.kind == .door ? .orange : .cyan
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.30))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 2)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func electricalPointView(
        _ point: ElectricalPoint,
        size: CGSize
    ) -> some View {
        let x = CGFloat((point.localX + wall.width / 2) / max(wall.width, 0.01))
            * size.width
        let height = point.heightFromFloor
        let y = size.height - CGFloat(height / max(wall.height, 0.01)) * size.height
        let fallback: UIColor = point.status == .existing ? .systemGreen : .systemOrange
        let color = Color(uiColor: wallPhotoUIColor(hex: point.colorHex, fallback: fallback))
        return Image(systemName: point.type.systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .overlay {
                Circle().stroke(.white, lineWidth: 1.5)
            }
            .shadow(radius: 2)
            .position(
                x: min(max(x, 12), max(size.width - 12, 12)),
                y: min(max(y, 12), max(size.height - 12, 12))
            )
    }

    private func previewRect(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
        size: CGSize
    ) -> CGRect {
        let left = CGFloat((centerX - width / 2 + wall.width / 2) / max(wall.width, 0.01))
            * size.width
        let right = CGFloat((centerX + width / 2 + wall.width / 2) / max(wall.width, 0.01))
            * size.width
        let bottom = CGFloat((centerY - height / 2 + wall.height / 2) / max(wall.height, 0.01))
            * size.height
        let top = CGFloat((centerY + height / 2 + wall.height / 2) / max(wall.height, 0.01))
            * size.height
        return CGRect(
            x: left,
            y: size.height - top,
            width: max(right - left, 2),
            height: max(top - bottom, 2)
        )
    }
}

struct WallPhotoSurfaceProjection: Equatable {
    let kind: SurfaceSnapshot.Kind
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

struct WallPhotoFurnitureProjection: Identifiable, Equatable {
    let id: UUID
    let title: String
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

func wallPhotoUIColor(
    hex: String?,
    fallback: UIColor = .systemGray4
) -> UIColor {
    guard let hex else { return fallback }
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6,
          let value = UInt64(cleaned, radix: 16) else {
        return fallback
    }
    return UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

private extension Color {
    var wallPhotoHexValue: String {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#D9D9DE"
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
