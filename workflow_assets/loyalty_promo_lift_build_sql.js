// Build the loyalty-lift BigQuery SQL from Configure Inputs.
// Required: promo_period_id, marketing_category
// Optional: brand_catalog_id, l10_non_promo_days, store_*, date overrides

const SQL_TEMPLATE = String.raw`__SQL_TEMPLATE__`;

const cfg = $input.first().json;

function requiredNumber(value, fieldName) {
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) {
    throw new Error(`Configure Inputs: set a valid ${fieldName} (got: ${JSON.stringify(value)})`);
  }
  return Math.trunc(num);
}

function escapeSqlString(value) {
  return String(value ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function optionalDateSql(value) {
  if (value === null || value === undefined || value === '') return 'CAST(NULL AS DATE)';
  const text = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new Error(`Configure Inputs: date overrides must be YYYY-MM-DD (got: ${value})`);
  }
  return `DATE '${text}'`;
}

const promoPeriodId = requiredNumber(cfg.promo_period_id, 'promo_period_id');
const marketingCategory = String(cfg.marketing_category || '').trim();
if (!marketingCategory) {
  throw new Error('Configure Inputs: set marketing_category (e.g. Bedding or Window)');
}

const storeBrand = String(cfg.store_brand || 'Wayfair').trim() || 'Wayfair';
const storeCountry = String(cfg.store_country || 'United States').trim() || 'United States';
const brandCatalogName = String(cfg.brand_catalog_name || 'Wayfair US').trim() || 'Wayfair US';
const brandCatalogId = Number(cfg.brand_catalog_id || 1);
const l10Days = Number(cfg.l10_non_promo_days || 10);

if (!Number.isFinite(brandCatalogId) || brandCatalogId <= 0) {
  throw new Error('Configure Inputs: brand_catalog_id must be a positive number');
}
if (!Number.isFinite(l10Days) || l10Days <= 0) {
  throw new Error('Configure Inputs: l10_non_promo_days must be a positive number');
}

const sqlQuery = SQL_TEMPLATE
  .replaceAll('__PROMO_PERIOD_ID__', String(promoPeriodId))
  .replaceAll('__MARKETING_CATEGORY__', escapeSqlString(marketingCategory))
  .replaceAll('__STORE_BRAND__', escapeSqlString(storeBrand))
  .replaceAll('__STORE_COUNTRY__', escapeSqlString(storeCountry))
  .replaceAll('__BRAND_CATALOG_NAME__', escapeSqlString(brandCatalogName))
  .replaceAll('__BRAND_CATALOG_ID__', String(Math.trunc(brandCatalogId)))
  .replaceAll('__L10_NON_PROMO_DAYS__', String(Math.trunc(l10Days)))
  .replaceAll('__PROMO_START_OVERRIDE__', optionalDateSql(cfg.promo_start_override))
  .replaceAll('__PROMO_END_OVERRIDE__', optionalDateSql(cfg.promo_end_override));

return [
  {
    json: {
      promo_period_id: promoPeriodId,
      marketing_category: marketingCategory,
      store_brand: storeBrand,
      store_country: storeCountry,
      brand_catalog_name: brandCatalogName,
      brand_catalog_id: Math.trunc(brandCatalogId),
      l10_non_promo_days: Math.trunc(l10Days),
      promo_start_override: cfg.promo_start_override || null,
      promo_end_override: cfg.promo_end_override || null,
      metric: 'WSC',
      sqlQuery,
    },
  },
];
