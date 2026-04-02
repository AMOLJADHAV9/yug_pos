import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'usb_printer_service.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// On Windows, [Printing.layoutPdf] opens a blocking native dialog that
  /// competes with Firestore's background-thread callbacks on the platform
  /// channel, causing "non-platform thread" crashes. A short async gap allows
  /// Flutter's event loop to drain before the native dialog takes the thread.
  static Future<void> _safePrint({
    required String name,
    required Future<Uint8List> Function(PdfPageFormat) onLayout,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
       // Optional: Add small delay for Android 7 stability if needed
    }
    if (!kIsWeb && Platform.isWindows) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Printing.layoutPdf(onLayout: onLayout, name: name);
  }

  static Future<Map<String, String>> _getRestaurantDetails(Map<String, dynamic> data, String defaultName, String defaultAddress) async {
    final restaurantId = data['restaurantId'];
    if (restaurantId != null) {
      try {
        final doc = await _firestore.collection('restaurants').doc(restaurantId).get();
        if (doc.exists) {
          final resData = doc.data();
          return {
            'name': resData?['name'] ?? defaultName,
            'address': resData?['address'] ?? defaultAddress,
          };
        }
      } catch (_) {}
    }
    return {'name': defaultName, 'address': defaultAddress};
  }

  static Future<pw.ImageProvider> _loadLogo() async {
    try {
      final logoData = await rootBundle.load('lib/assets/img/yug-poslogo.png');
      return pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint("Logo loading failed: $e");
      return pw.MemoryImage(Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 8, 215, 99, 96, 0, 2, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
      ]));
    }
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

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
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
                                  color: PdfColors.black,
                              )),
                          pw.Text(title,
                              style: const pw.TextStyle(
                                  fontSize: 16, color: PdfColors.black)),
                        ],
                      ),
                      pw.Image(logo, width: 80, height: 80),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1, color: PdfColors.black),
                  pw.SizedBox(height: 10),
                ],
              ),
              footer: (pw.Context context) => pw.Column(
                children: [
                  pw.Divider(thickness: 1, color: PdfColors.black),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Generated by YUG POS",
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
                      pw.Text("Page ${context.pageNumber} of ${context.pagesCount}",
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
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
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text("TOTAL NET REVENUE", 
                                style: const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
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
                    rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))),
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
          return pdf.save();
        },
        name: '${title.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  // ── DAILY COLLECTION THERMAL REPORT ───────────────────────────────────────
  static Future<void> printDailyCollection({
    required Map<String, dynamic> data,
    required String restaurantName,
    required String dateStr,
  }) async {
    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final netCol = (data['netCollection'] as num?)?.toDouble() ?? 0.0;
    final upiCol = (data['upiCollection'] as num?)?.toDouble() ?? 0.0;
    final cashCol = (data['cashCollection'] as num?)?.toDouble() ?? 0.0;
    final dineInCol = (data['dineInCollection'] as num?)?.toDouble() ?? 0.0;
    final takeawayCol = (data['takeawayCollection'] as num?)?.toDouble() ?? 0.0;
    final onlineCol = (data['onlineCollection'] as num?)?.toDouble() ?? 0.0;
    final bCount = (data['billCount'] as num?)?.toInt() ?? 0;

    await _safePrint(
      name: 'Daily_Collection_$dateStr.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              pw.Center(child: pw.Text("DAILY COLLECTION", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13))),
              pw.Center(child: pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Center(child: pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8))),
              _thickDash(),
              
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Total Bills:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text("$bCount", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ]),
              pw.SizedBox(height: 5),
              
              pw.Text("PAYMENT BREAKDOWN", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              _dash(),
              _amountRow("Cash Collection", "₹${cashCol.toStringAsFixed(0)}"),
              _amountRow("UPI Collection", "₹${upiCol.toStringAsFixed(0)}"),
              _dash(),
              
              pw.SizedBox(height: 5),
              pw.Text("SOURCE BREAKDOWN", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              _dash(),
              _amountRow("Dine-In", "₹${dineInCol.toStringAsFixed(0)}"),
              _amountRow("Takeaway", "₹${takeawayCol.toStringAsFixed(0)}"),
              _amountRow("Online", "₹${onlineCol.toStringAsFixed(0)}"),
              _dash(),
              
              pw.SizedBox(height: 5),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                 pw.Text("NET REVENUE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                 pw.Text("₹${netCol.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ]),
              _thickDash(),
              pw.SizedBox(height: 15),
            ]),
          )
        );
        return pdf.save();
      }
    );
  }

  // ── KOT RECEIPT ─────────────────────────────────────────────────────────
  static Future<void> printKOTReceipt(
      Map<String, dynamic> data, String orderId) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(
      base: roboto,
      bold: robotoBold,
      italic: robotoItalic,
    );

    await _safePrint(
      name: 'KOT_${orderId.substring(0, 4).toUpperCase()}.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              pw.Center(
                child: pw.Text("KOT", style: pw.TextStyle(fontSize: 11)),
              ),
              _thickDash(),
              pw.Center(
                child: pw.Text(_formatOrderTypeDisplay(data),
                    style: pw.TextStyle(fontSize: 14)),
              ),
              _thickDash(),
              // ── Column headers ──────────────────────────────────
              pw.Row(children: [
                pw.Expanded(child: pw.Text("ITEM", style: pw.TextStyle(fontSize: 8))),
                pw.SizedBox(width: 30, child: pw.Text("QTY", style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                pw.SizedBox(width: 40, child: pw.Text("RATE", style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
              ]),
              _thickDash(),
              // ── Items ───────────────────────────────────────────
              ...items.map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                final itemName = (item['name']?.toString() ?? '').toUpperCase();
                final itemQty = (item['quantity'] as num?)?.toInt() ?? 1;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(children: [
                    pw.Expanded(child: pw.Text(itemName, style: const pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(width: 30, child: pw.Text("$itemQty", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                    pw.SizedBox(width: 40, child: pw.Text("-", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                  ]),
                );
              }),
              _dash(),
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
    final items = data['items'] as List;
    final date = _getDateTime(data['createdAt']);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final logo = await _loadLogo();
    final resDetails = await _getRestaurantDetails(data, restaurantName, "Market Road, City");
    final actualHotelName = resDetails['name']!;

    await _safePrint(
      name: 'Order_${orderId.substring(0, 8)}.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              pw.Center(child: pw.Image(logo, width: 45, height: 45)),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(actualHotelName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
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
    final items = (orderData['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final date = DateTime.now();
    final dateStr = DateFormat('dd-MM-yyyy  hh:mm a').format(date);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final receiptNum = orderData['receiptNumber'] ?? orderId.substring(0, 6);
    final logo = await _loadLogo();
    final resDetails = await _getRestaurantDetails(orderData, hotelName, address);
    final actualHotelName = resDetails['name']!;
    final actualAddress = resDetails['address']!;

    await _safePrint(
      name: 'Invoice_$receiptNum.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: _getThermalFormat(format.width),
            theme: theme,
            build: (pw.Context context) => _receiptWrapper(format.width, [
              // ── Header ─────────────────────────────────────────
              pw.Center(child: pw.Image(logo, width: 45, height: 45)),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(actualHotelName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Center(child: pw.Text(actualAddress, style: const pw.TextStyle(fontSize: 7))),
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
                pw.Text("Token: ${orderData['kotNumber'] ?? 'N/A'}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
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
              ...items.map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                final itemName = item['name']?.toString() ?? '';
                final itemQty = (item['quantity'] as num?)?.toInt() ?? 1;
                final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
                return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                      child: pw.Row(children: [
                        pw.Expanded(child: pw.Text(itemName.toUpperCase(), style: const pw.TextStyle(fontSize: 8))),
                        pw.SizedBox(width: 20, child: pw.Text("$itemQty", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                        pw.SizedBox(width: 35, child: pw.Text("$itemPrice", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                        pw.SizedBox(width: 40, child: pw.Text("₹${(itemPrice * itemQty).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      ]),
                    );
              }),
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
              pw.Center(child: pw.Text(actualHotelName, style: const pw.TextStyle(fontSize: 6))),
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
    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
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
          return pdf.save();
        },
        name: 'Revenue_Summary_$dateStr.pdf');
  }

  // ── ORDER HISTORY REPORT ──────────────────────────────────────────────
  static Future<void> printOrderHistoryReport({
    required String restaurantName,
    required List<Map<String, dynamic>> orders,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startStr = DateFormat('dd-MM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MM-yyyy').format(endDate);
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
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
                      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.white),
                          children: [
                            _tableHeader("Date"),
                            _tableHeader("Order ID"),
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
                              _tableCell((order['id']?.toString() ?? 'N/A').toUpperCase()),
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
                    pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Page ${(i/itemsPerPage).toInt() + 1}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.black))),
                  ],
                ),
              ),
            ),
          );
        }
        return pdf.save();
      }, 
      name: 'Order_History_Report.pdf'
    );
  }

  static pw.Widget _tableHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: align),
  );

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 8), textAlign: align),
  );

  // ── ESC/POS GENERATORS (Thermal Printers) ──────────────────────────────
  static Future<List<int>> generateKOTBytes(Map<String, dynamic> data, {PaperSize paperSize = PaperSize.mm58}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final kotNum = data['kotNumber'] ?? 'N/A';
    final tableName = _formatOrderTypeDisplay(data);
    final waiterName = data['waiterName'] ?? 'Staff';
    final timeStr = DateFormat('hh:mm a').format(DateTime.now());
    final note = data['note'] ?? '';

    // Header: YUGPOS
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("YUGPOS", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.text("KITCHEN TICKET", styles: const PosStyles(bold: true));
    bytes += generator.hr();

    // Details: size 8 (Font B)
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    bytes += generator.text("KOT : $kotNum");
    bytes += generator.text("Table : $tableName");
    bytes += generator.text("Waiter : $waiterName");
    bytes += generator.text("Time : $timeStr");
    bytes += generator.hr();

    // Column Headers
    bytes += generator.text("QTY   ITEM", styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
    bytes += generator.hr();

    // Items
    final items = data['items'] as List;
    for (var item in items) {
      final qty = item['quantity'] ?? 1;
      final name = item['name'].toString().toUpperCase();
      // Simple alignment: Qty followed by Name
      bytes += generator.text("${qty.toString().padRight(5)} $name", styles: const PosStyles(fontType: PosFontType.fontB));
    }

    bytes += generator.hr();

    // Note
    if (note.isNotEmpty) {
      bytes += generator.text("Note : $note", styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
      bytes += generator.hr();
    }

    bytes += generator.feed(3);
    bytes += generator.cut();
    return bytes;
  }

  static Future<List<int>> generateFinalBillBytes({
    required Map<String, dynamic> data,
    required double total,
    required String paymentMode,
    String hotelName = "YUG POS",
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // Header: Title
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.text("INVOICE", styles: const PosStyles(bold: false));
    bytes += generator.hr();

    // Details: size 8 (Font B)
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    bytes += generator.text("Table: ${_formatOrderTypeDisplay(data, isFinalBill: true)}");
    
    final billedAt = _getDateTime(data['billedAt']);
    bytes += generator.text("Date: ${DateFormat('dd/MM/yy hh:mm a').format(billedAt)}");
    bytes += generator.hr();

    // Column Headers
    bytes += generator.row([
      PosColumn(text: "ITEM", width: 7, styles: const PosStyles(bold: true, fontType: PosFontType.fontB)),
      PosColumn(text: "QTY", width: 2, styles: const PosStyles(bold: true, align: PosAlign.center, fontType: PosFontType.fontB)),
      PosColumn(text: "AMT", width: 3, styles: const PosStyles(bold: true, align: PosAlign.right, fontType: PosFontType.fontB)),
    ]);
    bytes += generator.hr();

    // Items
    final items = data['items'] as List;
    for (var item in items) {
      final qty = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0) as num;
      bytes += generator.row([
        PosColumn(text: "${item['name']}".toUpperCase(), width: 7, styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB)),
        PosColumn(text: "$qty", width: 2, styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)),
        PosColumn(text: "${(qty * price).toStringAsFixed(0)}", width: 3, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
    }

    bytes += generator.hr();

    // Grand Total
    bytes += generator.setStyles(const PosStyles(align: PosAlign.right, bold: true));
    bytes += generator.text("TOTAL: INR ${total.toStringAsFixed(0)}", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.hr(ch: '=');

    // Footer
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
    bytes += generator.text("PAYMENT: ${paymentMode.toUpperCase()}");
    bytes += generator.text("Thank you! Visit Again", styles: const PosStyles(bold: true));
    
    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }

  /// Updates Firestore order status to 'billed' and adds timestamp.
  /// Helper to isolate native USB printing from the main thread.
  static Future<void> printBytesIsolated(
      UsbPrinterService printerService, List<int> bytes) async {
    Future.microtask(() async {
      try {
        await printerService.printRawBytes(bytes);
      } catch (e) {
        debugPrint('Print error (isolated): $e');
      }
    });
  }

  static Future<int> recordRevenueAndSettle({
    required String orderId,
    required String restaurantId,
    required double total,
    required String paymentMode,
  }) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final collRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");
    
    // Windows: Firebase plugins may violate Flutter's platform-channel threading rules.
    // Your logs match `firebase_firestore/transaction/...` errors, which frequently
    // crash the app on Windows. So we avoid Firestore transactions on Windows.
    //
    // Tradeoff: `receiptNumber` won't be strictly sequential, but the billing
    // totals and status updates remain correct.
    final isWindows = Platform.isWindows;
    int newReceiptNumber;

    final orderDoc = isWindows
        ? await _firestore.collection('orders').doc(orderId).get()
        : null;
    final orderDataWindows = (orderDoc?.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final orderType = (isWindows ? orderDataWindows['orderType'] : null) != null
        ? (orderDataWindows['orderType'] ?? 'dineIn').toString()
        : 'dineIn';

    // Map payment mode field
    final paymentField = paymentMode.toLowerCase() == 'cash' ? 'cashCollection' : 'upiCollection';

    // Map order type fields
    String typeCollField = 'tableCollection'; // default
    String typeCountField = 'tableCount';     // default
    if (orderType == 'takeaway') {
      typeCollField = 'takeawayCollection';
      typeCountField = 'takeawayCount';
    } else if (orderType == 'delivery') {
      typeCollField = 'deliveryCollection';
      typeCountField = 'deliveryCount';
    } else if (orderType == 'online') {
      typeCollField = 'onlineCollection';
      typeCountField = 'onlineCount';
    }

    if (isWindows) {
      // Generate a stable-ish integer receipt number.
      // (OrderId is random; this just makes printing consistent.) 
      newReceiptNumber = DateTime.now().millisecondsSinceEpoch % 1000000;

      await collRef.set({
        'restaurantId': restaurantId,
        'netCollection': FieldValue.increment(total),
        'grossCollection': FieldValue.increment(total),
        'billCount': FieldValue.increment(1),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        paymentField: FieldValue.increment(total),
        typeCollField: FieldValue.increment(total),
        typeCountField: FieldValue.increment(1),
      }, SetOptions(merge: true));
    } else {
      newReceiptNumber = 1;

      // Phase 1: Atomic transaction to update collections and get next sequential number
      await _firestore.runTransaction((transaction) async {
        final collDoc = await transaction.get(collRef);
        final orderDoc = await transaction.get(_firestore.collection('orders').doc(orderId));
        
        // Firestore may return null data for missing docs; avoid unsafe `as` casts.
        final orderData =
            (orderDoc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        final orderTypeTx = (orderData['orderType'] ?? 'dineIn').toString();

        // Map order type fields
        String typeCollFieldTx = 'tableCollection'; // default
        String typeCountFieldTx = 'tableCount';     // default
        if (orderTypeTx == 'takeaway') {
          typeCollFieldTx = 'takeawayCollection';
          typeCountFieldTx = 'takeawayCount';
        } else if (orderTypeTx == 'delivery') {
          typeCollFieldTx = 'deliveryCollection';
          typeCountFieldTx = 'deliveryCount';
        } else if (orderTypeTx == 'online') {
          typeCollFieldTx = 'onlineCollection';
          typeCountFieldTx = 'onlineCount';
        }
        
        if (!collDoc.exists) {
          newReceiptNumber = 1;
          transaction.set(collRef, {
            'restaurantId': restaurantId,
            'netCollection': total,
            'grossCollection': total,
            'billCount': 1,
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            paymentField: total,
            typeCollFieldTx: total,
            typeCountFieldTx: 1,
          });
        } else {
          // billCount can be stored as int/num/string from legacy data.
          final billCountRaw = collDoc.data()?['billCount'];
          final currentCount = billCountRaw is int
              ? billCountRaw
              : billCountRaw is num
                  ? billCountRaw.toInt()
                  : int.tryParse(billCountRaw?.toString() ?? '') ?? 0;
          newReceiptNumber = currentCount + 1;
          
          transaction.update(collRef, {
            'netCollection': FieldValue.increment(total),
            'grossCollection': FieldValue.increment(total),
            'billCount': FieldValue.increment(1),
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            paymentField: FieldValue.increment(total),
            typeCollFieldTx: FieldValue.increment(total),
            typeCountFieldTx: FieldValue.increment(1),
          });
        }
      });
    }

    // Phase 2: Finalize the order document
    await _firestore.collection('orders').doc(orderId).update({
      'status': 'billed',
      'paymentMode': paymentMode,
      'receiptNumber': newReceiptNumber,
      'billedAt': FieldValue.serverTimestamp(),
    });

    return newReceiptNumber;
  }

  static Future<void> settleOrder({
    required String docId,
    required String paymentMode,
  }) async {
    try {
      await _firestore.collection('orders').doc(docId).update({
        'status': 'billed', // Keep 'billed' for intermediate settlement if needed
        'paymentMode': paymentMode,
        'billedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("Order $docId settled successfully.");
    } catch (e) {
      debugPrint("Error settling order: $e");
      rethrow;
    }
  }
}