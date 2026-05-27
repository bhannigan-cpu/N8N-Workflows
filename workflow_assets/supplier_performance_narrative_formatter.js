const data = $input.first().json;

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function toNumber(value) {
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
}

function escapeHtml(value) {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function money(value) {
  const num = toNumber(value);
  if (num === null) return "N/A";
  return "$" + num.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  });
}

function number(value) {
  const num = toNumber(value);
  if (num === null) return "N/A";
  return num.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  });
}

function percent(value) {
  const num = toNumber(value);
  if (num === null) return "N/A";
  return (num * 100).toFixed(2) + "%";
}

function signedPercent(value) {
  const num = toNumber(value);
  if (num === null) return "N/A";
  const scaled = num * 100;
  const sign = scaled > 0 ? "+" : "";
  return sign + scaled.toFixed(1) + "%";
}

function signedBps(value) {
  const num = toNumber(value);
  if (num === null) return "N/A";
  const scaled = num * 10000;
  const sign = scaled > 0 ? "+" : "";
  return sign + scaled.toFixed(0) + " bps";
}

function supplierKey(row) {
  if (!row) return "";
  return String(row.supplier_id || row.supplier_name || "");
}

function supplierName(row) {
  if (!row || !row.supplier_name) return "Unknown supplier";
  return String(row.supplier_name);
}

function topGrsSupplierKeys(rows) {
  return new Set(asArray(rows).map(function(row) {
    return supplierKey(row);
  }));
}

function prioritySort(rows, metricKey, direction, preferredSupplierKeys) {
  return asArray(rows)
    .filter(function(row) {
      return toNumber(row[metricKey]) !== null;
    })
    .slice()
    .sort(function(left, right) {
      const leftPreferred = preferredSupplierKeys.has(supplierKey(left)) ? 1 : 0;
      const rightPreferred = preferredSupplierKeys.has(supplierKey(right)) ? 1 : 0;

      if (leftPreferred !== rightPreferred) {
        return rightPreferred - leftPreferred;
      }

      const leftValue = toNumber(left[metricKey]);
      const rightValue = toNumber(right[metricKey]);
      return direction === "asc" ? leftValue - rightValue : rightValue - leftValue;
    });
}

function createActionItems(payload) {
  const preferredSupplierKeys = topGrsSupplierKeys(payload.topCurrentGrs);
  const suggestions = [];
  const usedKeys = new Set();

  function addSuggestion(kind, row, builder) {
    if (!row) return;
    const dedupeKey = `${kind}:${supplierKey(row)}`;
    if (usedKeys.has(dedupeKey)) return;

    const message = builder(row);
    if (!message) return;

    usedKeys.add(dedupeKey);
    suggestions.push(message);
  }

  addSuggestion("availability-drop", prioritySort(
    payload.bottomWowAvailabilityMovers,
    "wow_availability_change",
    "asc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Reach out to ${supplierName(row)} about inventory issues after availability moved ${signedBps(row.wow_availability_change)} WoW to ${percent(row.current_availability)}.`;
  });

  addSuggestion("low-availability", prioritySort(
    asArray(payload.topCurrentGrs).concat(asArray(payload.bottomAvailability)),
    "current_availability",
    "asc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Pressure-test replenishment plans with ${supplierName(row)} because availability is only ${percent(row.current_availability)} on ${money(row.current_grs)} in current GRS.`;
  });

  addSuggestion("mrpi-increase", prioritySort(
    payload.topMrpiMovers,
    "wow_mrpi_change",
    "desc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Check in with ${supplierName(row)} about recent price increases after MRPI rose ${signedBps(row.wow_mrpi_change)} WoW.`;
  });

  addSuggestion("wsi-increase", prioritySort(
    payload.topWsiMovers,
    "wow_wsi_change",
    "desc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Review pricing competitiveness with ${supplierName(row)} because WSI increased ${signedBps(row.wow_wsi_change)} WoW.`;
  });

  addSuggestion("visits-drop", prioritySort(
    payload.bottomYoyMoversVisits,
    "yoy_visits_pct_change",
    "asc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Investigate traffic softness with ${supplierName(row)} after visits declined ${signedPercent(row.yoy_visits_pct_change)} YoY.`;
  });

  addSuggestion("cvr-drop", prioritySort(
    payload.bottomYoyMoversCvr,
    "yoy_cvr_pct_change",
    "asc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Audit PDP quality and promo support with ${supplierName(row)} because CVR is down ${signedPercent(row.yoy_cvr_pct_change)} YoY.`;
  });

  addSuggestion("share-loss", prioritySort(
    asArray(payload.topCurrentGrs).filter(function(row) {
      const value = toNumber(row.share_yoy_pct_change);
      return value !== null && value < 0;
    }),
    "share_yoy_pct_change",
    "asc",
    preferredSupplierKeys
  )[0], function(row) {
    return `Review share pressure with ${supplierName(row)} because share is down ${signedPercent(row.share_yoy_pct_change)} YoY while current GRS is ${money(row.current_grs)}.`;
  });

  return suggestions.slice(0, 6);
}

