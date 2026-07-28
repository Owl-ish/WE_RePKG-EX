/// project.json's `contentrating`, lowercased.
///
/// Not `ratingsex`/`ratingviolence`, which are the descriptors this value is
/// derived from. They are missing on about a fifth of workshop items and do not
/// map onto the three age levels.
class ContentRating {
  static const String everyone = 'everyone';
  static const String questionable = 'questionable';
  static const String mature = 'mature';
}
