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

function pp(value) {
  if (value === null || value === undefined || value === "N/A") return "N/A";

  const num = Number(value) * 100;
  const sign = num > 0 ? "+" : "";

  return sign + num.toFixed(1) + " pts";
}

function escapeHtml(value) {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function formatCell(row, key) {
  const value = row[key];

  if (key.includes("pct")) return percent(value);

  if (key.includes("change")) {
    if (key.includes("grs")) return money(value);
    if (key.includes("visits")) return number(value);
    return pp(value);
  }

  if (key.includes("share")) return percent(value);
  if (key.includes("cvr")) return percent(value);
  if (key.includes("availability")) return percent(value);
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

  const bodyHtml = rows.map(function(row) {
    const cells = columns.map(function(col) {
      return `<td>${formatCell(row, col.key)}</td>`;
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
      line-height: 1.4;
    }

    h1 {
      background: #1f4e79;
      color: white;
      padding: 14px;
      border-radius: 6px;
    }

    h2 {
      margin-top: 28px;
      color: #1f4e79;
      border-bottom: 2px solid #1f4e79;
      padding-bottom: 4px;
    }

    table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 22px;
      font-size: 13px;
    }

    th {
      background: #eaf2f8;
      color: #111;
      text-align: left;
      padding: 8px;
      border: 1px solid #ccc;
      white-space: nowrap;
    }

    td {
      padding: 8px;
      border: 1px solid #ddd;
      white-space: nowrap;
    }

    tr:nth-child(even) {
      background: #f9f9f9;
    }
  </style>
</head>
<body>
  <h1>Weekly Supplier Performance Summary</h1>

  ${makeTable("Top Current GRS", data.topCurrentGrs, [
    ...supplierColumns,
    { label: "Current GRS", key: "current_grs" },
    { label: "GRS YoY %", key: "yoy_grs_pct" },
    { label: "Share", key: "grs_share" },
    { label: "Share YoY", key: "share_yoy_change" },
    { label: "Availability", key: "current_availability" },
    { label: "Availability YoY", key: "yoy_availability_change" },
    { label: "Visits", key: "current_visits" },
    { label: "Visits YoY %", key: "yoy_visits_pct_change" },
    { label: "CVR", key: "current_cvr" },
    { label: "CVR YoY", key: "yoy_cvr_change" },
    { label: "MRPI", key: "current_mrpi" },
    { label: "MRPI YoY", key: "yoy_mrpi_change" },
    { label: "WSI", key: "current_wsi" },
    { label: "WSI YoY", key: "yoy_wsi_change" }
  ])}

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
    { label: "WoW Change", key: "wow_availability_change" },
    { label: "Current GRS", key: "current_grs" }
  ])}

  ${makeTable("Bottom WoW Availability Movers", data.bottomWowAvailabilityMovers, [
    ...supplierColumns,
    { label: "Current Availability", key: "current_availability" },
    { label: "Prior Week Availability", key: "prior_week_availability" },
    { label: "WoW Change", key: "wow_availability_change" },
    { label: "WoW GRS Change", key: "wow_grs_change" }
  ])}

  ${makeTable("Top MRPI Value", data.topMrpiValue, [
    ...supplierColumns,
    { label: "Current MRPI", key: "current_mrpi" },
    { label: "Prior Week MRPI", key: "prior_week_mrpi" },
    { label: "WoW Change", key: "wow_mrpi_change" }
  ])}

  ${makeTable("Top MRPI Increases", data.topMrpiMovers, [
    ...supplierColumns,
    { label: "Current MRPI", key: "current_mrpi" },
    { label: "Prior Week MRPI", key: "prior_week_mrpi" },
    { label: "WoW Change", key: "wow_mrpi_change" }
  ])}

  ${makeTable("Top WSI", data.topWsi, [
    ...supplierColumns,
    { label: "Current WSI", key: "current_wsi" },
    { label: "Prior Week WSI", key: "prior_week_wsi" },
    { label: "WoW Change", key: "wow_wsi_change" }
  ])}

  ${makeTable("Top WSI Increases", data.topWsiMovers, [
    ...supplierColumns,
    { label: "Current WSI", key: "current_wsi" },
    { label: "Prior Week WSI", key: "prior_week_wsi" },
    { label: "WoW Change", key: "wow_wsi_change" }
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