function safeGap(current, benchmark, multiplier) {
  const currentNum = toNumber(current);
  const benchmarkNum = toNumber(benchmark);
  if (currentNum === null || benchmarkNum === null) return 0;
  return (benchmarkNum - currentNum) * multiplier;
}

function safeExcess(current, benchmark, multiplier) {
  const currentNum = toNumber(current);
  const benchmarkNum = toNumber(benchmark);
  if (currentNum === null || benchmarkNum === null) return 0;
  return (currentNum - benchmarkNum) * multiplier;
}

function supplierIssueScore(row, benchmark) {
  let score = 0;
  score += Math.max(0, safeGap(row.wow_grs_pct, benchmark.wow_grs_pct, 120));
  score += Math.max(0, safeGap(row.yoy_grs_pct, benchmark.yoy_grs_pct, 90));
  score += Math.max(0, safeGap(row.wow_visits_pct_change, benchmark.wow_visits_pct_change, 80));
  score += Math.max(0, safeGap(row.yoy_visits_pct_change, benchmark.yoy_visits_pct_change, 70));
  score += Math.max(0, safeGap(row.current_cvr, benchmark.current_cvr, 7000));
  score += Math.max(0, safeGap(row.current_availability, benchmark.current_availability, 5000));
  score += Math.max(0, (toNumber(row.wow_availability_change) || 0) * -3500);
  score += Math.max(0, safeExcess(row.current_mrpi, benchmark.current_mrpi, 7000));
  score += Math.max(0, safeExcess(row.current_wsi, benchmark.current_wsi, 7000));
  score += Math.max(0, safeExcess(row.wow_wsc_pct_change, benchmark.wow_wsc_pct_change, 40));
  score += Math.max(0, safeExcess(row.yoy_wsc_pct_change, benchmark.yoy_wsc_pct_change, 30));
  score += Math.max(0, (toNumber(row.grs_share) || 0) * 20);
  return score;
}

function pickPrioritySuppliers(rows, benchmark, limit) {
  const ranked = asArray(rows).map(function(row) {
    return {
      row: row,
      score: supplierIssueScore(row, benchmark)
    };
  }).sort(function(left, right) {
    if (right.score !== left.score) return right.score - left.score;
    return (toNumber(right.row.current_grs) || 0) - (toNumber(left.row.current_grs) || 0);
  });

  const selected = ranked.filter(function(entry) {
    return entry.score > 0;
  }).slice(0, limit).map(function(entry) {
    return entry.row;
  });

  if (selected.length) return selected;

  return asArray(rows)
    .slice()
    .sort(function(left, right) {
      return (toNumber(right.current_grs) || 0) - (toNumber(left.current_grs) || 0);
    })
    .slice(0, limit);
}

function hashString(value) {
  return String(value || "").split("").reduce(function(acc, char) {
    return (acc * 31 + char.charCodeAt(0)) >>> 0;
  }, 7);
}

function chooseVariant(seed, options) {
  if (!options.length) return "";
  return options[seed % options.length];
}

function gapPercentPoints(current, benchmark) {
  const currentNum = toNumber(current);
  const benchmarkNum = toNumber(benchmark);
  if (currentNum === null || benchmarkNum === null) return null;
  return (benchmarkNum - currentNum) * 100;
}

function gapBps(current, benchmark) {
  const currentNum = toNumber(current);
  const benchmarkNum = toNumber(benchmark);
  if (currentNum === null || benchmarkNum === null) return null;
  return (benchmarkNum - currentNum) * 10000;
}

