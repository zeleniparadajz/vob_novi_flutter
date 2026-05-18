import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vodovod_models.dart';

class ReadingCountdown extends StatefulWidget {
  const ReadingCountdown({
    super.key,
    required this.ocitavanjeGlavno,
    this.checkNetwork,
  });

  final OcitavanjeGlavnoModel? ocitavanjeGlavno;
  final Future<bool> Function()? checkNetwork;

  @override
  State<ReadingCountdown> createState() => _ReadingCountdownState();
}

class _ReadingCountdownState extends State<ReadingCountdown> {
  Timer? timer;
  Timer? networkTimer;
  DateTime now = DateTime.now();
  bool? isOnline;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
    unawaited(_checkNetwork());
    networkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkNetwork()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    networkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNetwork() async {
    final checker = widget.checkNetwork;
    if (checker == null) return;
    final result = await checker();
    if (!mounted) return;
    setState(() => isOnline = result);
  }

  @override
  Widget build(BuildContext context) {
    final finishDate = _parseFinishDate(widget.ocitavanjeGlavno);
    if (finishDate == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final remaining = finishDate.difference(now);
    final isFinished = remaining.isNegative || remaining.inSeconds == 0;

    final text = isFinished
        ? 'Očitavanje je završeno!'
        : 'Preostalo: ${remaining.inDays}d ${remaining.inHours % 24}h '
              '${remaining.inMinutes % 60}m ${remaining.inSeconds % 60}s';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Završava: ${DateFormat('dd.MM.yyyy').format(finishDate)} u ${DateFormat('HH:mm').format(finishDate)}h',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _NetworkChip(isOnline: isOnline),
        ],
      ),
    );
  }

  DateTime? _parseFinishDate(OcitavanjeGlavnoModel? model) {
    final value = model?.dateShouldFinish.trim();
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

class _NetworkChip extends StatelessWidget {
  const _NetworkChip({required this.isOnline});

  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = isOnline;
    final color = online == null
        ? theme.colorScheme.onSurfaceVariant
        : online
        ? const Color(0xFF2E7D32)
        : theme.colorScheme.error;
    final label = online == null
        ? 'Provjera'
        : online
        ? 'Online'
        : 'Offline';
    final icon = online == null
        ? Icons.more_horiz
        : online
        ? Icons.wifi
        : Icons.wifi_off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
