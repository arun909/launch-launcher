import '../models/app_info.dart';

/// Filters [apps] by label, case-insensitively.
///
/// Ranking: labels that start with the query, then labels with a word that
/// starts with it, then any other substring match. Order within each group
/// is preserved (i.e. stays alphabetical). An empty query returns [apps].
List<AppInfo> filterApps(List<AppInfo> apps, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return apps;

  final prefix = <AppInfo>[];
  final wordPrefix = <AppInfo>[];
  final contains = <AppInfo>[];
  for (final app in apps) {
    final label = app.label.toLowerCase();
    if (label.startsWith(q)) {
      prefix.add(app);
    } else if (label.contains(' $q')) {
      wordPrefix.add(app);
    } else if (label.contains(q)) {
      contains.add(app);
    }
  }
  return [...prefix, ...wordPrefix, ...contains];
}
