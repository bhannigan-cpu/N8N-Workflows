// Bedding Member Monday / Loyalty lift analysis
// Consumes SKU-level BigQuery rows and builds:
// - category / class / supplier / discount-bucket / baseline-tier summaries
// - markdown + HTML case study
// - Google Sheets payloads

const rows = $input.all().map((item) => item.json);

function toNumber(value) {
  if (value === null || value === undefined || value === '') return 0;
  if (typeof value === 'number') return value;
  const cleaned = String(value).replace(/[$,%]/g, '').trim();
  const num = Number(cleaned);
  return Number.isFinite(num) ? num : 0;
}

function round(value, digits = 2) {
  const factor = 10 ** digits;
  return Math.round((Number(value) + Number.EPSILON) * factor) / factor;
}

function fmtCurrency(value) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(toNumber(value));
}

function fmtPct(value, digits = 1) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return 'n/a';
  return `${(toNumber(value) * 100).toFixed(digits)}%`;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function discountBucket(discountPct) {
  const d = toNumber(discountPct);
  if (d < 0.1) return '<10%';
  if (d < 0.15) return '10-14.9%';
  if (d < 0.2) return '15-19.9%';
  if (d < 0.25) return '20-24.9%';
  return '25%+';
}

function quantile(sortedValues, q) {
  if (!sortedValues.length) return 0;
  const pos = (sortedValues.length - 1) * q;
  const base = Math.floor(pos);
  const rest = pos - base;
  if (sortedValues[base + 1] === undefined) return sortedValues[base];
  return sortedValues[base] + rest * (sortedValues[base + 1] - sortedValues[base]);
}

function weightedAvg(values, weights) {
  let num = 0;
  let den = 0;
  for (let i = 0; i < values.length; i += 1) {
    const value = values[i];
    const weight = weights[i];
    if (value === null || value === undefined || Number.isNaN(value)) continue;
    if (!weight || weight <= 0) continue;
    num += value * weight;
    den += weight;
  }
  if (den > 0) return num / den;
  const valid = values.filter((v) => v !== null && v !== undefined && !Number.isNaN(v));
  if (!valid.length) return null;
  return valid.reduce((a, b) => a + b, 0) / valid.length;
}

function summarize(records, groupKeyFn, labelKeys) {
  const groups = new Map();
  for (const row of records) {
    const keyObj = groupKeyFn(row);
    const key = JSON.stringify(keyObj);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }

  const summaries = [];
  for (const [key, group] of groups.entries()) {
    const keyObj = JSON.parse(key);
    const baseline = group.reduce((sum, row) => sum + row.non_promo_avg, 0);
    const sales = group.reduce((sum, row) => sum + row.loyalty_avg, 0);
    const incremental = sales - baseline;
    const weightedLift = baseline ? incremental / baseline : null;
    const skuCount = new Set(group.map((row) => row.sku)).size;
    const activeSkus = new Set(group.filter((row) => row.loyalty_avg > 0).map((row) => row.sku)).size;
    const positiveSkus = new Set(group.filter((row) => row.incremental_sales > 0).map((row) => row.sku)).size;
    const weightedDiscount = weightedAvg(
      group.map((row) => row.discount_pct),
      group.map((row) => row.non_promo_avg),
    );

    const out = {
      ...keyObj,
      sku_count: skuCount,
      active_skus: activeSkus,
      positive_lift_skus: positiveSkus,
      positive_lift_sku_rate: skuCount ? positiveSkus / skuCount : null,
      non_promo_avg: round(baseline, 2),
      loyalty_avg: round(sales, 2),
      incremental_sales: round(incremental, 2),
      weighted_lift_pct: weightedLift === null ? null : round(weightedLift, 4),
      weighted_discount_pct: weightedDiscount === null ? null : round(weightedDiscount, 4),
    };
    for (const label of labelKeys) {
      if (!(label in out)) out[label] = keyObj[label];
    }
    summaries.push(out);
  }

  return summaries.sort((a, b) => b.loyalty_avg - a.loyalty_avg || b.incremental_sales - a.incremental_sales);
}

