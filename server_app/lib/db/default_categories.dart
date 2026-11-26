/// Categories every new user starts with, copied into `categories` on
/// registration. Same names as the former global seed in
/// `migrations/001_initial_schema.sql`; 'other' is deliberately missing
/// (see documentation.md, design decision 6).
const defaultCategoryNames = [
  'food',
  'transport',
  'entertainment',
  'housing',
  'health',
  'insurance',
  'shopping',
  'subscriptions',
  'education',
];
