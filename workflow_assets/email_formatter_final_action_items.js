const data = $input.first().json;

function money(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";
  return "$" + Number(value).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  });
}

function number(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";
  return Number(value).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  });
}

function percent(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";
  return (Number(value) * 100).toFixed(1) + "%";
}

function signedPercent(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";
  const num = Number(value) * 100;
  const sign = num > 0 ? "+" : "";
  return sign + num.toFixed(1) + "%";
}

function bps(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";
  const num = Number(value) * 10000;
  const sign = num > 0 ? "+" : "";
  return sign + num.toFixed(0) + " bps";
}

function isChangeKey(key) {
  return key.includes("change") || key === "wow_grs_pct" || key === "yoy_grs_pct";
}

function isReverseScaleKey(key) {
  return key.includes("mrpi") || key.includes("wsi");
}

function escapeHtml(value) {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function mixChannel(start, end, ratio) {
  return Math.round(start + (end - start) * ratio);
}

function buildRgb(start, end, ratio) {
  return `rgb(${mixChannel(start[0], end[0], ratio)}, ${mixChannel(start[1], end[1], ratio)}, ${mixChannel(start[2], end[2], ratio)})`;
}

function toNumber(value) {
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function supplierKey(row) {
  if (!row) return "";
  return String(row.supplier_id || row.supplier_name || "");
}

function supplierName(row) {
  if (!row || !row.supplier_name) return "the supplier";
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

function scaleReference(key, rows) {
  const numericValues = rows
    .map(function(row) {
      const value = toNumber(row[key]);
      return value === null ? null : Math.abs(value);
    })
    .filter(function(value) {
      return value !== null;
    });

  const observedMax = numericValues.length ? Math.max.apply(null, numericValues) : 0;

  if (key.includes("pct") || (!key.includes("grs") && !key.includes("visits") && key.includes("change"))) {
    return Math.max(observedMax, 0.2);
  }

  return Math.max(observedMax, 1);
}

function computeHeatmapStyles(rows, columns) {
  const styles = {};

  columns.forEach(function(column) {
    if (!isChangeKey(column.key)) return;
    styles[column.key] = {
      reference: scaleReference(column.key, rows)
    };
  });

  return styles;
}

function getCellStyle(row, key, heatmapStyles) {
  if (!isChangeKey(key) || !heatmapStyles[key]) return "";

  const value = toNumber(row[key]);
  if (value === null || value === 0) {
    return "background-color: rgb(255, 255, 255);";
  }

  const ratio = clamp(Math.abs(value) / heatmapStyles[key].reference, 0, 1);
  const easedRatio = Math.pow(ratio, 0.75);
  const positiveColor = [34, 197, 94];
  const negativeColor = [239, 68, 68];
  const neutral = [255, 255, 255];
  const useReverseScale = isReverseScaleKey(key);
  const target = value > 0
    ? (useReverseScale ? negativeColor : positiveColor)
    : (useReverseScale ? positiveColor : negativeColor);
  const background = buildRgb(neutral, target, easedRatio);
  const textColor = value > 0
    ? (useReverseScale ? "rgb(127, 29, 29)" : "rgb(20, 83, 45)")
    : (useReverseScale ? "rgb(20, 83, 45)" : "rgb(127, 29, 29)");

  return `background-color: ${background}; color: ${textColor}; font-weight: 600;`;
}

function formatCell(row, key) {
  const value = row[key];

  if (key.includes("pct")) return percent(value);

  if (key.includes("change")) {
    if (key.includes("grs")) return money(value);
    if (key.includes("visits")) return number(value);
    if (key.includes("mrpi") || key.includes("wsi")) return bps(value);
    return percent(value);
  }

  if (key.includes("share")) return percent(value);
  if (key.includes("cvr")) return percent(value);
  if (key.includes("availability")) return percent(value);
  if (key.includes("wsc")) return money(value);
  if (key.includes("mrpi")) return percent(value);
  if (key.includes("wsi")) return percent(value);

  if (key.includes("grs")) return money(value);
  if (key.includes("visits")) return number(value);

  return escapeHtml(value);
}

function makeTable(title, rows, columns) {
  if (!Array.isArray(rows) || rows.length === 0) {
    return `
      <h2>${escapeHtml(title)}</h2>
      <p><em>No results found.</em></p>
    `;
  }

  const headerHtml = columns.map(function(col) {
    return `<th>${escapeHtml(col.label)}</th>`;
  }).join("");

  const heatmapStyles = computeHeatmapStyles(rows, columns);

  const bodyHtml = rows.map(function(row) {
    const cells = columns.map(function(col) {
      const style = getCellStyle(row, col.key, heatmapStyles);
      const styleAttribute = style ? ` style="${style}"` : "";
      return `<td${styleAttribute}>${formatCell(row, col.key)}</td>`;
    }).join("");

    return `<tr>${cells}</tr>`;
  }).join("");

  return `
    <h2>${escapeHtml(title)}</h2>
    <table>
      <thead>
        <tr>${headerHtml}</tr>
      </thead>
      <tbody>
        ${bodyHtml}
      </tbody>
    </table>
  `;
}

function createActionItemSection(payload) {
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

  const availabilityDrop = prioritySort(
    payload.bottomWowAvailabilityMovers,
    "wow_availability_change",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("availability-drop", availabilityDrop, function(row) {
    return `Reach out to ${supplierName(row)} about inventory issues after availability fell ${signedPercent(row.wow_availability_change)} WoW to ${percent(row.current_availability)}.`;
  });

  const lowAvailability = prioritySort(
    asArray(payload.topCurrentGrs).concat(asArray(payload.bottomAvailability)),
    "current_availability",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("low-availability", lowAvailability, function(row) {
    const currentAvailability = toNumber(row.current_availability);
    if (currentAvailability === null) return "";
    return `Pressure-test replenishment plans with ${supplierName(row)} because availability is only ${percent(row.current_availability)} on ${money(row.current_grs)} in current GRS.`;
  });

  const mrpiIncrease = prioritySort(
    payload.topMrpiMovers,
    "wow_mrpi_change",
    "desc",
    preferredSupplierKeys
  )[0];
  addSuggestion("mrpi-increase", mrpiIncrease, function(row) {
    return `Check in with ${supplierName(row)} about recent price increases after MRPI rose ${bps(row.wow_mrpi_change)} WoW.`;
  });

  const wsiIncrease = prioritySort(
    payload.topWsiMovers,
    "wow_wsi_change",
    "desc",
    preferredSupplierKeys
  )[0];
  addSuggestion("wsi-increase", wsiIncrease, function(row) {
    return `Review pricing competitiveness with ${supplierName(row)} because WSI increased ${bps(row.wow_wsi_change)} WoW.`;
  });

  const visitsDrop = prioritySort(
    payload.bottomYoyMoversVisits,
    "yoy_visits_pct_change",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("visits-drop", visitsDrop, function(row) {
    return `Investigate traffic softness with ${supplierName(row)} after visits declined ${signedPercent(row.yoy_visits_pct_change)} YoY.`;
  });

  const cvrDrop = prioritySort(
    payload.bottomYoyMoversCvr,
    "yoy_cvr_pct_change",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("cvr-drop", cvrDrop, function(row) {
    return `Audit PDP quality and promo support with ${supplierName(row)} because CVR is down ${signedPercent(row.yoy_cvr_pct_change)} YoY.`;
  });

  const shareLoss = prioritySort(
    asArray(payload.topCurrentGrs).filter(function(row) {
      const value = toNumber(row.share_yoy_pct_change);
      return value !== null && value < 0;
    }),
    "share_yoy_pct_change",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("share-loss", shareLoss, function(row) {
    return `Review share losses with ${supplierName(row)} because share is down ${signedPercent(row.share_yoy_pct_change)} YoY while current GRS is ${money(row.current_grs)}.`;
  });

  const grsDecline = prioritySort(
    payload.bottomWowGrsMovers,
    "wow_grs_pct",
    "asc",
    preferredSupplierKeys
  )[0];
  addSuggestion("grs-decline", grsDecline, function(row) {
    return `Plan a recovery check-in with ${supplierName(row)} after GRS declined ${signedPercent(row.wow_grs_pct)} WoW.`;
  });

  const topSuggestions = suggestions.slice(0, 6);
  if (!topSuggestions.length) {
    return `
      <h2>Weekly Action Items</h2>
      <p class="section-note">No major action items were generated from this week's movers.</p>
    `;
  }

  const listHtml = topSuggestions.map(function(item) {
    return `<li>${escapeHtml(item)}</li>`;
  }).join("");

  return `
    <h2>Weekly Action Items</h2>
    <p class="section-note">Quick supplier follow-ups generated from the largest moves in availability, pricing, traffic, conversion, and share.</p>
    <ol class="action-items">
      ${listHtml}
    </ol>
  `;
}

const supplierColumns = [
  { label: "Rank", key: "rank" },
  { label: "Supplier", key: "supplier_name" },
  { label: "Supplier ID", key: "supplier_id" }
];

const htmlBody = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: Arial, sans-serif;
      color: #222;
      line-height: 1.25;
      font-size: 12px;
      margin: 0;
      padding: 8px;
    }

    h1 {
      background: #1f4e79;
      color: white;
      padding: 10px 12px;
      border-radius: 6px;
      font-size: 18px;
      margin: 0 0 12px 0;
    }

    h2 {
      margin-top: 16px;
      margin-bottom: 6px;
      color: #1f4e79;
      border-bottom: 2px solid #1f4e79;
      padding-bottom: 3px;
      font-size: 14px;
    }

    table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 14px;
      font-size: 11px;
    }

    th {
      background: #eaf2f8;
      color: #111;
      text-align: left;
      padding: 5px 6px;
      border: 1px solid #ccc;
      white-space: nowrap;
    }

    td {
      padding: 5px 6px;
      border: 1px solid #ddd;
      white-space: nowrap;
    }

    tr:nth-child(even) {
      background: #f9f9f9;
    }

    .section-note {
      margin: 4px 0 8px 0;
      color: #555;
      font-size: 11px;
    }

    .action-items {
      margin: 6px 0 14px 18px;
      padding: 0;
      font-size: 12px;
    }

    .action-items li {
      margin-bottom: 6px;
    }
  </style>
</head>
<body>
  <h1>Weekly Supplier Performance Summary</h1>

  ${makeTable("Top 15 Current GRS", data.topCurrentGrs, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "GRS YoY %", key: "yoy_grs_pct" },
    { label: "Share", key: "grs_share" },
    { label: "Share YoY %", key: "share_yoy_pct_change" },
    { label: "Availability", key: "current_availability" },
    { label: "Availability WoW %", key: "wow_availability_change" },
    { label: "WSC", key: "current_wsc" },
    { label: "Visits", key: "current_visits" },
    { label: "Visits YoY %", key: "yoy_visits_pct_change" },
    { label: "CVR", key: "current_cvr" },
    { label: "CVR YoY %", key: "yoy_cvr_pct_change" },
    { label: "MRPI", key: "current_mrpi" },
    { label: "MRPI WoW bps", key: "wow_mrpi_change" },
    { label: "WSI", key: "current_wsi" },
    { label: "WSI WoW bps", key: "wow_wsi_change" }
  ])}

  ${createActionItemSection(data)}

  ${makeTable("Top WoW GRS Movers", data.topWowGrsMovers, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "Prior GRS", key: "prior_week_grs" },
    { label: "Change", key: "wow_grs_change" },
    { label: "% Change", key: "wow_grs_pct" }
  ])}

  ${makeTable("Bottom WoW GRS Movers", data.bottomWowGrsMovers, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "Prior GRS", key: "prior_week_grs" },
    { label: "Change", key: "wow_grs_change" },
    { label: "% Change", key: "wow_grs_pct" }
  ])}

  ${makeTable("Top YoY GRS Movers", data.topYoyGrsMovers, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "Prior Year GRS", key: "prior_year_grs" },
    { label: "YoY Change", key: "yoy_grs_change" },
    { label: "YoY %", key: "yoy_grs_pct" }
  ])}

  ${makeTable("Bottom YoY GRS Movers", data.bottomYoyGrsMovers, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "Prior Year GRS", key: "prior_year_grs" },
    { label: "YoY Change", key: "yoy_grs_change" },
    { label: "YoY %", key: "yoy_grs_pct" }
  ])}

  ${makeTable("Top Visits", data.topVisits, [
    ...supplierColumns,
    { label: "Current Visits", key: "current_visits" },
    { label: "Prior Year Visits", key: "prior_year_visits" },
    { label: "YoY Visits % Change", key: "yoy_visits_pct_change" }
  ])}

  ${makeTable("Top CVR", data.topCvr, [
    ...supplierColumns,
    { label: "Current CVR", key: "current_cvr" },
    { label: "Prior Year CVR", key: "prior_year_cvr" },
    { label: "YoY CVR % Change", key: "yoy_cvr_pct_change" }
  ])}

  ${makeTable("Top YoY Visits Movers", data.topYoyMoversVisits, [
    ...supplierColumns,
    { label: "Current Visits", key: "current_visits" },
    { label: "Prior Year Visits", key: "prior_year_visits" },
    { label: "YoY % Change", key: "yoy_visits_pct_change" }
  ])}

  ${makeTable("Bottom YoY Visits Movers", data.bottomYoyMoversVisits, [
    ...supplierColumns,
    { label: "Current Visits", key: "current_visits" },
    { label: "Prior Year Visits", key: "prior_year_visits" },
    { label: "YoY % Change", key: "yoy_visits_pct_change" }
  ])}

  ${makeTable("Top YoY CVR Movers", data.topYoyMoversCvr, [
    ...supplierColumns,
    { label: "Current CVR", key: "current_cvr" },
    { label: "Prior Year CVR", key: "prior_year_cvr" },
    { label: "YoY CVR % Change", key: "yoy_cvr_pct_change" }
  ])}

  ${makeTable("Bottom YoY CVR Movers", data.bottomYoyMoversCvr, [
    ...supplierColumns,
    { label: "Current CVR", key: "current_cvr" },
    { label: "Prior Year CVR", key: "prior_year_cvr" },
    { label: "YoY CVR % Change", key: "yoy_cvr_pct_change" }
  ])}

  ${makeTable("Bottom Availability", data.bottomAvailability, [
    ...supplierColumns,
    { label: "Current Availability", key: "current_availability" },
    { label: "Prior Week Availability", key: "prior_week_availability" },
    { label: "WoW Availability %", key: "wow_availability_change" },
    { label: "Current GRS", key: "current_grs" }
  ])}

  ${makeTable("Bottom WoW Availability Movers", data.bottomWowAvailabilityMovers, [
    ...supplierColumns,
    { label: "Current Availability", key: "current_availability" },
    { label: "Prior Week Availability", key: "prior_week_availability" },
    { label: "WoW Availability %", key: "wow_availability_change" },
    { label: "WoW GRS Change", key: "wow_grs_change" }
  ])}

  ${makeTable("Top MRPI Value", data.topMrpiValue, [
    ...supplierColumns,
    { label: "Current MRPI", key: "current_mrpi" },
    { label: "Prior Week MRPI", key: "prior_week_mrpi" },
    { label: "WoW MRPI bps", key: "wow_mrpi_change" }
  ])}

  ${makeTable("Top MRPI Increases", data.topMrpiMovers, [
    ...supplierColumns,
    { label: "Current MRPI", key: "current_mrpi" },
    { label: "Prior Week MRPI", key: "prior_week_mrpi" },
    { label: "WoW MRPI bps", key: "wow_mrpi_change" }
  ])}

  ${makeTable("Top WSI", data.topWsi, [
    ...supplierColumns,
    { label: "Current WSI", key: "current_wsi" },
    { label: "Prior Week WSI", key: "prior_week_wsi" },
    { label: "WoW WSI bps", key: "wow_wsi_change" }
  ])}

  ${makeTable("Top WSI Increases", data.topWsiMovers, [
    ...supplierColumns,
    { label: "Current WSI", key: "current_wsi" },
    { label: "Prior Week WSI", key: "prior_week_wsi" },
    { label: "WoW WSI bps", key: "wow_wsi_change" }
  ])}
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
