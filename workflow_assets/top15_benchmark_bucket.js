const rows = $input.all().map(function(item) {
  return item.json;
});

return [
  {
    json: {
      topCurrentGrsBenchmark: rows
    }
  }
];
