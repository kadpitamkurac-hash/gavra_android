import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/finansije_service.dart';

/// 💰 FINANSIJE SCREEN
/// Prikazuje prihode, troškove i neto zaradu
class FinansijeScreen extends StatefulWidget {
  const FinansijeScreen({super.key});

  @override
  State<FinansijeScreen> createState() => _FinansijeScreenState();
}

class _FinansijeScreenState extends State<FinansijeScreen> {
  final _formatBroja = NumberFormat('#,###', 'sr');

  @override
  void initState() {
    super.initState();
  }

  String _formatIznos(double iznos) {
    return '${_formatBroja.format(iznos.round())} din';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FinansijskiIzvestaj>(
      stream: FinansijeService.streamIzvestaj(),
      builder: (context, snapshot) {
        final izvestaj = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting && izvestaj == null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('💰 Finansije'),
            centerTitle: true,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () => _selectCustomRange(),
                tooltip: 'Izveštaj za period',
              ),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : izvestaj == null
                  ? const Center(child: Text('Greška pri učitavanju'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // POTRAŽIVANJA (Dugovi putnika)
                            _buildPotrazivanjaCard(izvestaj.potrazivanja),

                            const SizedBox(height: 16),

                            // NEDELJA
                            _buildPeriodCard(
                              icon: '📅',
                              naslov: 'Ova nedelja',
                              podnaslov: izvestaj.nedeljaPeriod,
                              prihod: izvestaj.prihodNedelja,
                              troskovi: izvestaj.troskoviNedelja,
                              neto: izvestaj.netoNedelja,
                              voznjiLabel: '${izvestaj.voznjiNedelja} vožnji',
                              color: Colors.blue,
                            ),

                            const SizedBox(height: 16),

                            // MESEC
                            _buildPeriodCard(
                              icon: '🗓️',
                              naslov: 'Ovaj mesec',
                              podnaslov: _getMesecNaziv(DateTime.now().month),
                              prihod: izvestaj.prihodMesec,
                              troskovi: izvestaj.troskoviMesec,
                              neto: izvestaj.netoMesec,
                              voznjiLabel: '${izvestaj.voznjiMesec} vožnji',
                              color: Colors.green,
                            ),

                            const SizedBox(height: 16),

                            // PROŠLA GODINA
                            _buildPeriodCard(
                              icon: '📊',
                              naslov: 'Prošla godina (${izvestaj.proslaGodina})',
                              podnaslov: 'Ceo godišnji bilans',
                              prihod: izvestaj.prihodProslaGodina,
                              troskovi: izvestaj.troskoviProslaGodina,
                              neto: izvestaj.netoProslaGodina,
                              voznjiLabel: '${izvestaj.voznjiProslaGodina} vožnji',
                              color: Colors.grey,
                            ),

                            const SizedBox(height: 16),

                            // DETALJI TROŠKOVA
                            _buildTroskoviDetailsList(izvestaj.troskoviPoTipu),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildPeriodCard({
    required String icon,
    required String naslov,
    required String podnaslov,
    required double prihod,
    required double troskovi,
    required double neto,
    required String voznjiLabel,
    required Color color,
  }) {
    final isPositive = neto >= 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        naslov,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        podnaslov,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    voznjiLabel,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Prihod
            _buildRow('Prihod', prihod, Colors.green.shade700, isPlus: true),
            const SizedBox(height: 8),

            // Troškovi
            _buildRow('Troškovi', troskovi, Colors.red.shade700, isMinus: true),

            const SizedBox(height: 8),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 8),

            // NETO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'NETO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatIznos(neto.abs()),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, double iznos, Color color, {bool isMinus = false, bool isPlus = false}) {
    String prefix = '';
    if (isPlus) prefix = '+';
    if (isMinus) prefix = '-';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          '$prefix${_formatIznos(iznos)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTroskoviDetailsList(Map<String, double> troskoviPoTipu) {
    final ukupnoMesecniTroskovi = troskoviPoTipu.values.fold(0.0, (sum, item) => sum + item);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📋 Mesečni troškovi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatIznos(ukupnoMesecniTroskovi),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Lista po tipu
            ...troskoviPoTipu.entries.map(
              (entry) => _buildTrosakRow(entry.key, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrosakRow(String label, double iznos) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            _formatIznos(iznos),
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: iznos > 0 ? Colors.red.shade600 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _getMesecNaziv(int mesec) {
    const meseci = [
      '',
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar'
    ];
    return meseci[mesec];
  }

  Widget _buildPotrazivanjaCard(double iznos) {
    return Card(
      elevation: 4,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade200, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('💰', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Potraživanja (Dugovi)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    'Neplaćene vožnje svih putnika',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Text(
              _formatIznos(iznos),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 31)),
      saveText: 'PRIKAŽI',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      _showCustomReportDialog(picked.start, picked.end);
    }
  }

  void _showCustomReportDialog(DateTime from, DateTime to) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Text('📊 Izveštaj za period'),
            Text(
              '${dateFormat.format(from)} - ${dateFormat.format(to)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.grey),
            ),
          ],
        ),
        content: StreamBuilder<Map<String, dynamic>>(
          stream: Stream.fromFuture(FinansijeService.getIzvestajZaPeriod(from, to)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text('Greška pri učitavanju podataka');
            }

            final data = snapshot.data!;
            final double prihod = (data['prihod'] as num).toDouble();
            final double troskovi = (data['troskovi'] as num).toDouble();
            final double neto = (data['neto'] as num).toDouble();
            final int voznje = data['voznje'] ?? 0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPopupRow('Prihod', prihod, Colors.green),
                const SizedBox(height: 8),
                _buildPopupRow('Troškovi', troskovi, Colors.red),
                const Divider(),
                _buildPopupRow('NETO', neto, neto >= 0 ? Colors.green : Colors.red, isBold: true),
                const SizedBox(height: 16),
                Text('$voznje vožnji u ovom periodu', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ZATVORI'),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupRow(String label, double iznos, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          _formatIznos(iznos),
          style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 18 : 16,
          ),
        ),
      ],
    );
  }
}