function markdownTable(rows, columns) {
  if (!rows.length) return '_No rows_';
  const headers = columns;
  const body = rows.map((row) =>
    headers.map((col) => {
      const value = row[col];
      if (value === null || value === undefined) return '';
      return String(value);
    }),
  );
  const widths = headers.map((header, idx) =>
    Math.max(header.length, ...body.map((row) => row[idx].length)),
  );
  const render = (values) =>
    `| ${values.map((value, idx) => value.padEnd(widths[idx])).join(' | ')} |`;
  return [
    render(headers),
    `| ${widths.map((width) => '-'.repeat(width)).join(' | ')} |`,
    ...body.map(render),
  ].join('\n');
}

function htmlTable(rows, columns) {
  if (!rows.length) return '<p><em>No rows</em></p>';
  const head = columns.map((col) => `<th style="text-align:left;padding:6px 10px;border-bottom:1px solid #ddd;">${escapeHtml(col)}</th>`).join('');
  const body = rows
    .map((row) => {
      const cells = columns
        .map((col) => `<td style="padding:6px 10px;border-bottom:1px solid #f0f0f0;">${escapeHtml(row[col] ?? '')}</td>`)
        .join('');
      return `<tr>${cells}</tr>`;
    })
    .join('');
  return `<table style="border-collapse:collapse;width:100%;font-size:13px;"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

function formatSummaryRows(rows) {
  return rows.map((row) => ({
    ...row,
    positive_lift_sku_rate: fmtPct(row.positive_lift_sku_rate),
    weighted_discount_pct: fmtPct(row.weighted_discount_pct),
    non_promo_avg: fmtCurrency(row.non_promo_avg),
    loyalty_avg: fmtCurrency(row.loyalty_avg),
    incremental_sales: fmtCurrency(row.incremental_sales),
    weighted_lift_pct: fmtPct(row.weighted_lift_pct),
  }));
}

if (!rows.length) {
  return [
    {
      json: {
        subject: '[Bedding Loyalty Lift] No participating SKUs found',
        emailHtml:
          '<html><body style="font-family:Arial,sans-serif;"><h2>Bedding Loyalty Lift</h2><p>No participating Bedding SKUs were returned. Check Promo_Period_Id in the BigQuery inputs CTE.</p></body></html>',
        markdown: '# Bedding Loyalty Lift\n\nNo participating SKUs found.',
        spreadsheetTitle: `Bedding Loyalty Lift - empty - ${new Date().toISOString().slice(0, 10)}`,
        sheet_rows: [],
        summary: {
          sku_count: 0,
          loyalty_avg: 0,
          non_promo_avg: 0,
          incremental_sales: 0,
          weighted_lift_pct: null,
        },
      },
    },
  ];
}

const skuData = rows.map((row) => {
  const nonPromoAvg = toNumber(row.non_promo_avg);
  const loyaltyAvg = toNumber(row.loyalty_avg);
  const incremental = loyaltyAvg - nonPromoAvg;
  const lift =
    row.lift_pct === null || row.lift_pct === undefined || row.lift_pct === ''
      ? nonPromoAvg > 0
        ? incremental / nonPromoAvg
        : null
      : toNumber(row.lift_pct);

  return {
    promo_period_id: row.promo_period_id,
    promo_period_name: row.promo_period_name || 'Loyalty Promo',
    promo_start_date: row.promo_start_date,
    promo_end_date: row.promo_end_date,
    promo_day_count: toNumber(row.promo_day_count),
    non_promo_start_date: row.non_promo_start_date,
    non_promo_end_date: row.non_promo_end_date,
    non_promo_day_count: toNumber(row.non_promo_day_count),
    brand_catalog: row.brand_catalog || 'Wayfair US',
    supplier_id: row.supplier_id,
    supplier_name: row.supplier_name || 'Unknown Supplier',
    srm: row.srm || '',
    sku: row.sku,
    class_name: row.class_name || 'Unknown Class',
    marketing_category: row.marketing_category || 'Bedding',
    discount_pct: toNumber(row.discount_pct),
    rec_discount_pct: toNumber(row.rec_discount_pct),
    b2b_discount_pct: toNumber(row.b2b_discount_pct),
    wsc_rev_l12m: toNumber(row.wsc_rev_l12m),
    grs_l12m: toNumber(row.grs_l12m),
    participating_part_count: toNumber(row.participating_part_count),
    non_promo_avg: nonPromoAvg,
    loyalty_avg: loyaltyAvg,
    incremental_sales: round(incremental, 2),
    lift_pct: lift === null ? null : round(lift, 4),
    discount_bucket: discountBucket(row.discount_pct),
    active_on_event: loyaltyAvg > 0,
    positive_lift: incremental > 0,
  };
});

const baselines = skuData
  .map((row) => row.non_promo_avg)
  .filter((value) => value > 0)
  .sort((a, b) => a - b);
const q1 = quantile(baselines, 0.25);
const q2 = quantile(baselines, 0.5);
const q3 = quantile(baselines, 0.75);

for (const row of skuData) {
  if (row.non_promo_avg <= 0) {
    row.baseline_success_tier = 'No baseline';
  } else if (row.non_promo_avg <= q1) {
    row.baseline_success_tier = 'Low baseline';
  } else if (row.non_promo_avg <= q2) {
    row.baseline_success_tier = 'Mid-low baseline';
  } else if (row.non_promo_avg <= q3) {
    row.baseline_success_tier = 'Mid-high baseline';
  } else {
    row.baseline_success_tier = 'High baseline';
  }
}

const categorySummary = summarize(
  skuData,
  (row) => ({ marketing_category: row.marketing_category }),
  ['marketing_category'],
);
const classSummary = summarize(skuData, (row) => ({ class_name: row.class_name }), ['class_name']);
const supplierSummary = summarize(
  skuData,
  (row) => ({
    supplier_id: row.supplier_id,
    supplier_name: row.supplier_name,
    srm: row.srm,
  }),
  ['supplier_id', 'supplier_name', 'srm'],
);
const discountSummary = summarize(
  skuData,
  (row) => ({ discount_bucket: row.discount_bucket }),
  ['discount_bucket'],
).sort((a, b) => {
  const order = ['<10%', '10-14.9%', '15-19.9%', '20-24.9%', '25%+'];
  return order.indexOf(a.discount_bucket) - order.indexOf(b.discount_bucket);
});
const baselineTier = ['Low baseline', 'Mid-low baseline', 'Mid-high baseline', 'High baseline'];
const baselineSummary = summarize(
  skuData.filter((row) => baselineTier.includes(row.baseline_success_tier)),
  (row) => ({ baseline_success_tier: row.baseline_success_tier }),
  ['baseline_success_tier'],
).sort(
  (a, b) =>
    baselineTier.indexOf(a.baseline_success_tier) - baselineTier.indexOf(b.baseline_success_tier),
);

const totalNonPromo = skuData.reduce((sum, row) => sum + row.non_promo_avg, 0);
const totalLoyalty = skuData.reduce((sum, row) => sum + row.loyalty_avg, 0);
const totalIncremental = totalLoyalty - totalNonPromo;
const totalLift = totalNonPromo ? totalIncremental / totalNonPromo : null;
const activeSkus = skuData.filter((row) => row.active_on_event).length;
const positiveSkus = skuData.filter((row) => row.positive_lift).length;
const weightedDiscount = weightedAvg(
  skuData.map((row) => row.discount_pct),
  skuData.map((row) => row.non_promo_avg),
);
const bestClass = [...classSummary]
  .filter((row) => row.weighted_lift_pct !== null)
  .sort((a, b) => b.weighted_lift_pct - a.weighted_lift_pct)[0];
const biggestClass = [...classSummary].sort((a, b) => b.loyalty_avg - a.loyalty_avg)[0];
const bestSupplier = [...supplierSummary]
  .filter((row) => row.incremental_sales > 0)
  .sort((a, b) => b.incremental_sales - a.incremental_sales)[0];
const highTier = baselineSummary.find((row) => row.baseline_success_tier === 'High baseline');
const lowTier = baselineSummary.find((row) => row.baseline_success_tier === 'Low baseline');
const meta = skuData[0];
const eventName = meta.promo_period_name || 'Bedding Loyalty Promo';

const classTable = formatSummaryRows(classSummary);
const supplierTable = formatSummaryRows(
  [...supplierSummary].sort((a, b) => b.incremental_sales - a.incremental_sales).slice(0, 15),
);
const discountTable = formatSummaryRows(discountSummary);
const tierTable = formatSummaryRows(baselineSummary);
const categoryTable = formatSummaryRows(categorySummary);

const markdown = `# ${eventName} Performance Case Study

## Executive takeaway

The Bedding loyalty file generated **${fmtCurrency(totalLoyalty)}** in loyalty sales versus a recent non-promo average of **${fmtCurrency(totalNonPromo)}**, creating **${fmtCurrency(totalIncremental)} in incremental sales** and **${fmtPct(totalLift)} weighted lift**.

## What changed during the event

- **Overall lift:** ${fmtPct(totalLift)}
- **Incremental sales:** ${fmtCurrency(totalIncremental)}
- **Participation breadth:** ${activeSkus} of ${skuData.length} participating SKUs recorded loyalty sales; ${positiveSkus} SKUs generated positive incremental dollars.
- **Weighted supplier investment:** ${fmtPct(weightedDiscount)} average discount, weighted by non-promo average.
- **Best class by lift:** ${bestClass ? `${bestClass.class_name} at ${fmtPct(bestClass.weighted_lift_pct)}` : 'n/a'}.
- **Largest class by loyalty sales:** ${biggestClass ? `${biggestClass.class_name} with ${fmtCurrency(biggestClass.loyalty_avg)}` : 'n/a'}.
- **Promo window:** ${meta.promo_start_date} to ${meta.promo_end_date} (${meta.promo_day_count} day(s)).
- **L10 non-promo baseline:** ${meta.non_promo_day_count} day(s) from ${meta.non_promo_start_date} to ${meta.non_promo_end_date}.

## Are normally successful SKUs performing better or worse?

Using each SKU's non-promo average as a proxy for normal/historical success, high-baseline SKUs delivered **${fmtPct(highTier?.weighted_lift_pct)} weighted lift**, while low-baseline SKUs delivered **${fmtPct(lowTier?.weighted_lift_pct)} weighted lift**.

${markdownTable(tierTable, [
  'baseline_success_tier',
  'sku_count',
  'active_skus',
  'positive_lift_sku_rate',
  'weighted_discount_pct',
  'non_promo_avg',
  'loyalty_avg',
  'incremental_sales',
  'weighted_lift_pct',
])}

## Category-level insights

${markdownTable(categoryTable, [
  'marketing_category',
  'sku_count',
  'active_skus',
  'positive_lift_sku_rate',
  'weighted_discount_pct',
  'non_promo_avg',
  'loyalty_avg',
  'incremental_sales',
  'weighted_lift_pct',
])}

## Class-level insights

${markdownTable(classTable, [
  'class_name',
  'sku_count',
  'active_skus',
  'positive_lift_sku_rate',
  'weighted_discount_pct',
  'non_promo_avg',
  'loyalty_avg',
  'incremental_sales',
  'weighted_lift_pct',
])}

## Promotional investment vs. lift

${markdownTable(discountTable, [
  'discount_bucket',
  'sku_count',
  'weighted_discount_pct',
  'non_promo_avg',
  'loyalty_avg',
  'incremental_sales',
  'weighted_lift_pct',
])}

## Supplier-level insights

${markdownTable(supplierTable, [
  'supplier_name',
  'sku_count',
  'active_skus',
  'positive_lift_sku_rate',
  'weighted_discount_pct',
  'non_promo_avg',
  'loyalty_avg',
  'incremental_sales',
  'weighted_lift_pct',
])}

## Supplier success stories

The largest incremental supplier win was **${bestSupplier ? bestSupplier.supplier_name : 'n/a'}**, with **${bestSupplier ? fmtCurrency(bestSupplier.incremental_sales) : 'n/a'}** in incremental sales and **${bestSupplier ? fmtPct(bestSupplier.weighted_lift_pct) : 'n/a'}** weighted lift.
`;

const emailHtml = `
<html>
  <body style="font-family:Arial,sans-serif;color:#222;line-height:1.45;">
    <h2 style="margin-bottom:4px;">${escapeHtml(eventName)} Performance Case Study</h2>
    <p style="color:#666;margin-top:0;">Bedding marketing category · Promo ${escapeHtml(meta.promo_period_id)} · ${escapeHtml(meta.promo_start_date)} to ${escapeHtml(meta.promo_end_date)}</p>
    <p>The Bedding loyalty file generated <strong>${escapeHtml(fmtCurrency(totalLoyalty))}</strong> in loyalty sales versus a recent non-promo average of <strong>${escapeHtml(fmtCurrency(totalNonPromo))}</strong>, creating <strong>${escapeHtml(fmtCurrency(totalIncremental))}</strong> in incremental sales and <strong>${escapeHtml(fmtPct(totalLift))}</strong> weighted lift.</p>
    <ul>
      <li><strong>Participation:</strong> ${activeSkus} of ${skuData.length} SKUs recorded loyalty sales; ${positiveSkus} had positive incremental dollars.</li>
      <li><strong>Weighted discount:</strong> ${escapeHtml(fmtPct(weightedDiscount))}</li>
      <li><strong>Best class by lift:</strong> ${escapeHtml(bestClass ? `${bestClass.class_name} (${fmtPct(bestClass.weighted_lift_pct)})` : 'n/a')}</li>
      <li><strong>Top incremental supplier:</strong> ${escapeHtml(bestSupplier ? `${bestSupplier.supplier_name} (${fmtCurrency(bestSupplier.incremental_sales)})` : 'n/a')}</li>
      <li><strong>L10 non-promo baseline:</strong> ${escapeHtml(String(meta.non_promo_day_count))} day(s) from ${escapeHtml(meta.non_promo_start_date)} to ${escapeHtml(meta.non_promo_end_date)}</li>
    </ul>
    <h3>Class-level insights</h3>
    ${htmlTable(classTable, ['class_name', 'sku_count', 'active_skus', 'weighted_discount_pct', 'non_promo_avg', 'loyalty_avg', 'incremental_sales', 'weighted_lift_pct'])}
    <h3>Top suppliers by incremental sales</h3>
    ${htmlTable(supplierTable, ['supplier_name', 'sku_count', 'active_skus', 'weighted_discount_pct', 'non_promo_avg', 'loyalty_avg', 'incremental_sales', 'weighted_lift_pct'])}
    <h3>Discount investment vs. lift</h3>
    ${htmlTable(discountTable, ['discount_bucket', 'sku_count', 'weighted_discount_pct', 'non_promo_avg', 'loyalty_avg', 'incremental_sales', 'weighted_lift_pct'])}
    <p style="color:#666;font-size:12px;margin-top:24px;">Generated by Bedding Member Monday Loyalty Lift n8n workflow.</p>
  </body>
</html>
`;

const sheetRows = [];

function pushSheetRows(sheetName, records) {
  for (const record of records) {
    sheetRows.push({
      sheet_name: sheetName,
      ...record,
    });
  }
}

pushSheetRows(
  'SKU Data',
  skuData.map((row) => ({
    promo_period_id: row.promo_period_id,
    promo_period_name: row.promo_period_name,
    brand_catalog: row.brand_catalog,
    supplier_id: row.supplier_id,
    supplier_name: row.supplier_name,
    srm: row.srm,
    sku: row.sku,
    class_name: row.class_name,
    marketing_category: row.marketing_category,
    discount_pct: row.discount_pct,
    non_promo_avg: row.non_promo_avg,
    loyalty_avg: row.loyalty_avg,
    incremental_sales: row.incremental_sales,
    lift_pct: row.lift_pct,
    discount_bucket: row.discount_bucket,
    baseline_success_tier: row.baseline_success_tier,
  })),
);
pushSheetRows('Category Summary', categorySummary);
pushSheetRows('Class Summary', classSummary);
pushSheetRows('Supplier Summary', supplierSummary);
pushSheetRows('Discount Buckets', discountSummary);
pushSheetRows('Baseline Tiers', baselineSummary);

return [
  {
    json: {
      subject: `[Bedding Loyalty Lift] ${eventName}: ${fmtPct(totalLift)} weighted lift / ${fmtCurrency(totalIncremental)} incremental`,
      emailHtml,
      markdown,
      spreadsheetTitle: `Bedding Loyalty Lift - ${eventName} - ${meta.promo_start_date || new Date().toISOString().slice(0, 10)}`,
      sheet_rows: sheetRows,
      sku_data: skuData,
      category_summary: categorySummary,
      class_summary: classSummary,
      supplier_summary: supplierSummary,
      discount_summary: discountSummary,
      baseline_summary: baselineSummary,
      summary: {
        event_name: eventName,
        promo_period_id: meta.promo_period_id,
        sku_count: skuData.length,
        active_skus: activeSkus,
        positive_lift_skus: positiveSkus,
        non_promo_avg: round(totalNonPromo, 2),
        loyalty_avg: round(totalLoyalty, 2),
        incremental_sales: round(totalIncremental, 2),
        weighted_lift_pct: totalLift === null ? null : round(totalLift, 4),
        weighted_discount_pct: weightedDiscount === null ? null : round(weightedDiscount, 4),
      },
    },
  },
];
