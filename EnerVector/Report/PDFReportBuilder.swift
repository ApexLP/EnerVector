import UIKit

struct ReportOptions {
    var title = ""
    var preparedFor = ""
    var summary = ""
    var includeFlags = true
    var includeEquipment = true
    var includeSchedules = true
    var includeRoomScans = true
    var includeRuns = true
    var includeRoof = true
    var includeLoad = true
    var includePhotos = true
}

struct ReportAuthor {
    var technician: String
    var company: String
    var kwPerTon: Double
    var wattsPerSqFt: Double
}

/// Builds a US Letter PDF report for a site with UIGraphicsPDFRenderer.
enum PDFReportBuilder {
    static func build(site: Site, options: ReportOptions, author: ReportAuthor) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: options.title,
            kCGPDFContextAuthor as String: author.company.isEmpty ? author.technician : author.company,
            kCGPDFContextCreator as String: "EnerVector",
        ]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { ctx in
            let doc = Layout(ctx: ctx, page: page, footer: "\(site.name) · \(options.title)")
            doc.newPage()
            cover(doc, site: site, options: options, author: author)

            let equipment = site.equipment.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
            let flags = site.flags.sorted { ($0.resolved ? 1 : 0, $1.createdAt) < ($1.resolved ? 1 : 0, $0.createdAt) }

            if options.includeFlags && !flags.isEmpty {
                doc.section("Compliance Flags")
                doc.table(headers: ["Severity", "Finding", "Equipment", "Reference", "Status"],
                          widths: [0.12, 0.40, 0.14, 0.20, 0.14],
                          rows: flags.map { [$0.severity.rawValue, $0.title, $0.equipmentTag, $0.reference, $0.resolved ? "Resolved" : "Open"] },
                          highlight: { row in flags[row].resolved ? nil : flags[row].severity == .critical ? UIColor.systemRed.withAlphaComponent(0.08) : nil })
            }

            if options.includeEquipment && !equipment.isEmpty {
                let hvac = equipment.filter { $0.kind.isHVAC }
                let electrical = equipment.filter { !$0.kind.isHVAC }
                if !electrical.isEmpty {
                    doc.section("Electrical Equipment")
                    doc.table(headers: ["Tag", "Type", "Manufacturer", "Model", "Serial", "Rating", "Arc Flash"],
                              widths: [0.10, 0.16, 0.13, 0.15, 0.14, 0.20, 0.12],
                              rows: electrical.map { e in
                                  [e.tag, e.kind.rawValue, e.manufacturer, e.model, e.serial,
                                   [e.amperage, e.voltage, e.kva, e.phase.isEmpty ? "" : "\(e.phase)Ø"].filter { !$0.isEmpty }.joined(separator: " "),
                                   e.hasArcFlashLabel == true ? "Present" : e.hasArcFlashLabel == false ? "MISSING" : "—"]
                              },
                              highlight: { row in electrical[row].hasArcFlashLabel == false && electrical[row].kind.expectsArcFlashLabel ? UIColor.systemRed.withAlphaComponent(0.08) : nil })
                }
                if !hvac.isEmpty {
                    doc.section("HVAC Nameplates")
                    doc.table(headers: ["Unit", "Type", "Manufacturer", "Model", "Tonnage", "Refrigerant", "Age", "Electrical"],
                              widths: [0.09, 0.13, 0.13, 0.14, 0.11, 0.12, 0.10, 0.18],
                              rows: hvac.map { e in
                                  [e.tag, e.kind.rawValue, e.manufacturer, e.model, e.tonnage, e.refrigerant,
                                   e.age.map { "\($0) yrs" } ?? "—", [e.voltage, e.phase.isEmpty ? "" : "\(e.phase)Ø", e.amperage].filter { !$0.isEmpty }.joined(separator: " ")]
                              })
                    let old = hvac.filter { ($0.age ?? 0) >= 15 }
                    if !old.isEmpty {
                        doc.note("\(old.count) unit(s) are 15+ years old (\(old.map(\.tag).joined(separator: ", "))) — typical candidates for replacement with high-efficiency equipment.")
                    }
                }
            }

            if options.includeSchedules {
                for e in equipment where !e.circuits.isEmpty {
                    doc.section("Panel Schedule — \(e.displayName)")
                    doc.keyValues([("Panel", e.displayName), ("Rating", e.ratingSummary), ("Location", e.location), ("Circuits", "\(e.circuits.count)")])
                    doc.table(headers: ["Circuit", "Description", "Breaker"], widths: [0.14, 0.64, 0.22],
                              rows: e.circuits.map { c in
                                  ["\(c.number)", c.description, c.breakerAmps.map { "\($0)A" + (c.poles.map { " / \($0)P" } ?? "") } ?? "—"]
                              })
                }
            }

            if options.includeRoomScans && !site.roomScans.isEmpty {
                for scan in site.roomScans.sorted(by: { $0.name < $1.name }) {
                    doc.section("As-Built — \(scan.name)")
                    let e = scan.geometry.extents
                    doc.keyValues([("Floor area", "\(Units.number(scan.floorAreaSqFt)) sq ft"),
                                   ("Ceiling height", "\(Units.number(scan.ceilingHeightFt, digits: 1)) ft"),
                                   ("Extents", "\(Units.feetInches(e.width)) × \(Units.feetInches(e.depth))"),
                                   ("Method", scan.fromLiDAR ? "LiDAR room scan" : "Manual measurement"),
                                   ("Level", scan.level), ("Captured", scan.capturedAt.formatted(date: .abbreviated, time: .shortened))])
                    doc.drawing(height: 300) { cg, rect in PlanRenderer.draw(scan.geometry, in: cg, rect: rect) }
                    if !scan.notes.isEmpty { doc.note(scan.notes) }
                }
            }

            if options.includeRuns && !site.segments.isEmpty {
                doc.section("Conduit & Cable Tray Progress")
                let pct = site.plannedFeet > 0 ? site.installedFeet / site.plannedFeet : 0
                doc.keyValues([("Overall", Units.percent(pct)), ("Installed", "\(Units.number(site.installedFeet)) ft"),
                               ("Planned", "\(Units.number(site.plannedFeet)) ft"),
                               ("Remaining", "\(Units.number(max(0, site.plannedFeet - site.installedFeet))) ft")])
                let segs = site.segments.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                doc.table(headers: ["Segment", "Type", "Area", "Planned", "Installed", "Variance", "Status"],
                          widths: [0.15, 0.13, 0.18, 0.12, 0.12, 0.12, 0.18],
                          rows: segs.map { s in
                              [s.name, s.type.rawValue, s.area, "\(Units.number(s.plannedFt)) ft", "\(Units.number(s.installedFt)) ft",
                               "\(Units.number(min(0, s.variance))) ft", s.statusLabel]
                          },
                          highlight: { row in segs[row].statusLabel == "Behind" ? UIColor.systemRed.withAlphaComponent(0.07) : nil })
                doc.progressBars(segs.map { ($0.name, $0.progress) })
            }

            if options.includeRoof && !site.roofSurveys.isEmpty {
                for roof in site.roofSurveys {
                    doc.section("Roof & Solar — \(roof.name)")
                    if roof.plan.outline.count > 2 {
                        doc.drawing(height: 240) { cg, rect in PlanRenderer.drawRoof(roof.plan, in: cg, rect: rect) }
                    }
                    doc.keyValues([("Total roof area", "\(Units.number(roof.totalAreaSqFt)) sq ft"),
                                   ("Obstructions", "\(Units.number(roof.obstructionAreaSqFt)) sq ft"),
                                   ("Setback / spacing", "\(Units.number(roof.setbackPercent))%"),
                                   ("Usable roof area", "\(Units.number(roof.usableAreaSqFt)) sq ft"),
                                   ("Modules (est.)", "\(roof.moduleCount) × \(Units.number(roof.moduleWatts)) W"),
                                   ("System capacity (est.)", "\(Units.number(roof.capacityKW, digits: 1)) kW"),
                                   ("Annual production (est.)", "\(Units.number(roof.annualKWh)) kWh"),
                                   ("Specific yield", "\(Units.number(roof.specificYield)) kWh/kWp")])
                    if !roof.notes.isEmpty { doc.note(roof.notes) }
                }
            }

            if options.includeLoad && (site.discipline == .energyAudit || equipment.contains { $0.kind.isHVAC }) {
                let est = LoadEstimate(site: site, kwPerTon: author.kwPerTon, wattsPerSqFt: author.wattsPerSqFt)
                doc.section("Load Estimate")
                doc.keyValues([("Building area", site.buildingSqFt > 0 ? "\(Units.number(site.buildingSqFt)) sq ft" : "—"),
                               ("HVAC cooling", "\(Units.number(est.tons, digits: 1)) tons"),
                               ("HVAC load", "\(Units.number(est.hvacKW)) kW @ \(Units.number(author.kwPerTon, digits: 1)) kW/ton"),
                               ("Lighting & plug", "\(Units.number(est.densityKW)) kW @ \(Units.number(author.wattsPerSqFt, digits: 1)) W/sq ft"),
                               ("Connected load (est.)", "\(Units.number(est.totalKW)) kW")])
            }

            if options.includePhotos {
                let photos: [(String, UIImage)] = equipment.flatMap { e -> [(String, UIImage)] in
                    var out: [(String, UIImage)] = []
                    if let d = e.photo, let img = UIImage(data: d) { out.append(("\(e.displayName) — nameplate", img)) }
                    if let d = e.labelPhoto, let img = UIImage(data: d) { out.append(("\(e.displayName) — arc flash label", img)) }
                    return out
                }
                if !photos.isEmpty {
                    doc.section("Photo Log")
                    doc.photoGrid(photos)
                }
            }

            doc.section("Disclaimer")
            doc.note("Values in this report were captured with on-device computer vision (text recognition, LiDAR and AR measurement) and reviewed by the technician. Measurements are approximate and must be field-verified before use for design, procurement, permitting or code-compliance decisions. Solar and load figures are planning estimates, not engineered designs. This report is not an arc flash risk assessment.")
        }
    }

    private static func cover(_ doc: Layout, site: Site, options: ReportOptions, author: ReportAuthor) {
        let accent = UIColor(red: 0.12, green: 0.43, blue: 0.92, alpha: 1)
        doc.text("ENERVECTOR REPORT", font: .systemFont(ofSize: 10, weight: .bold), color: accent, spacing: 4)
        doc.text(options.title, font: .systemFont(ofSize: 24, weight: .bold), spacing: 4)
        doc.text([site.name, site.address].filter { !$0.isEmpty }.joined(separator: " · "), font: .systemFont(ofSize: 13), color: .darkGray, spacing: 14)
        doc.keyValues([("Discipline", site.discipline.rawValue),
                       ("Prepared for", options.preparedFor.isEmpty ? site.client : options.preparedFor),
                       ("Prepared by", [author.technician, author.company].filter { !$0.isEmpty }.joined(separator: ", ")),
                       ("Date", Date.now.formatted(date: .long, time: .omitted))])
        doc.statRow([
            ("\(site.equipment.count)", "Equipment captured"),
            ("\(site.openFlags.count)", "Open flags"),
            ("\(site.roomScans.count)", "Room scans"),
            (Units.percent(site.progress), "Complete"),
        ])
        if !options.summary.isEmpty {
            doc.section("Summary")
            doc.text(options.summary, font: .systemFont(ofSize: 10.5), spacing: 8)
        }
    }

    // MARK: - Layout engine

    final class Layout {
        let ctx: UIGraphicsPDFRendererContext
        let page: CGRect
        let footer: String
        let margin: CGFloat = 44
        var y: CGFloat = 0
        var pageNumber = 0
        var width: CGFloat { page.width - margin * 2 }
        var bottom: CGFloat { page.height - margin - 16 }

        init(ctx: UIGraphicsPDFRendererContext, page: CGRect, footer: String) {
            self.ctx = ctx
            self.page = page
            self.footer = footer
        }

        func newPage() {
            ctx.beginPage()
            pageNumber += 1
            y = margin
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
            (footer as NSString).draw(at: CGPoint(x: margin, y: page.height - margin + 6), withAttributes: attrs)
            let num = "Page \(pageNumber)" as NSString
            let size = num.size(withAttributes: attrs)
            num.draw(at: CGPoint(x: page.width - margin - size.width, y: page.height - margin + 6), withAttributes: attrs)
            UIColor(white: 0.85, alpha: 1).setFill()
            UIRectFill(CGRect(x: margin, y: page.height - margin, width: width, height: 0.5))
        }

        func ensure(_ height: CGFloat) {
            if y + height > bottom { newPage() }
        }

        func text(_ s: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 6) {
            let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
            let h = ceil(attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            ensure(h)
            attr.draw(with: CGRect(x: margin, y: y, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += h + spacing
        }

        func section(_ title: String) {
            ensure(60)
            y += 10
            text(title, font: .systemFont(ofSize: 14, weight: .semibold), spacing: 4)
            UIColor(red: 0.12, green: 0.43, blue: 0.92, alpha: 1).setFill()
            UIRectFill(CGRect(x: margin, y: y, width: 36, height: 2))
            y += 10
        }

        func note(_ s: String) {
            text(s, font: .italicSystemFont(ofSize: 9), color: .darkGray, spacing: 8)
        }

        func keyValues(_ pairs: [(String, String)]) {
            let items = pairs.filter { !$0.1.isEmpty }
            let colW = width / 2, rowH: CGFloat = 16
            for i in stride(from: 0, to: items.count, by: 2) {
                ensure(rowH)
                for j in 0..<2 where i + j < items.count {
                    let x = margin + CGFloat(j) * colW
                    let (k, v) = items[i + j]
                    cell(k, CGRect(x: x, y: y, width: colW * 0.42, height: rowH), font: .systemFont(ofSize: 9), color: .gray)
                    cell(v, CGRect(x: x + colW * 0.42, y: y, width: colW * 0.56, height: rowH), font: .systemFont(ofSize: 9.5, weight: .medium))
                }
                y += rowH
            }
            y += 8
        }

        func statRow(_ stats: [(String, String)]) {
            let h: CGFloat = 54
            ensure(h + 10)
            let w = (width - CGFloat(stats.count - 1) * 8) / CGFloat(stats.count)
            for (i, s) in stats.enumerated() {
                let r = CGRect(x: margin + CGFloat(i) * (w + 8), y: y, width: w, height: h)
                let path = UIBezierPath(roundedRect: r, cornerRadius: 6)
                UIColor(white: 0.96, alpha: 1).setFill()
                path.fill()
                cell(s.0, CGRect(x: r.minX + 10, y: r.minY + 8, width: w - 20, height: 22), font: .systemFont(ofSize: 18, weight: .bold))
                cell(s.1, CGRect(x: r.minX + 10, y: r.minY + 32, width: w - 20, height: 14), font: .systemFont(ofSize: 8.5), color: .gray)
            }
            y += h + 12
        }

        func table(headers: [String], widths: [CGFloat], rows: [[String]], highlight: ((Int) -> UIColor?)? = nil) {
            let rowH: CGFloat = 17
            let cols = widths.map { $0 * width }
            func header() {
                UIColor(white: 0.93, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y, width: width, height: rowH))
                var x = margin
                for (i, h) in headers.enumerated() {
                    cell(h, CGRect(x: x + 4, y: y + 3, width: cols[i] - 8, height: rowH), font: .systemFont(ofSize: 8.5, weight: .semibold), color: .darkGray)
                    x += cols[i]
                }
                y += rowH
            }
            ensure(rowH * 2)
            header()
            for (r, row) in rows.enumerated() {
                if y + rowH > bottom { newPage(); header() }
                if let color = highlight?(r) {
                    color.setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: width, height: rowH))
                }
                var x = margin
                for (i, value) in row.enumerated() where i < cols.count {
                    let isAlert = value == "MISSING" || value == "Behind" || value == "Critical"
                    cell(value.isEmpty ? "—" : value, CGRect(x: x + 4, y: y + 3, width: cols[i] - 8, height: rowH),
                         font: .systemFont(ofSize: 8.5, weight: isAlert ? .semibold : .regular), color: isAlert ? .systemRed : .black)
                    x += cols[i]
                }
                UIColor(white: 0.9, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y + rowH - 0.5, width: width, height: 0.5))
                y += rowH
            }
            y += 10
        }

        func progressBars(_ items: [(String, Double)]) {
            for (name, value) in items {
                ensure(16)
                cell(name, CGRect(x: margin, y: y, width: 90, height: 12), font: .systemFont(ofSize: 8.5))
                let track = CGRect(x: margin + 95, y: y + 3, width: width - 140, height: 6)
                UIColor(white: 0.9, alpha: 1).setFill()
                UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
                (value >= 1 ? UIColor.systemGreen : value < 0.5 ? UIColor.systemRed : UIColor.systemBlue).setFill()
                UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * min(value, 1), height: 6), cornerRadius: 3).fill()
                cell(Units.percent(value), CGRect(x: track.maxX + 6, y: y, width: 40, height: 12), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium))
                y += 15
            }
            y += 8
        }

        func drawing(height: CGFloat, _ draw: (CGContext, CGRect) -> Void) {
            ensure(height + 8)
            let rect = CGRect(x: margin, y: y, width: width, height: height)
            draw(ctx.cgContext, rect)
            UIColor(white: 0.85, alpha: 1).setStroke()
            UIBezierPath(rect: rect).stroke()
            y += height + 10
        }

        func photoGrid(_ photos: [(String, UIImage)]) {
            let gap: CGFloat = 12, cellW = (width - gap) / 2, imgH: CGFloat = 170
            for i in stride(from: 0, to: photos.count, by: 2) {
                ensure(imgH + 22)
                for j in 0..<2 where i + j < photos.count {
                    let (caption, image) = photos[i + j]
                    let frame = CGRect(x: margin + CGFloat(j) * (cellW + gap), y: y, width: cellW, height: imgH)
                    image.draw(in: aspectFit(image.size, in: frame))
                    cell(caption, CGRect(x: frame.minX, y: frame.maxY + 3, width: cellW, height: 12), font: .systemFont(ofSize: 8.5), color: .darkGray)
                }
                y += imgH + 22
            }
        }

        private func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
            guard size.width > 0, size.height > 0 else { return rect }
            let s = min(rect.width / size.width, rect.height / size.height)
            let w = size.width * s, h = size.height * s
            return CGRect(x: rect.minX + (rect.width - w) / 2, y: rect.minY + (rect.height - h) / 2, width: w, height: h)
        }

        private func cell(_ s: String, _ rect: CGRect, font: UIFont, color: UIColor = .black) {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        }
    }
}

enum CSVExporter {
    static func equipment(_ items: [Equipment]) -> String {
        let headers = ["Site", "Tag", "Type", "Manufacturer", "Model", "Serial", "Voltage", "Amperage", "Phase", "kVA", "Tonnage",
                       "Refrigerant", "Year", "Location", "Arc Flash Label", "Status", "Captured", "Notes"]
        let rows = items.map { e in
            [e.site?.name ?? "", e.tag, e.kind.rawValue, e.manufacturer, e.model, e.serial, e.voltage, e.amperage, e.phase, e.kva,
             e.tonnage, e.refrigerant, e.manufactureYear.map(String.init) ?? "", e.location,
             e.hasArcFlashLabel == true ? "Present" : e.hasArcFlashLabel == false ? "Missing" : "",
             e.status.rawValue, e.capturedAt.formatted(.iso8601), e.notes]
        }
        return ([headers] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }
}
