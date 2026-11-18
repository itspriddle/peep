# Diagrams

A GeoJSON feature collection: a polygon with a hole, a line, and a point.

```geojson
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": { "name": "<script>alert(1)</script>" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [[-10, 40], [10, 40], [10, 55], [-10, 55], [-10, 40]],
          [[-2, 45], [2, 45], [2, 50], [-2, 50], [-2, 45]]
        ]
      }
    },
    {
      "type": "Feature",
      "properties": {},
      "geometry": { "type": "LineString", "coordinates": [[-12, 38], [0, 47.5], [12, 57]] }
    },
    { "type": "Feature", "properties": {}, "geometry": { "type": "Point", "coordinates": [0, 47.5] } }
  ]
}
```

A TopoJSON topology (the specification's example):

```topojson
{
  "type": "Topology",
  "transform": { "scale": [0.0005, 0.0001], "translate": [100, 0] },
  "objects": {
    "example": {
      "type": "GeometryCollection",
      "geometries": [
        { "type": "Point", "properties": { "prop0": "value0" }, "coordinates": [4000, 5000] },
        { "type": "LineString", "properties": { "prop0": "value0", "prop1": 0 }, "arcs": [0] },
        { "type": "Polygon", "properties": { "prop0": "value0", "prop1": { "this": "that" } }, "arcs": [[-2]] }
      ]
    }
  },
  "arcs": [
    [[4000, 0], [1999, 9999], [2000, -9999], [2000, 9999]],
    [[0, 0], [0, 9999], [2000, 0], [0, -9999], [-2000, 0]]
  ]
}
```

Not valid GeoJSON, so it stays code:

```geojson
{ "type": "Point", "coordinates": [1] }
```

In a list:

- ```geojson
  {"type": "MultiPoint", "coordinates": [[-0.13, 51.51], [2.35, 48.86], [13.4, 52.52]]}
  ```
