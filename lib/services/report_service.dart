import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'usb_printer_service.dart';
import 'bluetooth_printer_service.dart';
import 'lan_printer_service.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/printer_role.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:share_plus/share_plus.dart'; // No longer needed for PDF
// import 'package:path_provider/path_provider.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// On Windows, [Printing.layoutPdf] opens a blocking native dialog that
  /// competes with Firestore's background-thread callbacks on the platform
  /// channel, causing "non-platform thread" crashes. A short async gap allows
  /// Flutter's event loop to drain before the native dialog takes the thread.
  static Future<void> _safePrint({
    required String name,
    required Future<Uint8List> Function(PdfPageFormat) onLayout,
    BluetoothPrinterService? btService,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      if (btService != null && btService.isConnected) {
        // If we have a direct BT connection, ideally we'd print directly.
        // For now, since _safePrint is PDF-focused, we'll keep it as is
        // but the caller should ideally use ESC/POS instead.
      }
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
            'state': resData?['state'] ?? '', // Added state
            'gstNumber': resData?['gstNumber'] ?? '',
          };
        }
      } catch (_) {}
    }
    return {'name': defaultName, 'address': defaultAddress, 'state': '', 'gstNumber': ''};
  }

  static Future<pw.ImageProvider> _loadLogo() async {
    try {
      final logoData = await rootBundle.load('assets/images/yugposlogo.png');
      return pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
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
  // Thermal widths in PDF points (72 pt per inch)
  // 58mm  = 58 / 25.4 * 72 = 164.41 pt
  // 3 inch = 3 * 72 = 216.00 pt
  // Thermal widths in PDF points (72 pt per inch)
  // 58mm  = 58 / 25.4 * 72 = 164.41 pt
  // 3 inch = 3 * 72 = 216.00 pt
  static const double _width58mm = 164.41;
  static const double _width3inch = 216.00; // 3 inches * 72 points
  static const PaperSize _defaultReceiptPaperSize = PaperSize.mm80;

  // Standard thermal page format: defaults to 3-inch (216pt)
  static PdfPageFormat _getThermalFormat(double width) => PdfPageFormat(
        216.0, // Fixed at 3 inches for professional consistency
        100 * PdfPageFormat.cm, // 1 meter max height per page
        marginAll: 0, // Maximize width usage
      );

  // Dynamic content wrapper: always use available printable width.
  static pw.Widget _receiptWrapper(double _pageWidth, List<pw.Widget> children) {
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

  // Thermal text helpers for stable fixed-width formatting.
  // FontA: mm58=32, mm80=64 | FontB (smaller): mm58=42, mm80=58
  static int _thermalChars(PaperSize paperSize) => paperSize == PaperSize.mm58 ? 32 : 64;
  // FontB character width for KOT (smaller font = more chars per line)
  static int _thermalCharsB(PaperSize paperSize) => paperSize == PaperSize.mm58 ? 42 : 58;

  static String _clipText(String text, int maxChars) {
    final clean = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (clean.length <= maxChars) return clean;
    return clean.substring(0, maxChars);
  }

  static String _fitLeft(String text, int width) {
    final clipped = _clipText(text, width);
    return clipped.padRight(width);
  }

  static String _fitRight(String text, int width) {
    final clipped = _clipText(text, width);
    return clipped.padLeft(width);
  }

  static String _lineOf(int count, {String ch = '-'}) => List.filled(count, ch).join();

  static List<String> _wrapText(String text, int width) {
    final clean = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (clean.isEmpty) return [''];
    if (clean.length <= width) return [clean];

    final words = clean.split(RegExp(r'\s+'));
    final List<String> lines = [];
    var current = '';
    for (final w in words) {
      if (current.isEmpty) {
        current = w;
      } else if ((current.length + 1 + w.length) <= width) {
        current = '$current $w';
      } else {
        lines.add(current);
        current = w;
      }
    }
    if (current.isNotEmpty) lines.add(current);

    // If a very long word breaks width, hard-split fallback.
    final List<String> normalized = [];
    for (final line in lines) {
      if (line.length <= width) {
        normalized.add(line);
      } else {
        var start = 0;
        while (start < line.length) {
          final end = (start + width < line.length) ? start + width : line.length;
          normalized.add(line.substring(start, end));
          start = end;
        }
      }
    }
    return normalized;
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

  /// REST-Compatible 80mm Thermal Report
  static Future<void> generateThermalPeriodReport(
      String title, String periodInfo, List<QueryDocumentSnapshot> orders, {String restaurantName = "YUG POS"}) async {
    final total = orders.fold<double>(0, (sum, doc) => sum + (doc['totalAmount'] ?? 0));
    final logo = await _loadLogo();

    await _safePrint(
      name: '${title.replaceAll(' ', '_')}.pdf',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.roll80,
            margin: const pw.EdgeInsets.all(5),
            build: (pw.Context context) => [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(logo, width: 60, height: 60),
                  pw.SizedBox(height: 5),
                  pw.Text(restaurantName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text(title.toUpperCase(),
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 5),
                  pw.Text(periodInfo, style: const pw.TextStyle(fontSize: 9)),
                  pw.Text("Total Orders: ${orders.length}", 
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 5),
                  pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                  pw.SizedBox(height: 10),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("NET COLLECTION:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text("INR ${total.toStringAsFixed(0)}", 
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 0.5),
                  
                  pw.SizedBox(height: 10),
                  pw.TableHelper.fromTextArray(
                    context: context,
                    border: null,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                    cellStyle: const pw.TextStyle(fontSize: 7),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    data: <List<String>>[
                      <String>['Date', 'Type', 'Amt', 'St'],
                      ...orders.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                        final isCancelled = data['status'] == 'cancelled';
                        return [
                          DateFormat('dd/MM').format(createdAt),
                          data['orderType'] == 'takeaway' ? 'TK' : (data['orderType'] == 'dineIn' ? 'DI' : 'DEL'),
                          "${((data['totalAmount'] ?? 0) as num).toStringAsFixed(0)}",
                          isCancelled ? 'CAN' : 'OK',
                        ];
                      })
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text("Generated by YUG POS", style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey)),
                ],
              ),
            ],
          ),
        );
        return pdf.save();
      },
    );
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
            pageFormat: PdfPageFormat.roll80,
            theme: theme,
            margin: const pw.EdgeInsets.all(10),
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
                          pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.blue900)),
                          pw.Text("DAILY REVENUE SUMMARY", style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700, letterSpacing: 1)),
                        ],
                      ),
                      if (logo != null) pw.Image(logo, width: 40),
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
                          pw.Text("Reporting Period", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                          pw.Text(dateStr, style: pw.TextStyle(font: boldFont, fontSize: 11)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text("Status", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                          pw.Text("Finalized", style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.green700)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 30),

                  // Key Highlights
                  pw.Row(
                    children: [
                      _buildHighlightCard("Total Bills", "$bCount", PdfColors.blue700),
                      pw.SizedBox(width: 10),
                      _buildHighlightCard("Net Revenue", "INR ${netCol.toStringAsFixed(0)}", PdfColors.blueGrey900),
                    ],
                  ),
                  pw.SizedBox(height: 15),

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

                  pw.SizedBox(height: 20),
                  
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
      Map<String, dynamic> data, String orderId, {
      BluetoothPrinterService? bt,
      UsbPrinterService? usb,
      LanPrinterService? lan,
      bool forcePdf = false}) async {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isWindows = !kIsWeb && Platform.isWindows;

    final service = await getServiceForRole(PrinterRole.kot, bt: bt, usb: usb, lan: lan);

    // ── Bluetooth / USB Silent Print (Android & Windows) ──
    if ((isAndroid || isWindows) && !forcePdf && service != null &&
        (service.hasSavedPrinter || service.isConnected)) {
      try {
        final bytes = await generateKOTBytes(data, paperSize: _defaultReceiptPaperSize);
        await printBytesIsolated(service, bytes, role: PrinterRole.kot);
        return;
      } catch (e) {
        // fall through to PDF below
      }
    }

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
              // Header
              pw.Center(child: pw.Text("KOT #${data['kotNo'] ?? 1}", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text(_formatOrderTypeDisplay(data).toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
              _thickDash(),

              // Meta Info
              pw.Row(
                children: [
                   pw.Expanded(child: pw.Text("CREATED BY:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                   pw.Expanded(child: pw.Text("${(data['cashierName'] ?? 'Staff')}".toUpperCase(), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                ]
              ),
              pw.Row(
                children: [
                   pw.Expanded(child: pw.Text("WAITER:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                   pw.Expanded(child: pw.Text("${(data['waiterName'] ?? 'Waiter')}".toUpperCase(), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                ]
              ),
              pw.Text("TIME: ${DateFormat('hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
              _dash(),

              // Table Headers
              pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text("ITEM", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 1, child: pw.Text("QTY", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 1, child: pw.Text("RATE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              ]),
              _dash(),

              // Items
              ...((data['items'] as List?) ?? []).map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 3, child: pw.Text((item['name'] ?? '').toUpperCase(), style: const pw.TextStyle(fontSize: 11))),
                    pw.Expanded(flex: 1, child: pw.Text("${item['quantity'] ?? 1}", style: const pw.TextStyle(fontSize: 11), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text("-", style: const pw.TextStyle(fontSize: 11), textAlign: pw.TextAlign.right)),
                  ]),
                );
              }),
              _dash(),

            ]),
          ),
        );
        return pdf.save();
      },
    );
  }

  // â”€â”€ ORDER RECEIPT (waiter copy) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> printOrderReceipt(
      Map<String, dynamic> data, String orderId, {
      String restaurantName = "YUG POS",
      BluetoothPrinterService? bt,
      UsbPrinterService? usb,
      LanPrinterService? lan,
      bool forcePdf = false}) async {
    final items = _groupItems(data['items'] as List? ?? []);
    final date = _getDateTime(data['createdAt']);

    final roboto = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoItalic = await PdfGoogleFonts.robotoItalic();
    final theme = pw.ThemeData.withFont(base: roboto, bold: robotoBold, italic: robotoItalic);

    final logo = await _loadLogo();
    final resDetails = await _getRestaurantDetails(data, restaurantName, "Market Road, City");
    final actualHotelName = resDetails['name']!;
    final actualAddress = resDetails['address'] ?? "Market Road, City";
    final actualState = resDetails['state'] ?? "";
    final actualGst = resDetails['gstNumber']!;

    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isWindows = !kIsWeb && Platform.isWindows;

    final service = await getServiceForRole(PrinterRole.bill, bt: bt, usb: usb, lan: lan);

    // ── Bluetooth / USB Silent Print (Android & Windows) ──
    if ((isAndroid || isWindows) && !forcePdf && service != null &&
        (service.hasSavedPrinter || service.isConnected)) {
      try {
        final bytes = await generateFinalBillBytes(
          data: data,
          total: _getDouble(data['totalAmount']),
          paymentMode: 'PREVIEW',
          hotelName: actualHotelName,
          address: actualAddress,
          state: actualState,
          gstNumber: actualGst,
          paperSize: _defaultReceiptPaperSize,
        );
        await printBytesIsolated(service, bytes, role: PrinterRole.bill);
        return;
      } catch (e) {
      }
    }

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
              if (actualGst.isNotEmpty) pw.Center(child: pw.Text("GSTIN: $actualGst", style: const pw.TextStyle(fontSize: 6))),
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
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
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
                pw.Expanded(flex: 3, child: pw.Text("Item", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6))),
                pw.Expanded(flex: 1, child: pw.Text("Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Text("Amt", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6), textAlign: pw.TextAlign.right)),
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
                        pw.Expanded(flex: 3, child: pw.Text("${item['name']}", style: const pw.TextStyle(fontSize: 6))),
                        pw.Expanded(flex: 1, child: pw.Text("$qty", style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center)),
                        pw.Expanded(flex: 2, child: pw.Text("â‚¹${(price * qty).toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
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
                   pw.Text("TOTAL (EST.)", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
                   pw.Text("₹${(_getDouble(data['totalAmount']) * (1 + (data['gstPercentage'] ?? 0) / 100)).toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6)),
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


  // â”€â”€ Helper: amount row (Updated for better proportions) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _amountRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
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
    Map<String, double>? revenueByPayment,
  }) async {
    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.roll80,
              build: (pw.Context context) => pw.Padding(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(child: pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
                    pw.Center(child: pw.Text("DAILY REVENUE SUMMARY", style: const pw.TextStyle(fontSize: 10))),
                    pw.Center(child: pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(height: 15),

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

                    if (revenueByPayment != null && revenueByPayment.isNotEmpty) ...[
                      pw.Text("REVENUE BY PAYMENT MODE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      pw.Divider(),
                      ...revenueByPayment.entries.map((e) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                            pw.Text(e.key),
                            pw.Text("INR ${e.value.toStringAsFixed(2)}"),
                          ])),
                      pw.SizedBox(height: 20),
                    ],

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

                    pw.SizedBox(height: 20),
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
  static Future<List<int>> generateKOTBytes(Map<String, dynamic> data, {PaperSize paperSize = _defaultReceiptPaperSize}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final kotNo = data['kotNo'] ?? 1;
    final tableName = _formatOrderTypeDisplay(data).toUpperCase();
    final timeStr = DateFormat('hh:mm a').format(DateTime.now());
    final note = data['note'] ?? '';
    final pageChars = _thermalCharsB(paperSize); // FontB = smaller font, more chars per line
    final divider = _lineOf(pageChars, ch: '-');

    // Header
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));
    bytes += generator.text("KOT #$kotNo");
    bytes += generator.text(tableName);
    bytes += generator.text(divider, styles: const PosStyles(align: PosAlign.left));

    // Meta Info - two column layout: label on left, value on right
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    final metaLabelW = 12;
    final metaValueW = pageChars - metaLabelW - 3;
    bytes += generator.text(_fitLeft("CREATED BY", metaLabelW) + " : " + _clipText((data['cashierName'] ?? 'STAFF').toString().toUpperCase(), metaValueW));
    bytes += generator.text(_fitLeft("WAITER", metaLabelW) + " : " + _clipText((data['waiterName'] ?? 'WAITER').toString().toUpperCase(), metaValueW));
    bytes += generator.text(_fitLeft("TIME", metaLabelW) + " : " + _clipText(timeStr, metaValueW));
    bytes += generator.text(divider);

    // Table Headers
    final qtyW = paperSize == PaperSize.mm58 ? 4 : 5;
    final rateW = paperSize == PaperSize.mm58 ? 5 : 6;
    final itemW = pageChars - qtyW - rateW - 2;
    
    bytes += generator.text(
      _fitLeft("ITEM", itemW) + _fitRight("QTY", qtyW) + _fitRight("RATE", rateW),
      styles: const PosStyles(bold: true, fontType: PosFontType.fontB)
    );
    bytes += generator.text(divider);

    // Items
    final items = _groupItems(data['items'] as List? ?? []);
    for (final item in items) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final lines = _wrapText((item['name'] ?? '').toString().toUpperCase(), itemW);
      for (var i = 0; i < lines.length; i++) {
        final isFirst = i == 0;
        final line = _fitLeft(lines[i], itemW) + 
                     _fitRight(isFirst ? "$qty" : "", qtyW) + 
                     _fitRight(isFirst ? "-" : "", rateW);
        bytes += generator.text(line, styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
      }
    }
    bytes += generator.text(divider);

    // Note
    if (note.isNotEmpty) {
      bytes += generator.text("Note : $note", styles: const PosStyles(bold: true, fontType: PosFontType.fontB));
      bytes += generator.text(divider);
    }

    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }

  static Future<List<int>> generateFinalBillBytes({
    required Map<String, dynamic> data,
    required double total,
    required String paymentMode,
    String hotelName = "YUG POS",
    String address = "",
    String state = "", // Added state
    String gstNumber = "",
    PaperSize paperSize = _defaultReceiptPaperSize,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final pageChars = _thermalChars(paperSize);
    // Use full page width with no extra padding
    final contentChars = pageChars;
    final leftPad = 0;
    final rightPad = 0;
    final divider = _lineOf(contentChars, ch: '-');
    final thickDivider = _lineOf(contentChars, ch: '=');

    final receiptNum = (data['receiptNumber'] ?? '').toString();
    final tableDisplay = _formatOrderTypeDisplay(data, isFinalBill: true).toUpperCase();
    final billedAt = _getDateTime(data['billedAt'] ?? data['completedAt'] ?? data['createdAt']);
    final createdAt = _getDateTime(data['createdAt'] ?? data['billedAt'] ?? data['completedAt']);
    final dateStr = DateFormat('dd-MM-yyyy').format(billedAt);
    final startStr = DateFormat('hh:mm a').format(createdAt);
    final endStr = DateFormat('hh:mm a').format(billedAt);

    final groupedItems = _groupItems(data['items'] as List? ?? []);

    final subtotalVal = _getDouble(data['subtotal']) > 0
        ? _getDouble(data['subtotal'])
        : (_getDouble(data['totalAmount']) > 0 ? _getDouble(data['totalAmount']) : _getDouble(data['grandTotal']));
    final serviceChargeVal = _getDouble(data['serviceCharge']);
    final discountVal = _getDouble(data['discount']);
    double cgstVal = _getDouble(data['cgst']);
    double sgstVal = _getDouble(data['sgst']);
    final gstP = _getDouble(data['gstPercentage']);
    if ((cgstVal == 0 && sgstVal == 0) && gstP > 0 && subtotalVal > 0) {
      final half = subtotalVal * (gstP / 2) / 100;
      cgstVal = half;
      sgstVal = half;
    }
    final computedGrand = _getDouble(data['grandTotal']) > 0
        ? _getDouble(data['grandTotal'])
        : (total > 0 ? total : subtotalVal + serviceChargeVal - discountVal + cgstVal + sgstVal);

    String padLine(String line) =>
        (' ' * leftPad) +
        _fitLeft(_clipText(line, contentChars), contentChars) +
        (' ' * rightPad);

    void addLine(String line, {PosStyles style = const PosStyles()}) {
      bytes += generator.text(padLine(line), styles: style);
    }

    String kvLine(String key, String value) {
      final leftWidth = (contentChars * 0.58).floor();
      final rightWidth = contentChars - leftWidth;
      return _fitLeft(key, leftWidth) + _fitRight(value, rightWidth);
    }

    String twoColKvLine({
      required String leftKey,
      required String leftValue,
      required String rightKey,
      required String rightValue,
    }) {
      final colGap = 2;
      final colWidth = ((contentChars - colGap) / 2).floor();
      final keyW = (colWidth * 0.42).floor();
      final valueW = colWidth - keyW - 3; // " : "

      String col(String key, String value) {
        final safeValueW = valueW > 0 ? valueW : 1;
        return _fitLeft(key, keyW) + " : " + _fitLeft(value, safeValueW);
      }

      return col(leftKey, leftValue) + (' ' * colGap) + col(rightKey, rightValue);
    }

    // ITEM layout widths by paper.
    final qtyW = paperSize == PaperSize.mm58 ? 3 : 4;
    final rateW = paperSize == PaperSize.mm58 ? 6 : 9;
    final amtW = paperSize == PaperSize.mm58 ? 7 : 10;
    final spacer = 1;
    final itemNameW = contentChars - qtyW - rateW - amtW - spacer;

    // Header
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
    if (address.isNotEmpty) bytes += generator.text(address);
    if (state.isNotEmpty) bytes += generator.text(state.toUpperCase()); // Added State
    if (gstNumber.isNotEmpty) bytes += generator.text("GSTIN: $gstNumber");
    bytes += generator.text("TAX INVOICE", styles: const PosStyles(bold: true, height: PosTextSize.size1));
    addLine(divider);

    bytes += generator.setStyles(const PosStyles(align: PosAlign.left));
    addLine(twoColKvLine(
      leftKey: "Bill No",
      leftValue: receiptNum.isEmpty ? "N/A" : receiptNum,
      rightKey: "Order",
      rightValue: tableDisplay,
    ));
    addLine(twoColKvLine(
      leftKey: "Date",
      leftValue: dateStr,
      rightKey: "Cashier",
      rightValue: (data['cashierName'] ?? 'STAFF').toString().toUpperCase(),
    ));
    addLine(twoColKvLine(
      leftKey: "Start",
      leftValue: startStr,
      rightKey: "Waiter",
      rightValue: (data['waiterName'] ?? 'STAFF').toString().toUpperCase(),
    ));
    addLine(kvLine("END", endStr));

    final orderTypeStr = (data['orderType'] ?? '').toString().toLowerCase();
    if (orderTypeStr == 'delivery' || orderTypeStr == 'takeaway') {
      final customer = (data['customerName'] ?? 'Walk-in').toString();
      addLine(kvLine("CUSTOMER", customer.toUpperCase()), style: const PosStyles(bold: true));
      final phone = (data['customerContact'] ?? '').toString();
      if (phone.isNotEmpty) addLine(kvLine("PHONE", phone));
      final addr = (data['deliveryAddress'] ?? '').toString();
      if (orderTypeStr == 'delivery' && addr.isNotEmpty) {
        final wrapped = _wrapText("ADDR: $addr", contentChars);
        for (final line in wrapped) {
          addLine(line);
        }
      }
    }

    addLine(divider);

    // Items section
    final itemHeader = _fitLeft("ITEM", itemNameW) +
        _fitRight("QTY", qtyW) +
        _fitRight("RATE", rateW) +
        _fitRight("AMT", amtW);
    addLine(itemHeader, style: const PosStyles(bold: true, fontType: PosFontType.fontB));
    addLine(divider);

    for (final item in groupedItems) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final price = _getDouble(item['price']);
      final amount = qty * price;
      final nameLines = _wrapText((item['name'] ?? '').toString().toUpperCase(), itemNameW);
      for (var i = 0; i < nameLines.length; i++) {
        final isFirst = i == 0;
        final line = _fitLeft(nameLines[i], itemNameW) +
            _fitRight(isFirst ? "$qty" : "", qtyW) +
            _fitRight(isFirst ? price.toStringAsFixed(0) : "", rateW) +
            _fitRight(isFirst ? amount.toStringAsFixed(0) : "", amtW);
        addLine(line);
      }
    }

    addLine(divider);

    // Totals
    addLine(kvLine("SUBTOTAL", "INR ${subtotalVal.toStringAsFixed(2)}"));
    if (serviceChargeVal > 0) {
      addLine(kvLine("SERVICE CHARGE", "INR ${serviceChargeVal.toStringAsFixed(2)}"));
    }
    if (discountVal > 0) {
      addLine(kvLine("DISCOUNT", "-INR ${discountVal.toStringAsFixed(2)}"));
    }
    if (cgstVal > 0) {
      final p = gstP > 0 ? " (${(gstP / 2).toStringAsFixed(1)}%)" : "";
      addLine(kvLine("CGST$p", "INR ${cgstVal.toStringAsFixed(2)}"));
    }
    if (sgstVal > 0) {
      final p = gstP > 0 ? " (${(gstP / 2).toStringAsFixed(1)}%)" : "";
      addLine(kvLine("SGST$p", "INR ${sgstVal.toStringAsFixed(2)}"));
    }

    addLine(thickDivider);
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left, bold: true));
    addLine(kvLine("GRAND TOTAL", "INR ${computedGrand.toStringAsFixed(2)}"),
        style: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1));
    addLine(thickDivider);

    // Footer
    bytes += generator.setStyles(const PosStyles(align: PosAlign.left));
    addLine(kvLine("PAYMENT", paymentMode.toUpperCase()));
    addLine(kvLine("STATUS", "PAID"));
    // Keep footer compact to reduce paper usage.
    bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
    bytes += generator.text("Thank you! Visit Again");
    bytes += generator.text(hotelName.toUpperCase(), styles: const PosStyles(bold: true, height: PosTextSize.size1));

    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  /// Updates Firestore order status to 'billed' and adds timestamp.
  /// Helper to isolate native USB printing from the main thread.
  /// Helper to isolate native printing from the main thread.
  /// Supports both UsbPrinterService (Windows) and BluetoothPrinterService (Android).
  static Future<void> printBytesIsolated(
      dynamic printerService, List<int> bytes, {PrinterRole role = PrinterRole.bill}) async {
    final roleName = role == PrinterRole.kot ? "KOT" : "Bill";
    try {
      Fluttertoast.showToast(
        msg: "Connecting to saved $roleName Printer...", 
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT,
      );
    } catch (_) {}

    try {
      bool success = false;
      if (printerService is UsbPrinterService) {
        success = await printerService.printRawBytes(bytes, role: role);
      } else if (printerService is BluetoothPrinterService) {
        success = await printerService.printRoleBytes(bytes, role);
      } else if (printerService is LanPrinterService) {
        success = await printerService.printRawBytes(bytes, role: role);
      } else {
        return;
      }

      if (!success) {
        Fluttertoast.showToast(msg: "Bluetooth connection error", backgroundColor: Colors.red);
        throw Exception('Printer returned failure. Check connection for $role.');
      }
      
      Fluttertoast.showToast(msg: "$roleName Printed Successfully", backgroundColor: Colors.green);
    } catch (e) {
      if (e is! Exception) {
         Fluttertoast.showToast(msg: "Bluetooth connection error", backgroundColor: Colors.red);
      }
      rethrow; // let caller handle it (e.g., fall back to PDF)
    }
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
        'date': today,
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
            'date': today,
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
      rethrow;
    }
  }

  static Future<List<int>> generateDailyCollectionBytes({
    required Map<String, dynamic> data,
    String hotelName = "YUG POS",
    PaperSize paperSize = PaperSize.mm80,
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

  static Future<Uint8List> generateFinalBillPdfBytes({
    required Map<String, dynamic> data,
    required double total,
    required String paymentMode,
    String hotelName = "YUG POS",
    String address = "",
    String state = "",
    String gstNumber = "",
  }) async {
    final pdf = pw.Document();

    final receiptNum = (data['receiptNumber'] ?? '').toString();
    final tableDisplay = _formatOrderTypeDisplay(data, isFinalBill: true).toUpperCase();
    final billedAt = _getDateTime(data['billedAt'] ?? data['completedAt'] ?? data['createdAt']);
    final dateStr = DateFormat('dd-MM-yyyy').format(billedAt);
    final timeStr = DateFormat('hh:mm a').format(billedAt);

    final groupedItems = _groupItems(data['items'] as List? ?? []);

    final subtotalVal = _getDouble(data['subtotal']) > 0
        ? _getDouble(data['subtotal'])
        : (_getDouble(data['totalAmount']) > 0 ? _getDouble(data['totalAmount']) : _getDouble(data['grandTotal']));
    final serviceChargeVal = _getDouble(data['serviceCharge']);
    final discountVal = _getDouble(data['discount']);
    double cgstVal = _getDouble(data['cgst']);
    double sgstVal = _getDouble(data['sgst']);
    final gstP = _getDouble(data['gstPercentage']);
    if ((cgstVal == 0 && sgstVal == 0) && gstP > 0 && subtotalVal > 0) {
      final half = subtotalVal * (gstP / 2) / 100;
      cgstVal = half;
      sgstVal = half;
    }
    final computedGrand = _getDouble(data['grandTotal']) > 0
        ? _getDouble(data['grandTotal'])
        : (total > 0 ? total : subtotalVal + serviceChargeVal - discountVal + cgstVal + sgstVal);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(hotelName.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
              if (state.isNotEmpty) pw.Text(state, style: const pw.TextStyle(fontSize: 10)),
              if (gstNumber.isNotEmpty) pw.Text("GSTIN: $gstNumber", style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(),
              pw.Text("TAX INVOICE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Bill No: $receiptNum", style: const pw.TextStyle(fontSize: 10)),
                  pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 10)),
                ]
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Table/Order: $tableDisplay", style: const pw.TextStyle(fontSize: 10)),
                  pw.Text("Time: $timeStr", style: const pw.TextStyle(fontSize: 10)),
                ]
              ),
              pw.Divider(),
              // Items Header
              pw.Row(
                children: [
                  pw.Expanded(flex: 3, child: pw.Text("ITEM", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  pw.Expanded(flex: 1, child: pw.Text("QTY", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  pw.Expanded(flex: 1, child: pw.Text("RATE", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  pw.Expanded(flex: 2, child: pw.Text("AMOUNT", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                ]
              ),
              pw.Divider(),
              // Items List
              ...groupedItems.map((item) {
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final price = _getDouble(item['price']);
                final amount = qty * price;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text((item['name'] ?? '').toString().toUpperCase(), style: const pw.TextStyle(fontSize: 10))),
                      pw.Expanded(flex: 1, child: pw.Text("$qty", textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                      pw.Expanded(flex: 1, child: pw.Text(price.toStringAsFixed(0), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                      pw.Expanded(flex: 2, child: pw.Text(amount.toStringAsFixed(0), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                    ]
                  )
                );
              }),
              pw.Divider(),
              // Totals
              _buildTotalsRow("SUBTOTAL", subtotalVal),
              if (serviceChargeVal > 0) _buildTotalsRow("SERVICE CHARGE", serviceChargeVal),
              if (discountVal > 0) _buildTotalsRow("DISCOUNT", -discountVal),
              if (cgstVal > 0) _buildTotalsRow("CGST${gstP > 0 ? ' (${(gstP / 2).toStringAsFixed(1)}%)' : ''}", cgstVal),
              if (sgstVal > 0) _buildTotalsRow("SGST${gstP > 0 ? ' (${(gstP / 2).toStringAsFixed(1)}%)' : ''}", sgstVal),
              pw.Divider(thickness: 1.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("GRAND TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text("INR ${computedGrand.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                ]
              ),
              pw.Divider(thickness: 1.5),
              // Footer
              pw.SizedBox(height: 5),
              _buildTotalsRow("PAYMENT MODE", 0, valueStr: paymentMode.toUpperCase()),
              _buildTotalsRow("STATUS", 0, valueStr: "PAID"),
              pw.SizedBox(height: 10),
              pw.Text("Thank you! Visit Again", style: const pw.TextStyle(fontSize: 10)),
              pw.Text(hotelName.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildTotalsRow(String label, double value, {String? valueStr}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(valueStr ?? "INR ${value.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 10)),
        ]
      )
    );
  }

  static Future<void> printFinalBill({
    required Map<String, dynamic> data,
    required String orderId,
    required double total,
    required String paymentMode,
    String? receiptNum,
    BluetoothPrinterService? bt,
    UsbPrinterService? usb,
    LanPrinterService? lan,
    bool forcePdf = false,
  }) async {
    final resId = data['restaurantId'];
    String hotelName = "YUG POS";
    String address = "Market Road, City";
    String state = "";
    String gstNumber = "";

    if (resId != null) {
      final doc = await _firestore.collection('restaurants').doc(resId).get();
      if (doc.exists) {
        final resData = doc.data();
        hotelName = resData?['name'] ?? hotelName;
        address = resData?['address'] ?? address;
        state = resData?['state'] ?? "";
        gstNumber = resData?['gstNumber'] ?? "";
      }
    }

    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isWindows = !kIsWeb && Platform.isWindows;

    final service = await getServiceForRole(PrinterRole.bill, bt: bt, usb: usb, lan: lan);

    // ── Silent Print (Android & Windows) ──
    if ((isAndroid || isWindows) && !forcePdf && service != null &&
        (service.hasSavedPrinter || service.isConnected)) {
      try {
        final bytes = await generateFinalBillBytes(
          data: {
            ...data,
            if (receiptNum != null) 'receiptNumber': receiptNum,
          },
          total: total,
          paymentMode: paymentMode,
          hotelName: hotelName,
          address: address,
          state: state,
          gstNumber: gstNumber,
          paperSize: _defaultReceiptPaperSize,
        );

        await printBytesIsolated(service, bytes, role: PrinterRole.bill);
        return;
      } catch (e) {
      }
    }

    await _safePrint(
      name: 'Bill_${receiptNum ?? orderId.substring(0, 4)}.pdf',
      onLayout: (PdfPageFormat format) async {
        return generateFinalBillPdfBytes(
          data: {
            ...data,
            if (receiptNum != null) 'receiptNumber': receiptNum,
          },
          total: total,
          paymentMode: paymentMode,
          hotelName: hotelName,
          address: address,
          state: state,
          gstNumber: gstNumber,
        );
      },
    );
  }

  static Future<dynamic> getServiceForRole(PrinterRole role, {
    BluetoothPrinterService? bt,
    UsbPrinterService? usb,
    LanPrinterService? lan,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(role == PrinterRole.kot ? 'kot_connection_type' : 'bill_connection_type') ?? 'bluetooth';
    
    if (typeStr == 'bluetooth') return bt;
    if (typeStr == 'usb') return usb;
    if (typeStr == 'lan') return lan;
    return bt; // fallback
  }

  static Future<void> shareBillAsPdf({
    required Map<String, dynamic> orderData,
    required String orderId,
    required double total,
    required String paymentMode,
    String? receiptNum,
  }) async {
    try {
      final resId = orderData['restaurantId'];
      String hotelName = "YUG POS";
      String address = "Market Road, City";
      String state = "";
      String gstNumber = "";

      if (resId != null) {
        final doc = await _firestore.collection('restaurants').doc(resId).get();
        if (doc.exists) {
          final resData = doc.data();
          hotelName = resData?['name'] ?? hotelName;
          address = resData?['address'] ?? address;
          state = resData?['state'] ?? "";
          gstNumber = resData?['gstNumber'] ?? "";
        }
      }

      final pdfBytes = await generateFinalBillPdfBytes(
        data: {
          ...orderData,
          if (receiptNum != null) 'receiptNumber': receiptNum,
        },
        total: total,
        paymentMode: paymentMode,
        hotelName: hotelName,
        address: address,
        state: state,
        gstNumber: gstNumber,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "Bill_${receiptNum ?? orderId.substring(0, 4)}.pdf",
      );
    } catch (e) {
      Fluttertoast.showToast(msg: "Share Error: $e", backgroundColor: Colors.red);
    }
  }
}