function addFinding(findings, type, score, text) {
  if (!Number.isFinite(score) || score <= 0 || !text) return;
  findings.push({ type: type, score: score, text: text });
}

function openingSentence(row, topFindingType) {
  const seed = hashString(supplierName(row));
  const name = supplierName(row);
  const optionsByType = {
    sales: [
      `${name} looks like a sales-momentum story this week.`,
      `The topline is the first thing that stands out for ${name} this week.`,
      `${name} is showing real pressure in the sales trend right now.`
    ],
    traffic: [
      `Traffic is the clearest headwind for ${name} right now.`,
      `${name} mainly looks like a traffic issue this week.`,
      `The top-of-funnel is where ${name} looks weakest this week.`
    ],
    conversion: [
      `Conversion is the biggest watchout for ${name} this week.`,
      `${name} is getting hurt most by conversion efficiency right now.`,
      `The clearest drag for ${name} this week is lower conversion.`
    ],
    availability: [
      `Inventory looks like the biggest blocker for ${name} right now.`,
      `${name} still looks supply-constrained this week.`,
      `Availability is the first operational issue I would flag for ${name}.`
    ],
    pricing: [
      `Pricing competitiveness is the first thing I would watch for ${name}.`,
      `${name} looks like a pricing conversation this week.`,
      `The biggest strategic watchout for ${name} right now is pricing.`
    ],
    cost: [
      `WSC pressure is standing out for ${name} this week.`,
      `${name} looks like a cost-inflation watchout right now.`,
      `The cost side is worth watching closely for ${name} this week.`
    ],
    balanced: [
      `${name} looks mixed this week, with a couple of metrics moving in different directions.`,
      `${name} has a more balanced read this week than some of the other pressured suppliers.`,
      `The picture for ${name} is mixed rather than driven by one single issue.`
    ]
  };

  const options = optionsByType[topFindingType] || optionsByType.balanced;
  return chooseVariant(seed, options);
}

