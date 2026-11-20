// Flytte eller bytte en kommende økt innen samme uke.
// Belastningen i uka er den samme, så 10 %-regelen påvirkes ikke.
// Regel: aldri to harde økter to dager på rad (også over ukeskiftet).

import 'models.dart';

class MoveOption {
  final DateTime date;
  final Session? swapWith; // økt som ligger på dagen fra før (byttes)
  final bool allowed;
  final String? reason; // hvorfor dagen ikke går

  const MoveOption(this.date, {this.swapWith, this.allowed = true, this.reason});
}

List<Session> _active(List<WeekPlan> weeks) => [
      for (final w in weeks)
        for (final s in w.sessions)
          if (s.status != SessionStatus.staattOver) s
    ];

/// Dager økta kan flyttes til (samme uke, fra i dag, innenfor planen).
List<MoveOption> moveOptions(List<WeekPlan> weeks, Session s, DateTime today, DateTime endDate) {
  final week = weeks.where((w) => w.contains(s.date)).firstOrNull;
  if (week == null || s.status != SessionStatus.planlagt || s.extra) return [];
  final t = dateOnly(today);
  final out = <MoveOption>[];
  for (var i = 0; i < 7; i++) {
    final d = week.monday.add(Duration(days: i));
    if (d == s.date || d.isBefore(t) || d.isAfter(endDate)) continue;
    final there = _active(weeks).where((x) => x.date == d && !x.extra).toList();
    if (there.length > 1) {
      out.add(MoveOption(d, allowed: false, reason: 'Flere økter den dagen'));
      continue;
    }
    final other = there.firstOrNull;
    if (other != null && other.status != SessionStatus.planlagt) {
      out.add(MoveOption(d, allowed: false, reason: 'Økta den dagen er allerede registrert'));
      continue;
    }
    // Hvordan blir harde dager etter flyttingen?
    final dates = <DateTime, bool>{};
    for (final x in _active(weeks)) {
      if (x == s || x == other) continue;
      if (x.isHard) dates[x.date] = true;
    }
    if (s.isHard) dates[d] = true;
    if (other != null && other.isHard) dates[s.date] = true;
    bool hardNear(DateTime day) =>
        (dates[day.subtract(const Duration(days: 1))] ?? false) || (dates[day.add(const Duration(days: 1))] ?? false);
    final bad = (s.isHard && hardNear(d)) || (other != null && other.isHard && hardNear(s.date));
    if (bad) {
      out.add(MoveOption(d, swapWith: other, allowed: false, reason: 'Ville gitt harde økter to dager på rad'));
    } else {
      out.add(MoveOption(d, swapWith: other));
    }
  }
  return out;
}

/// Flytt (eller bytt) økta. Returnerer false hvis det ikke er lov.
bool applyMove(List<WeekPlan> weeks, Session s, MoveOption o) {
  if (!o.allowed) return false;
  final from = s.date;
  s.date = o.date;
  if (o.swapWith != null) o.swapWith!.date = from;
  for (final w in weeks) {
    if (w.contains(o.date) || w.contains(from)) w.sessions.sort((a, b) => a.date.compareTo(b.date));
  }
  return true;
}
