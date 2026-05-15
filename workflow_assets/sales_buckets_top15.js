const rows = $input.all().map(item => item.json);

const buckets = {
  topCurrentGrs: [],
  topWowGrsMovers: [],
  bottomWowGrsMovers: [],
  topYoyGrsMovers: [],
  bottomYoyGrsMovers: [],
};

for (const row of rows) {
  switch (row.section) {
    case 'Top 15 Current GRS':
      buckets.topCurrentGrs.push(row);
      break;

    case 'Top 5 WoW GRS Movers':
      buckets.topWowGrsMovers.push(row);
      break;

    case 'Bottom 5 WoW GRS Movers':
      buckets.bottomWowGrsMovers.push(row);
      break;

    case 'Top 5 YoY GRS Movers':
      buckets.topYoyGrsMovers.push(row);
      break;

    case 'Bottom 5 YoY GRS Movers':
      buckets.bottomYoyGrsMovers.push(row);
      break;
  }
}

return [
  {
    json: buckets,
  },
];