function buildSupplierSummary(row, benchmark) {
  const findings = [];
  const positives = [];

  const salesWowGap = gapPercentPoints(row.wow_grs_pct, benchmark.wow_grs_pct);
  const salesYoyGap = gapPercentPoints(row.yoy_grs_pct, benchmark.yoy_grs_pct);
  if ((salesWowGap !== null && salesWowGap > 2) || (salesYoyGap !== null && salesYoyGap > 4)) {
    addFinding(
      findings,
      "sales",
      Math.max(salesWowGap || 0, salesYoyGap || 0),
      `Sales are running ${signedPercent(row.wow_grs_pct)} WoW versus ${signedPercent(benchmark.wow_grs_pct)} for benchmark, and ${signedPercent(row.yoy_grs_pct)} YoY versus ${signedPercent(benchmark.yoy_grs_pct)}.`
    );
  } else if ((toNumber(row.wow_grs_pct) || 0) >= (toNumber(benchmark.wow_grs_pct) || 0) &&
             (toNumber(row.yoy_grs_pct) || 0) >= (toNumber(benchmark.yoy_grs_pct) || 0)) {
    positives.push(`Sales are holding up at or above benchmark on both WoW and YoY views.`);
  }

  const visitsWowGap = gapPercentPoints(row.wow_visits_pct_change, benchmark.wow_visits_pct_change);
  const visitsYoyGap = gapPercentPoints(row.yoy_visits_pct_change, benchmark.yoy_visits_pct_change);
  if ((visitsWowGap !== null && visitsWowGap > 2) || (visitsYoyGap !== null && visitsYoyGap > 3)) {
    addFinding(
      findings,
      "traffic",
      Math.max(visitsWowGap || 0, visitsYoyGap || 0),
      `Traffic is softer than the category: visits are ${signedPercent(row.wow_visits_pct_change)} WoW and ${signedPercent(row.yoy_visits_pct_change)} YoY, versus ${signedPercent(benchmark.wow_visits_pct_change)} WoW and ${signedPercent(benchmark.yoy_visits_pct_change)} YoY for benchmark.`
    );
  } else if ((toNumber(row.wow_visits_pct_change) || 0) >= (toNumber(benchmark.wow_visits_pct_change) || 0)) {
    positives.push(`Traffic is at least holding up versus the benchmark on the weekly view.`);
  }

  const cvrGap = gapBps(row.current_cvr, benchmark.current_cvr);
  if (cvrGap !== null && cvrGap > 12) {
    addFinding(
      findings,
      "conversion",
      cvrGap,
      `Conversion is ${percent(row.current_cvr)} versus ${percent(benchmark.current_cvr)} for benchmark, so the PDP / promo / assortment story likely matters here.`
    );
  } else if ((toNumber(row.current_cvr) || 0) >= (toNumber(benchmark.current_cvr) || 0)) {
    positives.push(`Conversion is at or above benchmark, so the issue does not look conversion-led right now.`);
  }

  const availabilityGap = gapBps(row.current_availability, benchmark.current_availability);
  const availabilityMove = toNumber(row.wow_availability_change) || 0;
  if ((availabilityGap !== null && availabilityGap > 150) || availabilityMove < -0.005) {
    addFinding(
      findings,
      "availability",
      Math.max(availabilityGap || 0, Math.abs(availabilityMove) * 10000),
      `Availability is ${percent(row.current_availability)} versus ${percent(benchmark.current_availability)} for benchmark, and it moved ${signedBps(row.wow_availability_change)} WoW.`
    );
  } else if ((toNumber(row.current_availability) || 0) >= (toNumber(benchmark.current_availability) || 0)) {
    positives.push(`Availability is not the binding constraint this week because it is in line with or above the benchmark.`);
  }

  const mrpiGap = gapBps(benchmark.current_mrpi, row.current_mrpi);
  const wsiGap = gapBps(benchmark.current_wsi, row.current_wsi);
  if ((mrpiGap !== null && mrpiGap > 25) || (wsiGap !== null && wsiGap > 25)) {
    addFinding(
      findings,
      "pricing",
      Math.max(mrpiGap || 0, wsiGap || 0),
      `Pricing looks heavier than benchmark: MRPI is ${percent(row.current_mrpi)} versus ${percent(benchmark.current_mrpi)}, and WSI is ${percent(row.current_wsi)} versus ${percent(benchmark.current_wsi)}.`
    );
  } else if ((toNumber(row.current_mrpi) || 0) <= (toNumber(benchmark.current_mrpi) || 0) &&
             (toNumber(row.current_wsi) || 0) <= (toNumber(benchmark.current_wsi) || 0)) {
    positives.push(`Pricing does not look like the main issue because MRPI and WSI are roughly in line with or better than benchmark.`);
  }

  const wscWowGap = gapPercentPoints(benchmark.wow_wsc_pct_change, row.wow_wsc_pct_change);
  const wscYoyGap = gapPercentPoints(benchmark.yoy_wsc_pct_change, row.yoy_wsc_pct_change);
  if ((wscWowGap !== null && wscWowGap > 2) || (wscYoyGap !== null && wscYoyGap > 3)) {
    addFinding(
      findings,
      "cost",
      Math.max(wscWowGap || 0, wscYoyGap || 0),
      `WSC is moving faster than the category: ${signedPercent(row.wow_wsc_pct_change)} WoW and ${signedPercent(row.yoy_wsc_pct_change)} YoY versus ${signedPercent(benchmark.wow_wsc_pct_change)} and ${signedPercent(benchmark.yoy_wsc_pct_change)} for benchmark.`
    );
  }

  findings.sort(function(left, right) {
    return right.score - left.score;
  });

  const primaryType = findings.length ? findings[0].type : "balanced";
  const sentences = [openingSentence(row, primaryType)];

  findings.slice(0, 3).forEach(function(finding) {
    sentences.push(finding.text);
  });

  if (positives.length) {
    sentences.push(positives[0]);
  } else if (!findings.length) {
    sentences.push(`Nothing is flashing red here relative to benchmark, and the account still represents ${percent(row.grs_share)} of weekly GRS.`);
  }

  return sentences.join(" ");
}

