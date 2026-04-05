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

  static List<Map<String, dynamic>> _groupItems(List<dynamic> rawItems) {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var raw in rawItems) {
      final item = Map<String, dynamic>.from(raw as Map);
      final itemName = item['name']?.toString() ?? 'Unknown';
      final itemPrice = _getDouble(item['price']);
      final itemQty = (item['quantity'] as num?)?.toInt() ?? 1;
      
      final key = "$itemName-$itemPrice";
      if (grouped.containsKey(key)) {
        grouped[key]!['quantity'] += itemQty;
      } else {
        grouped[key] = {
          'name': itemName,
          'price': itemPrice,
          'quantity': itemQty,
          'category': item['category'],
        };
      }
    }
    return grouped.values.toList();
  }

  // â”€â”€ Standard thermal widths in PDF points (72 points per inch) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ Professional Separators (Vector Lines instead of Text Dots) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _dash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
        child: pw.Divider(
          color: PdfColors.grey800,
          thickness: 0.5,
          borderStyle: pw.BorderStyle.dashed,
        ),
      );

  static pw.Widget _thickDash() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
        child: pw.Divider(
          color: PdfColors.black,
          thickness: 1.0,
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

  // â”€â”€ DAILY COLLECTION REPORT (A4) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> generateDailyCollectionReport(
      DateTime date, List<QueryDocumentSnapshot> orders, {String restaurantName = "YUG POS"}) async {
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    await generatePeriodReport("Daily Collection Report", "Date: $dateStr", orders, restaurantName: restaurantName);
  }

  // â”€â”€ GENERAL PERIOD REPORT (A4) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ DAILY COLLECTION REPORT (A4) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> printDailyCollection({
    required Map<String, dynamic> data,
    required String restaurantName,
    required String dateStr,
  }) async {
    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);

    final netCol = (data['netCollection'] as num?)?.toDouble() ?? 0.0;
    final upiCol = (data['upiCollection'] as num?)?.toDouble() ?? 0.0;
    final cashCol = (data['cashCollection'] as num?)?.toDouble() ?? 0.0;
    final cardCol = (data['cardCollection'] as num?)?.toDouble() ?? 0.0;
    final dineInCol = (data['tableCollection'] as num?)?.toDouble() ?? 0.0;
    final takeawayCol = (data['takeawayCollection'] as num?)?.toDouble() ?? 0.0;
    final deliveryCol = (data['deliveryCollection'] as num?)?.toDouble() ?? 0.0;
    final bCount = (data['billCount'] as num?)?.toInt() ?? 0;
    final cCount = (data['cancelCount'] as num?)?.toInt() ?? 0;

    await _safePrint(
      name: 'Daily_Collection_$dateStr.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        final logo = await _loadLogo();

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            theme: theme,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Professional Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 22, color: PdfColors.blue900)),
                          pw.Text("DAILY REVENUE SUMMARY", style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.grey700, letterSpacing: 1)),
                        ],
                      ),
                      if (logo != null) pw.Image(logo, width: 70),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.SizedBox(height: 15),

                  // Info Row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("Reporting Period", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                          pw.Text(dateStr, style: pw.TextStyle(font: boldFont, fontSize: 14)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text("Status", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                          pw.Text("Finalized", style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.green700)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 30),

                  // Key Highlights
                  pw.Row(
                    children: [
                      _buildHighlightCard("Total Transactions", "$bCount", PdfColors.blue700),
                      pw.SizedBox(width: 20),
                      _buildHighlightCard("Net Collection", "INR ${netCol.toStringAsFixed(0)}", PdfColors.blueGrey900),
                    ],
                  ),
                  pw.SizedBox(height: 40),

                  // Detailed Breakdown Section
                  pw.Text("PAYMENT MODE BREAKDOWN", style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900)),
                  pw.SizedBox(height: 10),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    children: [
                      _buildTableRow("Cash Collection", "INR ${cashCol.toStringAsFixed(0)}", font, boldFont),
                      _buildTableRow("UPI Payments", "INR ${upiCol.toStringAsFixed(0)}", font, boldFont),
                      _buildTableRow("Card Payments", "INR ${cardCol.toStringAsFixed(0)}", font, boldFont),
                    ],
                  ),
                  pw.SizedBox(height: 30),

                  pw.Text("SOURCE CHANNEL BREAKDOWN", style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900)),
                  pw.SizedBox(height: 10),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    children: [
                      _buildTableRow("Dine-In Sales", "INR ${dineInCol.toStringAsFixed(0)}", font, boldFont),
                      _buildTableRow("Takeaway Orders", "INR ${takeawayCol.toStringAsFixed(0)}", font, boldFont),
                      _buildTableRow("Delivery Services", "INR ${deliveryCol.toStringAsFixed(0)}", font, boldFont),
                    ],
                  ),

                  pw.Spacer(),
                  
                  // Footer
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Generated by YUG POS v2.0", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                      pw.Text("Timestamp: ${DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.now())}", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                    ],
                  ),
                ],
              );
            },
          )
        );
        return pdf.save();
      }
    );
  }

  static pw.Widget _buildHighlightCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(15),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600, letterSpacing: 0.5)),
            pw.SizedBox(height: 5),
            pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.TableRow _buildTableRow(String label, String value, pw.Font font, pw.Font boldFont) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(2),
          child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 6)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(2),
          child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(font: boldFont, fontSize: 6)),
        ),
      ],
    );
  }

  // â”€â”€ KOT RECEIPT (Professional Layout) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
              // â”€â”€ Header â”€â”€
              pw.Center(
                child: pw.Text("KOT", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 1),
              pw.Center(
                child: pw.Text(_formatOrderTypeDisplay(data),
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 1),
              
              // â”€â”€ Meta Info â”€â”€
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Token: ${data['kotNumber'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 6)),
                  pw.Text("Time: ${DateFormat('hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 6)),
                ]
              ),
              pw.SizedBox(height: 1),
              pw.Text("Waiter: ${data['waiterName'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 6)),
              _thickDash(),

              // â”€â”€ Column headers â”€â”€
              pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text("ITEM", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 1, child: pw.Text("QTY", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ]),
              _dash(),

              // â”€â”€ Items â”€â”€
              ...items.map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                final itemName = (item['name']?.toString() ?? '').toUpperCase();
                final itemQty = (item['quantity'] as num?)?.toInt() ?? 1;
                
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                    pw.Expanded(flex: 3, child: pw.Text(itemName, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 1, child: pw.Text("$itemQty", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  ]),
                );
              }),
              _thickDash(),
              pw.SizedBox(height: 10),
            ]),
          ),
        );
        return pdf.save();
      },
    );
  }

  // â”€â”€ ORDER RECEIPT (waiter copy) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> printOrderReceipt(
      Map<String, dynamic> data, String orderId, {String restaurantName = "YUG POS"}) async {
    final items = _groupItems(data['items'] as List? ?? []);
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
              pw.Center(child: pw.Image(logo, width: 35, height: 35)),
              pw.SizedBox(height: 1),
              pw.Center(child: pw.Text(actualHotelName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
              pw.Center(child: pw.Text("ORDER SLIP", style: const pw.TextStyle(fontSize: 6))),
              _thickDash(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Order: ${orderId.substring(0, 8)}", style: const pw.TextStyle(fontSize: 7)),
                  pw.Text("Start: ${DateFormat('dd/MM HH:mm').format(date)}", style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Text(_formatOrderTypeDisplay(data, includeTablePrefix: true), 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              pw.Text("Waiter: ${data['waiterName']}", style: const pw.TextStyle(fontSize: 6)),
              
              // â”€â”€ Customer Info (Delivery/Takeaway Only) â”€â”€
              if (((data['orderType'] ?? '').toString().toLowerCase() == 'delivery' || 
                   (data['orderType'] ?? '').toString().toLowerCase() == 'takeaway') &&
                  (data['customerName'] != null || data['customerContact'] != null)) ...[
                pw.SizedBox(height: 2),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("CUSTOMER: ${(data['customerName'] ?? 'Walk-in').toUpperCase()}", 
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    if (data['customerContact']?.toString().isNotEmpty ?? false)
                      pw.Text("PHONE: ${data['customerContact']}", style: const pw.TextStyle(fontSize: 6)),
                    if ((data['orderType'] ?? '').toString().toLowerCase() == 'delivery' && 
                        data['deliveryAddress']?.toString().isNotEmpty == true)
                      pw.Text("ADDRESS: ${data['deliveryAddress']}", style: const pw.TextStyle(fontSize: 6)),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
              _dash(),
              pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text("Item", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                pw.Expanded(flex: 1, child: pw.Text("Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Text("Amt", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
              ]),
              _dash(),
              ...items.map((item) {
                final qty = item['quantity'] ?? 1;
                final price = item['price'] ?? 0;
                return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(flex: 3, child: pw.Text("${item['name']}", style: const pw.TextStyle(fontSize: 8))),
                        pw.Expanded(flex: 1, child: pw.Text("$qty", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                        pw.Expanded(flex: 2, child: pw.Text("â‚¹${(price * qty).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  );
              }).toList(),
              _dash(),
              _dash(),
              _amountRow("SUBTOTAL", "â‚¹${_getDouble(data['totalAmount']).toStringAsFixed(2)}"),
              if ((data['gstPercentage'] ?? 0) > 0) 
                 _amountRow("EST. GST (${(data['gstPercentage'] ?? 0)}%)", "â‚¹${(_getDouble(data['totalAmount']) * (data['gstPercentage'] ?? 0) / 100).toStringAsFixed(2)}"),
              _thickDash(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                   pw.Text("TOTAL (EST.)", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                   pw.Text("₹${(_getDouble(data['totalAmount']) * (1 + (data['gstPercentage'] ?? 0) / 100)).toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
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

  // â”€â”€ FINAL BILL (Professional Layout) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> printFinalBill({
    required Map<String, dynamic> orderData,
    required String orderId,
    required double subtotal,
    double serviceCharge = 0,
    double discount = 0,
    double? cgst,
    double? sgst,
    required double total,
    required String paymentMode,
    double gstPercentage = 0,
    String hotelName = "YUG POS",
    String address = "Market Road, City",
  }) async {
    final items = _groupItems(orderData['items'] as List? ?? []);
    final date = _getDateTime(orderData['billedAt']);
    final dateStr = DateFormat('dd-MM-yyyy').format(date);
    final timeStr = DateFormat('hh:mm a').format(date);

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
          build: (pw.Context context) {
            final printType = (orderData['orderType'] ?? '').toString().toLowerCase();
            return _receiptWrapper(format.width, [
              
              // â”€â”€ Header â”€â”€
              pw.Center(child: pw.Image(logo, width: 35, height: 35)),
              pw.SizedBox(height: 1),
              pw.Center(child: pw.Text(actualHotelName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
              pw.Center(child: pw.Text(actualAddress, style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center)),
              pw.SizedBox(height: 1),
              
              pw.Center(child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text("TAX INVOICE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
              )),
              pw.SizedBox(height: 4),
              
              // â”€â”€ Meta Data Grid â”€â”€
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Bill No: $receiptNum", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
                  pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 6)),
                ]
              ),
              pw.SizedBox(height: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(_formatOrderTypeDisplay(orderData, isFinalBill: true), style: const pw.TextStyle(fontSize: 6)),
                  pw.Text("Time: $timeStr", style: const pw.TextStyle(fontSize: 6)),
                ]
              ),
              pw.SizedBox(height: 1),
              pw.Text("Waiter: ${orderData['waiterName'] ?? 'Counter'}", style: const pw.TextStyle(fontSize: 6)),
              
              // â”€â”€ Customer Info (Delivery/Takeaway Only) â”€â”€
              if (printType == 'delivery' || printType == 'takeaway') ...[
                pw.SizedBox(height: 1),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("CUSTOMER: ${(orderData['customerName'] ?? 'Walk-in').toUpperCase()}", 
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
                    if (orderData['customerContact'] != null && orderData['customerContact'].toString().isNotEmpty)
                      pw.Text("PHONE: ${orderData['customerContact']}", style: const pw.TextStyle(fontSize: 6)),
                    if (printType == 'delivery' && orderData['deliveryAddress'] != null && 
                        orderData['deliveryAddress'].toString().isNotEmpty)
                      pw.Text("ADDRESS: ${orderData['deliveryAddress']}", style: const pw.TextStyle(fontSize: 6)),
                  ],
                ),
                pw.SizedBox(height: 1),
              ],
              
              _thickDash(),

              // â”€â”€ Column headers â”€â”€
              pw.Row(children: [
                pw.Expanded(flex: 4, child: pw.Text("ITEM", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6))),
                pw.Expanded(flex: 1, child: pw.Text("QTY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Text("RATE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6), textAlign: pw.TextAlign.right)),
                pw.Expanded(flex: 2, child: pw.Text("AMT", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6), textAlign: pw.TextAlign.right)),
              ]),
              _dash(),

              // â”€â”€ Items â”€â”€                 
              ...items.map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                final itemName = item['name']?.toString() ?? '';
                final itemQty = (item['quantity'] as num?)?.toInt() ?? 1;
                final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
                
                return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                        pw.Expanded(flex: 4, child: pw.Text(itemName.toUpperCase(), style: const pw.TextStyle(fontSize: 6))),
                        pw.Expanded(flex: 1, child: pw.Text("$itemQty", style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center)),
                        pw.Expanded(flex: 2, child: pw.Text(itemPrice.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.right)),
                        pw.Expanded(flex: 2, child: pw.Text("${(itemPrice * itemQty).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      ]),
                    );
              }),
              _dash(),

              // â”€â”€ Totals â”€â”€
              pw.SizedBox(height: 4),
              _amountRow("SUBTOTAL", "â‚¹${subtotal.toStringAsFixed(2)}"),
              if (serviceCharge > 0) _amountRow("SERVICE CHARGE", "â‚¹${serviceCharge.toStringAsFixed(2)}"),
              if (discount > 0) _amountRow("DISCOUNT", "-â‚¹${discount.toStringAsFixed(2)}"),
              if (cgst != null && cgst > 0) _amountRow("CGST (${(gstPercentage/2).toStringAsFixed(1)}%)", "â‚¹${cgst.toStringAsFixed(2)}"),
              if (sgst != null && sgst > 0) _amountRow("SGST (${(gstPercentage/2).toStringAsFixed(1)}%)", "â‚¹${sgst.toStringAsFixed(2)}"),
              _thickDash(),
              
              // â”€â”€ Grand Total â”€â”€
              pw.Container(
                color: PdfColors.grey100,
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("GRAND TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text("₹${total.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ]
                )
              ),
              _thickDash(),

              // â”€â”€ Footer â”€â”€
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("PAYMENT: ${paymentMode.toUpperCase()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  pw.Text("STATUS: PAID", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                ]
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text("Thank you! Visit Again", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 6))),
              pw.SizedBox(height: 1),
              pw.Center(child: pw.Text("Powered by YUG POS", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600))),
              pw.SizedBox(height: 2),
            ]);
          },
        ),
      );
      return pdf.save();
    },
  );
}

  // â”€â”€ Helper: amount row (Updated for better proportions) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _amountRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 6)),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
          ],
        ),
      );

  // â”€â”€ REVENUE SUMMARY REPORT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ ORDER HISTORY REPORT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> printOrderHistoryReport({
    required String restaurantName,
    required List<Map<String, dynamic>> orders,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startStr = DateFormat('dd-MM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MM-yyyy').format(endDate);
    
    await _safePrint(
      name: 'Order_History_Report.pdf',
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
                               _tableCell((order['id']?.toString() ?? 'N/A').substring(0, 8).toUpperCase()),
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
      }
    );
  }

  static pw.Widget _tableHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: align),
  );

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 9), textAlign: align),
  );

  // â”€â”€ ESC/POS GENERATORS (Thermal Printers) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

    // Primary Identifiers: LARGE
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("KOT : $kotNum", styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text("TABLE : $tableName", styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Secondary Details: Small
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    bytes += generator.text("Waiter : $waiterName");
    bytes += generator.text("Time : $timeStr");

    // Delivery Info in KOT
    final orderType = (data['orderType'] ?? '').toString().toLowerCase();
    if (orderType == 'delivery' || orderType == 'takeaway') {
      final custName = (data['customerName'] ?? 'Walk-in').toString().toUpperCase();
      bytes += generator.text("CUSTOMER: $custName", styles: const PosStyles(bold: true));
      if (orderType == 'delivery' && data['deliveryAddress'] != null) {
        bytes += generator.text("ADDR: ${data['deliveryAddress']}", styles: const PosStyles(fontType: PosFontType.fontB));
      }
    }
    
    bytes += generator.hr();

    // Column Headers
    bytes += generator.text("QTY   ITEM", styles: const PosStyles(bold: true, fontType: PosFontType.fontA));
    bytes += generator.hr();

    // Items
    final items = data['items'] as List;
    for (var item in items) {
      final qty = item['quantity'] ?? 1;
      final name = item['name'].toString().toUpperCase();
      bytes += generator.text("${qty.toString().padRight(4)} x $name", styles: const PosStyles(bold: true, fontType: PosFontType.fontA));
    }

    bytes += generator.hr();

    // Note
    if (note.isNotEmpty) {
      bytes += generator.emptyLines(1);
      bytes += generator.text("Note : $note", styles: const PosStyles(bold: true, fontType: PosFontType.fontA));
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
    String address = "",
    String gstNumber = "",
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // Header: Title
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: false, fontType: PosFontType.fontB));
    if (address.isNotEmpty) {
      bytes += generator.text(address);
    }
    if (gstNumber.isNotEmpty) {
      bytes += generator.text("GSTIN: $gstNumber");
    }
    bytes += generator.hr(ch: '=');
    bytes += generator.text("TAX INVOICE", styles: const PosStyles(bold: true, height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.hr(ch: '-');

    // Bill Details (Center-Aligned blocks)
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    final receiptNum = data['receiptNumber'] ?? '';
    final tableDisplay = _formatOrderTypeDisplay(data, isFinalBill: true);
    
    bytes += generator.text("BILL #: $receiptNum", styles: const PosStyles(bold: true));
    bytes += generator.text(tableDisplay.toUpperCase(), styles: const PosStyles(bold: true));
    
    final billedAt = _getDateTime(data['billedAt']);
    final createdAt = _getDateTime(data['createdAt']);
    
    final dateStr = DateFormat('dd-MM-yyyy  hh:mm a').format(billedAt);
    final startStr = DateFormat('hh:mm a').format(createdAt);
    final endStr = DateFormat('hh:mm a').format(billedAt);
    
    final token = data['kotNumber'] ?? 'N/A';
    bytes += generator.text("DATE: $dateStr");
    bytes += generator.text("START: $startStr   END: $endStr");
    bytes += generator.text("TOKEN: $token", styles: const PosStyles(bold: true));
    
    bytes += generator.text("CASHIER: ${data['cashierName'] ?? 'STAFF'}");
    bytes += generator.text("WAITER: ${data['waiterName'] ?? 'STAFF'}");

    // Customer Info (Thermal Bill)
    final orderTypeStr = (data['orderType'] ?? '').toString().toLowerCase();
    if (orderTypeStr == 'delivery' || orderTypeStr == 'takeaway') {
      bytes += generator.hr(ch: '-');
      bytes += generator.text("CUSTOMER: ${(data['customerName'] ?? 'Walk-in').toString().toUpperCase()}", styles: const PosStyles(bold: true));
      if (data['customerContact'] != null && data['customerContact'].toString().isNotEmpty) {
        bytes += generator.text("PHONE: ${data['customerContact']}");
      }
      if (orderTypeStr == 'delivery' && data['deliveryAddress'] != null && data['deliveryAddress'].toString().isNotEmpty) {
        bytes += generator.text("ADDRESS: ${data['deliveryAddress']}", styles: const PosStyles(fontType: PosFontType.fontB));
      }
    }

    bytes += generator.hr(ch: '-');

    // Column Headers (6-1-2-3 Optimized for 58mm)
    bytes += generator.row([
      PosColumn(text: "ITEM", width: 6, styles: const PosStyles(bold: true, fontType: PosFontType.fontB)),
      PosColumn(text: "QT", width: 1, styles: const PosStyles(bold: true, align: PosAlign.center, fontType: PosFontType.fontB)),
      PosColumn(text: "RT", width: 2, styles: const PosStyles(bold: true, align: PosAlign.right, fontType: PosFontType.fontB)),
      PosColumn(text: "AMT", width: 3, styles: const PosStyles(bold: true, align: PosAlign.right, fontType: PosFontType.fontB)),
    ]);
    bytes += generator.hr(ch: '.');

    // Items (6-1-2-3 Balanced widths)
    final items = _groupItems(data['items'] as List? ?? []);
    for (var item in items) {
      final qty = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0) as num;
      bytes += generator.row([
        PosColumn(text: "${item['name']}".toUpperCase(), width: 6, styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB)),
        PosColumn(text: "$qty", width: 1, styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)),
        PosColumn(text: "${price.toStringAsFixed(0)}", width: 2, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
        PosColumn(text: "${(qty * price).toStringAsFixed(0)}", width: 3, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
    }

    bytes += generator.hr(ch: '-');

    // Totals Grid (2 columns for alignment)
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    final sub = data['subtotal'] ?? total;
    final sc = data['serviceCharge'] ?? 0;
    final ds = data['discount'] ?? 0;

    bytes += generator.row([
      PosColumn(text: "SUBTOTAL:", width: 7, styles: const PosStyles(fontType: PosFontType.fontB)),
      PosColumn(text: "INR ${sub.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
    ]);

    if (sc > 0) {
      bytes += generator.row([
        PosColumn(text: "SERVICE CHRG:", width: 7, styles: const PosStyles(fontType: PosFontType.fontB)),
        PosColumn(text: "INR ${sc.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
    }

    if (ds > 0) {
      bytes += generator.row([
        PosColumn(text: "DISCOUNT:", width: 7, styles: const PosStyles(fontType: PosFontType.fontB)),
        PosColumn(text: "-INR ${ds.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
    }
    
    // GST Breakdown
    final cgst = data['cgst'] ?? 0;
    final sgst = data['sgst'] ?? 0;
    final gstP = data['gstPercentage'] ?? 0;
    if (cgst > 0) {
      bytes += generator.row([
        PosColumn(text: "CGST (${(gstP/2).toStringAsFixed(1)}%):", width: 7, styles: const PosStyles(fontType: PosFontType.fontB)),
        PosColumn(text: "INR ${cgst.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
      bytes += generator.row([
        PosColumn(text: "SGST (${(gstP/2).toStringAsFixed(1)}%):", width: 7, styles: const PosStyles(fontType: PosFontType.fontB)),
        PosColumn(text: "INR ${sgst.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)),
      ]);
    }

    bytes += generator.emptyLines(1);
    bytes += generator.hr(ch: '=');

    // Grand Total (Centered & Large)
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("GRAND TOTAL", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.text("INR ${total.toStringAsFixed(2)}", styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.hr(ch: '=');
    bytes += generator.text("= " * 16);
    bytes += generator.text("GRAND TOTAL: INR ${total.toStringAsFixed(0)}", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.text("= " * 16);

    // Footer
    bytes += generator.feed(1);
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("PAYMENT: ${paymentMode.toUpperCase()}");
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    bytes += generator.text("STATUS: PAID");
    
    bytes += generator.feed(1);
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: false));
    bytes += generator.text("Thank you! Visit Again");
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(bold: true));
    
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
    
    final isWindows = Platform.isWindows;
    int newReceiptNumber;

    final orderDoc = isWindows
        ? await _firestore.collection('orders').doc(orderId).get()
        : null;
    final orderDataWindows = (orderDoc?.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final orderType = (isWindows ? orderDataWindows['orderType'] : null) != null
        ? (orderDataWindows['orderType'] ?? 'dineIn').toString()
        : 'dineIn';

    String paymentField = 'upiCollection'; // Default
    if (paymentMode.toLowerCase() == 'cash') {
      paymentField = 'cashCollection';
    } else if (paymentMode.toLowerCase() == 'card') {
      paymentField = 'cardCollection';
    }

    String typeCollField = 'tableCollection'; 
    String typeCountField = 'tableCount';     
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

      await _firestore.runTransaction((transaction) async {
        final collDoc = await transaction.get(collRef);
        final orderDoc = await transaction.get(_firestore.collection('orders').doc(orderId));
        
        String paymentFieldTx = 'upiCollection'; 
        if (paymentMode.toLowerCase() == 'cash') paymentFieldTx = 'cashCollection';
        else if (paymentMode.toLowerCase() == 'card') paymentFieldTx = 'cardCollection';
        
        final orderData = (orderDoc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        final orderTypeTx = (orderData['orderType'] ?? 'dineIn').toString();

        String typeCollFieldTx = 'tableCollection'; 
        String typeCountFieldTx = 'tableCount';     
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
            paymentFieldTx: total,
            typeCollFieldTx: total,
            typeCountFieldTx: 1,
          });
        } else {
          final billCountRaw = collDoc.data()?['billCount'];
          final currentCount = billCountRaw is int ? billCountRaw : (billCountRaw is num ? billCountRaw.toInt() : (int.tryParse(billCountRaw?.toString() ?? '') ?? 0));
          newReceiptNumber = currentCount + 1;
          
          transaction.update(collRef, {
            'netCollection': FieldValue.increment(total),
            'grossCollection': FieldValue.increment(total),
            'billCount': FieldValue.increment(1),
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            paymentFieldTx: FieldValue.increment(total),
            typeCollFieldTx: FieldValue.increment(total),
            typeCountFieldTx: FieldValue.increment(1),
          });
        }
      });
    }

    await _firestore.collection('orders').doc(orderId).update({
      'status': 'billed',
      'paymentMode': paymentMode,
      'receiptNumber': newReceiptNumber,
      'billedAt': Timestamp.now(),
    });

    return newReceiptNumber;
  }

  static Future<void> settleOrder({
    required String docId,
    required String paymentMode,
  }) async {
    try {
      await _firestore.collection('orders').doc(docId).update({
        'status': 'billed',
        'paymentMode': paymentMode,
        'billedAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint("Error settling order: $e");
      rethrow;
    }
  }

  static Future<List<int>> generateDailyCollectionBytes({
    required Map<String, dynamic> data,
    String hotelName = "YUG POS",
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final netCol = (data['netCollection'] as num?)?.toDouble() ?? 0.0;
    final upiCol = (data['upiCollection'] as num?)?.toDouble() ?? 0.0;
    final cashCol = (data['cashCollection'] as num?)?.toDouble() ?? 0.0;
    final dineInCol = (data['tableCollection'] as num?)?.toDouble() ?? 0.0;
    final takeawayCol = (data['takeawayCollection'] as num?)?.toDouble() ?? 0.0;
    final deliveryCol = (data['deliveryCollection'] as num?)?.toDouble() ?? 0.0;
    final bCount = (data['billCount'] as num?)?.toInt() ?? 0;
    final cCount = (data['cancelCount'] as num?)?.toInt() ?? 0;

    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("DAILY COLLECTION", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(bold: true));
    bytes += generator.text("Date: $dateStr", styles: const PosStyles(bold: false, fontType: PosFontType.fontB));
    bytes += generator.hr(ch: '=');

    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    bytes += generator.row([
      PosColumn(text: "Total Bills:", width: 8),
      PosColumn(text: "$bCount", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    bytes += generator.row([
      PosColumn(text: "Cancelled:", width: 8),
      PosColumn(text: "$cCount", width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    bytes += generator.hr();

    bytes += generator.text("PAYMENT BREAKDOWN", styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
    bytes += generator.row([
      PosColumn(text: "Cash:", width: 8),
      PosColumn(text: cashCol.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: "UPI:", width: 8),
      PosColumn(text: upiCol.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    bytes += generator.text("SOURCE BREAKDOWN", styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
    bytes += generator.row([
      PosColumn(text: "Dine-In:", width: 8),
      PosColumn(text: dineInCol.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: "Takeaway:", width: 8),
      PosColumn(text: takeawayCol.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: "Delivery:", width: 8),
      PosColumn(text: deliveryCol.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    bytes += generator.setStyles(const PosStyles(align: PosAlign.right, bold: true));
    bytes += generator.text("NET REVENUE: INR ${netCol.toStringAsFixed(0)}", styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    bytes += generator.hr(ch: '=');

    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }

  static Future<void> printOrderHistoryList({
    required List<Map<String, dynamic>> orders,
    required String restaurantName,
    required DateTime date,
  }) async {
    await _safePrint(
      name: "OrderHistory_${DateFormat('yyyyMMdd').format(date)}",
      onLayout: (format) async {
        final pdf = pw.Document();
        final font = await PdfGoogleFonts.interRegular();
        final boldFont = await PdfGoogleFonts.interBold();
        final logo = await _loadLogo();

        pdf.addPage(
          pw.MultiPage(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(16),
            header: (context) => pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Image(logo, width: 60),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(restaurantName, style: pw.TextStyle(font: boldFont, fontSize: 16)),
                        pw.Text("ORDER HISTORY REPORT", style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700)),
                        pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(date)}", style: pw.TextStyle(font: font, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5),
              ],
            ),
            build: (context) => [
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                cellStyle: pw.TextStyle(font: font, fontSize: 8),
                columnWidths: {
                  0: const pw.FixedColumnWidth(45),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FixedColumnWidth(60),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FixedColumnWidth(65),
                },
                headers: ['# Token', 'Items Summary', 'Type', 'Status', 'Amount'],
                data: List<List<String>>.generate(orders.length, (index) {
                  final o = orders[index];
                  final itemsList = (o['items'] as List?) ?? [];
                  final items = itemsList.map((i) => i['name']?.toString() ?? 'Item').join(", ");
                  final token = o['tokenNo']?.toString() ?? (o['id'] != null ? o['id'].toString().substring(0, 4).toUpperCase() : '-');
                  return [
                    "#$token",
                    items.length > 50 ? "${items.substring(0, 47)}..." : items,
                    (o['orderType'] ?? 'dineIn').toString().toUpperCase(),
                    (o['status'] ?? 'new').toString().toUpperCase(),
                    "INR ${o['totalAmount']?.toStringAsFixed(0) ?? '0'}",
                  ];
                }),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("Total Orders: ${orders.length}", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  pw.SizedBox(width: 30),
                  pw.Text(
                    "Total Revenue: INR ${orders.fold<double>(0, (sum, o) => sum + (o['totalAmount'] is num ? (o['totalAmount'] as num).toDouble() : 0.0)).toStringAsFixed(0)}",
                    style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900),
                  ),
                ],
              ),
            ],
            footer: (context) => pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 20),
              child: pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: const pw.TextStyle(fontSize: 8)),
            ),
          ),
        );
        return pdf.save();
      },
    );
  }
}
