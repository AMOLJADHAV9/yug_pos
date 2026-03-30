import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class ReportService {
  static Future<pw.ImageProvider> _loadLogo() async {
    final logoData = await rootBundle.load('lib/assets/img/yug_pos_logo.png');
    return pw.MemoryImage(logoData.buffer.asUint8List());
  }

  static DateTime _getDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static double _getDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  // ── Standard thermal widths in PDF points (72 points per inch) ───────────
  static const double _width58mm = 155.91; // approx 155.91 pts
  static const double _width75mm = 212.77; // approx 212.77 pts

  // Standard thermal page format: defaults to 58mm but builds dynamically
  static PdfPageFormat _getThermalFormat(double width) => PdfPageFormat(
        width,
        100 * PdfPageFormat.cm, // 1 meter max height per page
        marginAll: 6,
      );

  // Dynamic content wrapper: Centering 58mm design on wider paper
  static pw.Widget _receiptWrapper(double pageWidth, List<pw.Widget> children) {
    if (pageWidth > 200) { // If printing on 80mm (226pt)
      final sidePadding = (pageWidth - _width58mm) / 2 - 6; // substracting margin
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: sidePadding > 0 ? sidePadding : 0),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  // Light dashed separator
  static pw.Widget _dash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '- ' * 48,
          style: pw.TextStyle(fontSize: 6, letterSpacing: 0),
          textAlign: pw.TextAlign.center,
        ),
      );

  // Heavy "=" separator
  static pw.Widget _thickDash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '= ' * 28
          ,
          style: pw.TextStyle(fontSize: 7, letterSpacing: 0),
          textAlign: pw.TextAlign.center,
        ),
      );

  // Helper to format order type display
  static String _formatOrderTypeDisplay(Map<String, dynamic> data, {bool includeTablePrefix = false, bool isFinalBill = false}) {
    final type = (data['orderType']?.toString() ?? '').toLowerCase();
    if (type == 'takeaway') return isFinalBill ? 'Type: TAKEAWAY' : 'TAKEAWAY';
    if (type == 'delivery') return isFinalBill ? 'Type: DELIVERY' : 'DELIVERY';
    if (isFinalBill) return 'Table: ${data['tableName']}';
    return includeTablePrefix ? 'TABLE: ${data['tableName']}' : data['tableName'].toString().toUpperCase();
  }

  // ── DAILY COLLECTION REPORT (A4) ─────────────────────────────────────────
  static Future<void> generateDailyCollectionReport(
      DateTime date, List<QueryDocumentSnapshot> orders, {String restaurantName = "YUG POS"}) async {
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    await generatePeriodReport("Daily Collection Report", "Date: $dateStr", orders, restaurantName: restaurantName);
  }

  // ── GENERAL PERIOD REPORT (A4) ───────────────────────────────────────────
  static Future<void> generatePeriodReport(
      String title, String periodInfo, List<QueryDocumentSnapshot> orders, {String restaurantName = "YUG POS"}) async {
    final pdf = pw.Document();
    final total =
        orders.fold<double>(0, (sum, doc) => sum + (doc['totalAmount'] ?? 0));

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    
    final theme = pw.ThemeData.withFont(
      base: roboto,
      bold: robotoBold,
      italic: robotoItalic,
    );

    final logo = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        header: (pw.Context context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(restaurantName.toUpperCase(),
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 22,
                            color: PdfColors.black)),
                    pw.Text(title,
                        style: const pw.TextStyle(
                            fontSize: 16, color: PdfColors.grey700)),
                  ],
                ),
                pw.Image(logo, width: 60, height: 60),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (pw.Context context) => pw.Column(
          children: [
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Generated by YUG POS",
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.Text("Page ${context.pageNumber} of ${context.pagesCount}",
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(periodInfo, style: const pw.TextStyle(fontSize: 12)),
                    pw.Text("Total Orders: ${orders.length}", 
                        style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("TOTAL NET REVENUE", 
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text("INR ${total.toStringAsFixed(2)}",
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 20)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.center,
              },
              data: <List<String>>[
                <String>['Order ID', 'Date', 'Table', 'Waiter', 'Amount', 'Status'],
                ...orders.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  return [
                    doc.id.substring(0, 8).toUpperCase(),
                    DateFormat('dd-MM-yy HH:mm').format(createdAt),
                    data['orderType'] == 'takeaway' ? 'TAKEAWAY' : data['tableName'].toString(),
                    data['waiterName'].toString(),
                    "INR ${((data['totalAmount'] ?? 0) as num).toStringAsFixed(2)}",
                    data['status'].toString().toUpperCase(),
                  ];
                })
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '${title.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  // ── KOT RECEIPT ─────────────────────────────────────────────────────────
  static Future<void> printKOTReceipt(
      Map<String, dynamic> data, String orderId) async {
    final pdf = pw.Document();
    final items = data['items'] as List;

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(
      base: roboto,
      bold: robotoBold,
      italic: robotoItalic,
    );

    final logo = await _loadLogo();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              pw.Center(child: pw.Image(logo, width: 45, height: 45)),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text("KOT", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              ),
              _thickDash(),
              pw.Center(
                child: pw.Text(_formatOrderTypeDisplay(data),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
              ),
              _thickDash(),
              ...items.map((item) {
                final quantity = (item['quantity'] ?? 0).toInt();
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text("${quantity}x  ${item['name']}",
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                );
              }),
              _dash(),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("Thank you from POS Solutions", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 9))),
              pw.SizedBox(height: 10),
            ]),
          ),
        );
        return pdf.save();
      },
    );
  }

  // ── ORDER RECEIPT (waiter copy) ──────────────────────────────────────────
  static Future<void> printOrderReceipt(
      Map<String, dynamic> data, String orderId, {String restaurantName = "YUG POS"}) async {
    final pdf = pw.Document();
    final items = data['items'] as List;
    final date = _getDateTime(data['createdAt']);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final logo = await _loadLogo();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              pw.Center(child: pw.Image(logo, width: 45, height: 45)),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Center(child: pw.Text("ORDER SLIP", style: const pw.TextStyle(fontSize: 8))),
              _thickDash(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Order: ${orderId.substring(0, 8)}", style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(DateFormat('dd/MM/yy hh:mm a').format(date), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Text(_formatOrderTypeDisplay(data, includeTablePrefix: true), 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text("Waiter: ${data['waiterName']}", style: const pw.TextStyle(fontSize: 8)),
              _dash(),
              pw.Row(children: [
                pw.Expanded(child: pw.Text("Item", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                pw.SizedBox(width: 30, child: pw.Text("Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
                pw.SizedBox(width: 40, child: pw.Text("Amt", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
              ]),
              _dash(),
              ...items.map((item) {
                final qty = item['quantity'] ?? 1;
                final price = item['price'] ?? 0;
                return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text("${item['name']}", style: const pw.TextStyle(fontSize: 8))),
                        pw.SizedBox(width: 30, child: pw.Text("$qty", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                        pw.SizedBox(width: 40, child: pw.Text("₹${(price * qty).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  );
              }).toList(),
              _dash(),
              _amountRow("Total Amount", "₹${_getDouble(data['totalAmount']).toStringAsFixed(2)}"),
              _thickDash(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                   pw.Text("TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                   pw.Text("₹${_getDouble(data['totalAmount']).toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                ],
              ),
              _thickDash(),
              pw.SizedBox(height: 10),
            ]),
          ),
        );
        return pdf.save();
      },
    );
  }

  // ── FINAL BILL ───────────────────────────────────────────────────────────
  static Future<void> printFinalBill({
    required Map<String, dynamic> orderData,
    required String orderId,
    required double subtotal,
    required double cgst,
    required double sgst,
    required double total,
    required String paymentMode,
    String hotelName = "YUG POS",
    String address = "Market Road, City",
  }) async {
    final pdf = pw.Document();
    final items = orderData['items'] as List;
    final date = DateTime.now();
    final dateStr = DateFormat('dd-MM-yyyy  hh:mm a').format(date);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final receiptNum = orderData['receiptNumber'] ?? orderId.substring(0, 6);
    final logo = await _loadLogo();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              // ── Header ─────────────────────────────────────────
              pw.Center(child: pw.Image(logo, width: 45, height: 45)),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(hotelName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Center(child: pw.Text(address, style: const pw.TextStyle(fontSize: 7))),
              _thickDash(),
              pw.Center(child: pw.Text("INVOICE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              _dash(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Bill #: $receiptNum", style: const pw.TextStyle(fontSize: 8)),
                pw.Text(_formatOrderTypeDisplay(orderData, isFinalBill: true), 
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 7)),
                pw.Text("Token: ${orderData['kotNumber'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
              ]),
              if (orderData['orderType'] == 'takeaway' && orderData['deliveryAddress'] != null)
                pw.Text("Address: ${orderData['deliveryAddress']}", style: const pw.TextStyle(fontSize: 7)),
              pw.Text("Cashier: ${orderData['cashierName'] ?? 'Counter'}", style: const pw.TextStyle(fontSize: 7)),
              pw.Text("Waiter: ${orderData['waiterName'] ?? 'Waiter'}", style: const pw.TextStyle(fontSize: 7)),
              _dash(),

              // ── Column headers ──────────────────────────────────
              pw.Row(children: [
                pw.Expanded(child: pw.Text("Item", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                pw.SizedBox(width: 20, child: pw.Text("Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
                pw.SizedBox(width: 35, child: pw.Text("Rate", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 40, child: pw.Text("Amt", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
              ]),
              _dash(),

              // ── Items ───────────────────────────────────────────                  
              ...items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Row(children: [
                      pw.Expanded(child: pw.Text(item['name'].toString().toUpperCase(), style: const pw.TextStyle(fontSize: 8))),
                      pw.SizedBox(width: 20, child: pw.Text("${item['quantity']}", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.SizedBox(width: 35, child: pw.Text("${item['price']}", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                      pw.SizedBox(width: 40, child: pw.Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                    ]),
                  )),
              _dash(),

              // ── Totals ──────────────────────────────────────────
              _amountRow("Total Amount", "₹${subtotal.toStringAsFixed(2)}"),
              _thickDash(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("GRAND TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text("₹${total.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              ]),
              _thickDash(),

              // ── Footer ──────────────────────────────────────────
              pw.Center(
                child: pw.Text("PAYMENT: ${paymentMode.toUpperCase()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ),
              pw.Center(
                child: pw.Text("STATUS: ${orderData['status'] == 'completed' ? 'PAID' : 'DRAFT / UNPAID'}", style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
              ),
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text("Thank you! Visit Again", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8))),
              pw.SizedBox(height: 5),
              pw.Center(child: pw.Text("YUG POS", style: const pw.TextStyle(fontSize: 6))),
              pw.SizedBox(height: 15),
            ]),
          ),
        );
        return pdf.save();
      },
    );
  }

  // ── Helper: amount row ───────────────────────────────────────────────────
  static pw.Widget _amountRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
          ],
        ),
      );

  // ── REVENUE SUMMARY REPORT ──────────────────────────────────────────────
  static Future<void> printSummaryReport({
    required String restaurantName,
    required double netRevenue,
    required int billCount,
    required Map<String, double> revenueBySource,
    required Map<String, int> orderStatuses,
    required Map<String, double> categories,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text("DAILY REVENUE SUMMARY", style: const pw.TextStyle(fontSize: 16))),
              pw.Center(child: pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 12))),
              pw.SizedBox(height: 30),

              pw.Text("OVERALL PERFORMANCE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Total Net Revenue:"),
                pw.Text("INR ${netRevenue.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Total Bills Generated:"),
                pw.Text("$billCount", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 20),

              pw.Text("REVENUE BY SOURCE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Divider(),
              ...revenueBySource.entries.map((e) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text(e.key),
                    pw.Text("INR ${e.value.toStringAsFixed(2)}"),
                  ])),
              pw.SizedBox(height: 20),

              pw.Text("ORDER STATUS SUMMARY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Divider(),
              ...orderStatuses.entries.map((e) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text(e.key),
                    pw.Text("${e.value}"),
                  ])),
              pw.SizedBox(height: 20),

              if (categories.isNotEmpty) ...[
                pw.Text("REVENUE BY CATEGORY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Divider(),
                ...categories.entries.map((e) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text(e.key),
                      pw.Text("INR ${e.value.toStringAsFixed(2)}"),
                    ])),
              ],

              pw.Spacer(),
              pw.Divider(),
              pw.Center(child: pw.Text("Generated by YUG POS Solution", style: const pw.TextStyle(fontSize: 10))),
            ],
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Revenue_Summary_$dateStr.pdf');
  }

  // ── ORDER HISTORY REPORT ──────────────────────────────────────────────
  static Future<void> printOrderHistoryReport({
    required String restaurantName,
    required List<Map<String, dynamic>> orders,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    final startStr = DateFormat('dd-MM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MM-yyyy').format(endDate);
    
    // Split orders into chunks for multiple pages (approx 25 per page)
    const int itemsPerPage = 28;
    for (var i = 0; i < orders.length; i += itemsPerPage) {
      final chunk = orders.sublist(i, i + itemsPerPage > orders.length ? orders.length : i + itemsPerPage);
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => pw.Padding(
            padding: const pw.EdgeInsets.all(30),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (i == 0) ...[
                  pw.Center(child: pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
                  pw.Center(child: pw.Text("ORDER HISTORY REPORT", style: const pw.TextStyle(fontSize: 14))),
                  pw.Center(child: pw.Text("Period: $startStr to $endStr", style: const pw.TextStyle(fontSize: 10))),
                  pw.SizedBox(height: 20),
                ],
                
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        _tableHeader("Date"),
                        _tableHeader("Bill #"),
                        _tableHeader("Type"),
                        _tableHeader("Status"),
                        _tableHeader("Amount", align: pw.TextAlign.right),
                      ],
                    ),
                    ...chunk.map((order) {
                      final dt = _getDateTime(order['createdAt']);
                      return pw.TableRow(
                        children: [
                          _tableCell(DateFormat('dd/MM HH:mm').format(dt)),
                          _tableCell(order['receiptNumber']?.toString() ?? 'N/A'),
                          _tableCell(order['orderType']?.toString().toUpperCase() ?? 'N/A'),
                          _tableCell(order['status']?.toString().toUpperCase() ?? 'N/A'),
                          _tableCell("INR ${order['totalAmount'] ?? '0'}", align: pw.TextAlign.right),
                        ],
                      );
                    }),
                  ],
                ),
                
                if (i + itemsPerPage >= orders.length) ...[
                  pw.SizedBox(height: 20),
                  pw.Divider(),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Total Orders: ${orders.length}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text("Total Revenue: INR ${orders.fold(0.0, (sum, o) => sum + (o['totalAmount'] ?? 0))}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ]),
                ],
                
                pw.Spacer(),
                pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Page ${(i/itemsPerPage).toInt() + 1}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))),
              ],
            ),
          ),
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Order_History_Report.pdf');
  }

  static pw.Widget _tableHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: align),
  );

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 8), textAlign: align),
  );
}
