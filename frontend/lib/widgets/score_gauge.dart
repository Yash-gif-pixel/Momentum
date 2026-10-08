import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../theme/credify_theme.dart';

class ScoreGauge extends StatelessWidget {
  final double score; // 0–100
  final String? band;
  final String? confidence;

  const ScoreGauge({
    super.key,
    required this.score,
    this.band,
    this.confidence,
  });

  Color _colorForScore(double s) {
    if (s >= 65) return const Color(0xFF4ADE80); // green
    if (s >= 45) return const Color(0xFFFBBF24); // amber
    return const Color(0xFFF87171); // red
  }

  String _bandLabel(String? b) {
    switch (b) {
      case 'strong_candidate':
        return 'Strong Candidate';
      case 'manual_review':
        return 'Refer for Manual Review';
      case 'high_risk_referral':
        return 'High-Risk Referral';
      default:
        return '—';
    }
  }

  Color _bandColor(String? b) {
    switch (b) {
      case 'strong_candidate':
        return const Color(0xFF4ADE80);
      case 'manual_review':
        return const Color(0xFFFBBF24);
      case 'high_risk_referral':
        return const Color(0xFFF87171);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForScore(score);
    return Column(
      children: [
        CircularPercentIndicator(
          radius: 90.0,
          lineWidth: 14.0,
          animation: true,
          animationDuration: 900,
          percent: (score / 100).clamp(0.0, 1.0),
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                'Vitality Signal',
                style: TextStyle(
                  fontSize: 11,
                  color: context.tokens.textSecondary,
                ),
              ),
            ],
          ),
          progressColor: color,
          backgroundColor: context.tokens.hairline,
          circularStrokeCap: CircularStrokeCap.round,
        ),
        const SizedBox(height: 16),
        if (band != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _bandColor(band).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _bandColor(band), width: 1.2),
            ),
            child: Text(
              _bandLabel(band),
              style: TextStyle(
                color: _bandColor(band),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ),
        if (confidence != null) ...[
          const SizedBox(height: 8),
          Text(
            'Confidence: ${confidence == 'high' ? 'High ✓' : 'Low — review advised'}',
            style: TextStyle(
              color: confidence == 'high'
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFFBBF24),
              fontSize: 12,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ],
    );
  }
}
