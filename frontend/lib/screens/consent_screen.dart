import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/persona_meta.dart';
import '../state/app_state.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';

/// First screen after the landing: pick an MSME profile, then authorise the
/// simulated Account Aggregator consent by sliding.
class ConsentScreen extends StatelessWidget {
  /// Jumps the shell to the Lender tab once consent is granted.
  final VoidCallback onContinue;

  const ConsentScreen({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Consumer<AppState>(
      builder: (context, state, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: HeroPill(
                  icon: Icons.insights_rounded,
                  label: '24-MONTH CASH-FLOW ANALYSIS',
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Credit invisible.\nCash flow real.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Account Aggregator transaction history turned into an '
                  'explainable credit signal for MSMEs with no bureau file — '
                  'decision support for a lender, never an automatic approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PICK A BORROWER · NO LOGIN',
                      style: TextStyle(
                        color: t.accentA,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Demo MSME profiles',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Spread the profiles across the full width only when each one
              // still gets enough room to read; otherwise fall back to the
              // swipeable rail.
              //
              // This used to be a flat `width >= 820`, which was tuned when
              // there were five profiles (~145px each). At seven that same
              // width gives ~103px per card and the name, sector and coverage
              // lines all collapse into ellipses. Deciding on per-card width
              // instead means adding a profile can no longer silently crush
              // the row.
              SizedBox(
                height: 208,
                child: _fitsInARow(
                  MediaQuery.of(context).size.width,
                  state.availableProfileIds.length,
                )
                    ? Row(
                        children: [
                          for (
                            var i = 0;
                            i < state.availableProfileIds.length;
                            i++
                          ) ...[
                            if (i > 0) const SizedBox(width: 14),
                            Expanded(
                              child: _PersonaCard(
                                profileId: state.availableProfileIds[i],
                                selected:
                                    state.hasPickedProfile &&
                                    state.availableProfileIds[i] ==
                                        state.selectedProfileId,
                                onTap: () => _openConsentSheet(
                                  context,
                                  state,
                                  state.availableProfileIds[i],
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        clipBehavior: Clip.none,
                        itemCount: state.availableProfileIds.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final id = state.availableProfileIds[i];
                          return SizedBox(
                            width: 212,
                            child: _PersonaCard(
                              profileId: id,
                              selected: state.hasPickedProfile &&
                                  id == state.selectedProfileId,
                              onTap: () =>
                                  _openConsentSheet(context, state, id),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),

              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: StatTile(value: '521', caption: 'Profiles scored'),
                    ),
                    _divider(t),
                    const Expanded(
                      child: StatTile(value: '0.96', caption: 'Model AUC'),
                    ),
                    _divider(t),
                    const Expanded(
                      child: StatTile(
                        value: '10',
                        caption: 'Predictive features',
                      ),
                    ),
                    _divider(t),
                    const Expanded(
                      child: StatTile(
                        value: 'Synthetic',
                        caption: 'Data source',
                      ),
                    ),
                  ],
                ),
              ),
              if (state.consentApproved) ...[
                const SizedBox(height: 22),
                GlassCard(
                  borderColor: t.positive.withValues(alpha: 0.45),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: t.positive,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Consent granted for '
                          '${PersonaMeta.forId(state.selectedProfileId).name}.',
                          style: TextStyle(
                            color: t.positive,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: state.revokeConsent,
                        style: TextButton.styleFrom(
                          foregroundColor: t.negative,
                        ),
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Narrowest a persona card may get before the row stops being readable.
  /// Below this the rail is the better answer — a card the user can swipe to
  /// beats seven they cannot read.
  static const _minPersonaCardWidth = 190.0;

  /// Mirrors the layout constants used above: 20px page padding either side
  /// and a 14px gap between cards.
  static bool _fitsInARow(double screenWidth, int count) {
    if (count == 0) return true;
    final available = screenWidth - 40 - (count - 1) * 14;
    return available / count >= _minPersonaCardWidth;
  }

  Widget _divider(CredifyTokens t) =>
      Container(width: 1, height: 26, color: t.hairline);

  void _openConsentSheet(BuildContext context, AppState state, String id) {
    state.selectProfile(id);
    final meta = PersonaMeta.forId(id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConsentSheet(
        personaName: meta.name,
        onAuthorized: () async {
          await state.approveConsent();
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          onContinue();
        },
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final String profileId;
  final bool selected;
  final VoidCallback onTap;

  const _PersonaCard({
    required this.profileId,
    required this.selected,
    required this.onTap,
  });

  /// Data coverage only — the score and outcome stay hidden until the lender
  /// actually runs the check, so the reveal is not spoiled here.
  static const _coverage = <String, String>{
    'lakshmi_vendor_001': '24 months · 612 transactions',
    'ramesh_carpentry_004': '22 months · 356 transactions',
    'dormancy_gap_003': '24 months · 401 transactions',
    'thin_file_002': '4 months · 38 transactions',
    'meera_tailor_005': '24 months · 1,916 transactions',
    'arjun_kirana_006': '24 months · 3,927 transactions',
    'uniform_trail_007': '24 months · 624 transactions',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final meta = PersonaMeta.forId(profileId);
    final coverage = _coverage[profileId] ?? 'Demo profile';

    // Unlike the landing pillars, these ARE tap targets, so the hover is an
    // affordance and GlassCard's own InkWell supplies the pointer cursor and
    // ripple. A selected card stays lit whether or not the pointer is on it,
    // and hovering it does not dim it back down.
    return HoverLift(
      lift: 5,
      builder: (context, hovered) => _card(context, t, meta, coverage, hovered),
    );
  }

  Widget _card(
    BuildContext context,
    CredifyTokens t,
    PersonaMeta meta,
    String coverage,
    bool hovered,
  ) {
    final Color? border = selected
        ? t.accentA.withValues(alpha: 0.6)
        : hovered
            ? t.accentA.withValues(alpha: 0.38)
            : null;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      borderColor: border,
      transitionDuration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DATA COVERAGE',
            style: TextStyle(
              color: t.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            coverage,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.accentA.withValues(
                    alpha: (hovered || selected) ? 0.30 : 0.18,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(meta.icon, size: 15, color: t.accentA),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      meta.sector,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Run cash-flow check',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.accentA,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Nudges toward the direction the card takes you.
              AnimatedSlide(
                offset: Offset(hovered ? 0.22 : 0, 0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(Icons.chevron_right, size: 15, color: t.accentA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsentSheet extends StatelessWidget {
  final String personaName;
  final VoidCallback onAuthorized;

  const _ConsentSheet({required this.personaName, required this.onAuthorized});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        border: Border(top: BorderSide(color: t.glassBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 16, color: t.accentA),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'SIMULATED ACCOUNT AGGREGATOR CONSENT',
                    style: TextStyle(
                      color: t.accentA,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Share 24 months of transaction history for $personaName?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Simulated AA flow on synthetic data · read-only · '
              'nothing leaves this session',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 24),
            SlideToAuthorize(
              label: 'Slide to authorise',
              doneLabel: 'Consent granted',
              onAuthorized: onAuthorized,
            ),
          ],
        ),
      ),
    );
  }
}
