// Attach the created Google Sheet URL into the case-study email body/subject.
const analysis = $('Build Analysis').first().json;
const sheet = $input.first().json || {};

const spreadsheetId = sheet.spreadsheetId || sheet.id || null;
const spreadsheetUrl =
  sheet.spreadsheetUrl ||
  sheet.url ||
  (spreadsheetId ? `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit` : '');

const linkHtml = spreadsheetUrl
  ? `<p style="margin:12px 0;"><strong>Workbook:</strong> <a href="${spreadsheetUrl}">${spreadsheetUrl}</a></p>`
  : '<p style="margin:12px 0;color:#996600;"><strong>Workbook:</strong> spreadsheet URL unavailable from Create Spreadsheet output.</p>';

const emailHtml = String(analysis.emailHtml || '').replace('<!-- SPREADSHEET_LINK -->', linkHtml);
const markdown = spreadsheetUrl
  ? `${analysis.markdown || ''}\n\nWorkbook: ${spreadsheetUrl}\n`
  : analysis.markdown || '';

return [
  {
    json: {
      ...analysis,
      spreadsheetId,
      spreadsheetUrl,
      emailHtml,
      markdown,
      subject: analysis.subject || 'Loyalty WSC Lift Case Study',
    },
  },
];