function renderSupplierCard(row, benchmark) {
  return `
    <div class="supplier-card">
      <h3>${escapeHtml(supplierName(row))}</h3>
      <p><strong>Sales:</strong> (GRS: ${money(row.current_grs)}, ${percent(row.grs_share)} Share) (${signedPercent(row.wow_grs_pct)} WoW, ${signedPercent(row.yoy_grs_pct)} YoY, Benchmark: ${signedPercent(benchmark.wow_grs_pct)} WoW, ${signedPercent(benchmark.yoy_grs_pct)} YoY)</p>
      <p><strong>WSC:</strong> ${money(row.current_wsc)} (${signedPercent(row.wow_wsc_pct_change)} WoW, ${signedPercent(row.yoy_wsc_pct_change)} YoY, Benchmark: ${signedPercent(benchmark.wow_wsc_pct_change)} WoW, ${signedPercent(benchmark.yoy_wsc_pct_change)} YoY)</p>
      <p><strong>Visits:</strong> ${number(row.current_visits)} (${signedPercent(row.wow_visits_pct_change)} WoW, ${signedPercent(row.yoy_visits_pct_change)} YoY, Benchmark: ${signedPercent(benchmark.wow_visits_pct_change)} WoW, ${signedPercent(benchmark.yoy_visits_pct_change)} YoY)</p>
      <p><strong>Conversion:</strong> ${percent(row.current_cvr)}, Benchmark: ${percent(benchmark.current_cvr)}</p>
      <p><strong>28D WSI:</strong> ${percent(row.current_wsi)}, Benchmark: ${percent(benchmark.current_wsi)}</p>
      <p><strong>28D MRPI:</strong> ${percent(row.current_mrpi)}, Benchmark: ${percent(benchmark.current_mrpi)}</p>
      <p><strong>Availability:</strong> ${percent(row.current_availability)} (${signedBps(row.wow_availability_change)} WoW, Benchmark: ${percent(benchmark.current_availability)})</p>
      <p class="supplier-summary">${escapeHtml(buildSupplierSummary(row, benchmark))}</p>
    </div>
  `;
}

const benchmark = asArray(data.topCurrentGrsBenchmark)[0] || {};
const prioritySuppliers = pickPrioritySuppliers(data.topCurrentGrs, benchmark, 5);
const actionItems = createActionItems(data);

const supplierHtml = prioritySuppliers.map(function(row) {
  return renderSupplierCard(row, benchmark);
}).join("");

const actionItemHtml = actionItems.length
  ? `<ol>${actionItems.map(function(item) {
      return `<li>${escapeHtml(item)}</li>`;
    }).join("")}</ol>`
  : "<p>No major action items were generated for this week's movers.</p>";

const currentWeekLabel = benchmark.current_week_label || "Current Week";
const indexDateLabel = benchmark.wsi_index_date_label || "04/02/25";
const subentityLabel = benchmark.subentity_label || "All Subentities";
const storeLabel = benchmark.store_label || "All Stores";

const htmlBody = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: Arial, sans-serif;
      color: #1f2937;
      line-height: 1.45;
      font-size: 13px;
      margin: 0;
      padding: 16px;
    }

    h1 {
      font-size: 22px;
      margin: 0 0 6px 0;
      color: #1f4e79;
    }

    h2 {
      font-size: 17px;
      margin: 20px 0 8px 0;
      color: #1f4e79;
      border-bottom: 2px solid #d7e3f4;
      padding-bottom: 4px;
    }

    h3 {
      font-size: 16px;
      margin: 0 0 8px 0;
      color: #0f3b63;
    }

    p {
      margin: 6px 0;
    }

    .subtitle {
      color: #4b5563;
      margin-bottom: 12px;
    }

    .supplier-card {
      border: 1px solid #d7e3f4;
      border-radius: 8px;
      padding: 14px 16px;
      margin: 0 0 14px 0;
      background: #fbfdff;
    }

    .supplier-summary {
      margin-top: 10px;
      color: #374151;
    }

    ol {
      margin: 8px 0 0 18px;
      padding: 0;
    }

    li {
      margin-bottom: 8px;
    }
  </style>
</head>
<body>
  <h1>Supplier Performance <em>*${escapeHtml(indexDateLabel)} index date*</em></h1>
  <p class="subtitle">Subentity: ${escapeHtml(subentityLabel)}, Store: ${escapeHtml(storeLabel)}</p>

  <h2>Weekly Performance</h2>
  <p><strong>W/O ${escapeHtml(currentWeekLabel)}</strong></p>

  ${supplierHtml || "<p>No supplier performance rows were available.</p>"}

  <h2>Weekly Action Items</h2>
  ${actionItemHtml}
</body>
</html>
`;

return [
  {
    json: {
      htmlBody: htmlBody
    }
  }
];
