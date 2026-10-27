# Visualization: Actual Blinds & Shades Joins by Competitor

## Definition Used

This visualization uses a stricter definition of **actual join** than the earlier report:

> An actual join is a customer-selectable PDP/configurator/order-flow option with two or more possible values on the same product or custom product flow.

This excludes attributes that are only:

- Mentioned in PDP descriptions.
- Listed as specs.
- Used as category filters.
- Stated as universal compatibility, such as "can be inside or outside mounted," when the customer does not actually select a mount type.

## High-Level View

| Actual Join | Competitors with Actual Selectable Joins |
|---|---|
| **Size / Measurements** | Amazon, Walmart, Home Depot, Lowe's, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, IKEA, The Shade Store, 3 Day Blinds, Target, Pottery Barn |
| **Color / Fabric / Finish** | Amazon, Walmart, Home Depot, Lowe's, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, IKEA, The Shade Store, 3 Day Blinds, Target, Pottery Barn |
| **Light Filtration / Opacity** | Lowe's Custom, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, The Shade Store, 3 Day Blinds |
| **Mount Type** | Lowe's Custom, Levolor, SelectBlinds, Blindsgalore, Bali, The Shade Store, 3 Day Blinds |
| **Lift / Control Type** | Lowe's Custom, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, The Shade Store, 3 Day Blinds |
| **Top-Down / Bottom-Up** | Lowe's Custom, Levolor, Blinds.com, Blindsgalore, Bali, 3 Day Blinds |
| **Motorization / Smart Control** | Lowe's Custom, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, The Shade Store, 3 Day Blinds |
| **Cell Size / Cell Construction** | Levolor, Blinds.com, Blindsgalore, 3 Day Blinds |
| **Liner Type** | Lowe's Custom, Bali, The Shade Store, 3 Day Blinds |
| **Valance / Cassette / Headrail** | Lowe's Custom, Levolor, SelectBlinds, Bali, The Shade Store, 3 Day Blinds |
| **Roll Type / Roll Position** | Lowe's Custom, Levolor, SelectBlinds, Bali, The Shade Store |
| **Control Side / Control Position** | Lowe's Custom, Levolor, The Shade Store |
| **Hardware / Chain / Bracket Color** | Lowe's Custom, Levolor, The Shade Store |
| **No-Drill Installation** | SelectBlinds |

## Strict Join Matrix

Legend:

- `X` = observed as an actual selectable PDP/configurator/order-flow join.
- `-` = not counted as an actual join under the strict definition, even if mentioned in PDP copy/specs.

| Competitor | Size | Color / Fabric | Light Filtration | Mount Type | Lift / Control | TDBU | Motorized | Cell Size | Liner | Valance / Headrail | Roll Type | Control Side | Hardware / Chain Color | No-Drill |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Amazon | X | X | - | - | - | - | - | - | - | - | - | - | - | - |
| Walmart | X | X | - | - | - | - | - | - | - | - | - | - | - | - |
| Home Depot | X | X | - | - | - | - | - | - | - | - | - | - | - | - |
| Lowe's Custom | X | X | X | X | X | X | X | - | X | X | X | X | X | - |
| Levolor | X | X | X | X | X | X | X | X | - | X | X | X | X | - |
| Blinds.com | X | X | X | - | X | X | X | X | - | - | - | - | - | - |
| SelectBlinds | X | X | X | X | X | - | X | - | - | X | X | - | - | X |
| Blindsgalore | X | X | X | X | X | X | X | X | - | - | - | - | - | - |
| Bali | X | X | X | X | X | X | X | - | X | X | X | - | - | - |
| IKEA | X | X | - | - | - | - | - | - | - | - | - | - | - | - |
| The Shade Store | X | X | X | X | X | - | X | - | X | X | X | X | X | - |
| 3 Day Blinds | X | X | X | X | X | X | X | X | X | X | - | - | - | - |
| Target | X | X | - | - | - | - | - | - | - | - | - | - | - | - |
| Pottery Barn | X | X | - | - | - | - | - | - | - | - | - | - | - | - |

## Join-by-Join Visualization

### Core Joins

```text
Size / Measurements
  Amazon
  Walmart
  Home Depot
  Lowe's
  Levolor
  Blinds.com
  SelectBlinds
  Blindsgalore
  Bali
  IKEA
  The Shade Store
  3 Day Blinds
  Target
  Pottery Barn

Color / Fabric / Finish
  Amazon
  Walmart
  Home Depot
  Lowe's
  Levolor
  Blinds.com
  SelectBlinds
  Blindsgalore
  Bali
  IKEA
  The Shade Store
  3 Day Blinds
  Target
  Pottery Barn

Light Filtration / Opacity
  Lowe's Custom
  Levolor
  Blinds.com
  SelectBlinds
  Blindsgalore
  Bali
  The Shade Store
  3 Day Blinds
```

### Installation and Operation Joins

```text
Mount Type
  Lowe's Custom
  Levolor
  SelectBlinds
  Blindsgalore
  Bali
  The Shade Store
  3 Day Blinds

Lift / Control Type
  Lowe's Custom
  Levolor
  Blinds.com
  SelectBlinds
  Blindsgalore
  Bali
  The Shade Store
  3 Day Blinds

Top-Down / Bottom-Up
  Lowe's Custom
  Levolor
  Blinds.com
  Blindsgalore
  Bali
  3 Day Blinds

Motorization / Smart Control
  Lowe's Custom
  Levolor
  Blinds.com
  SelectBlinds
  Blindsgalore
  Bali
  The Shade Store
  3 Day Blinds
```

### Product-Specific Joins

```text
Cell Size / Cell Construction
  Levolor
  Blinds.com
  Blindsgalore
  3 Day Blinds

Liner Type
  Lowe's Custom
  Bali
  The Shade Store
  3 Day Blinds

Valance / Cassette / Headrail
  Lowe's Custom
  Levolor
  SelectBlinds
  Bali
  The Shade Store
  3 Day Blinds

Roll Type / Roll Position
  Lowe's Custom
  Levolor
  SelectBlinds
  Bali
  The Shade Store

Control Side / Control Position
  Lowe's Custom
  Levolor
  The Shade Store

Hardware / Chain / Bracket Color
  Lowe's Custom
  Levolor
  The Shade Store

No-Drill Installation
  SelectBlinds
```

## Important Interpretation Notes

1. **Mass retailers are more limited under a strict join definition.** Amazon, Walmart, Home Depot, Target, IKEA, and Pottery Barn often describe light filtration, mount compatibility, cordless operation, no-drill, or blackout behavior on PDPs. Those were not counted unless they appeared as actual same-PDP choices.

2. **Custom/specialist retailers drive most actual non-size/color joins.** The richest actual joins come from Lowe's Custom, Levolor, Blinds.com, SelectBlinds, Blindsgalore, Bali, The Shade Store, and 3 Day Blinds.

3. **Mount type is a true join mainly in custom configurators.** The Shade Store and Bali/Costco explicitly expose inside vs outside mount as a configurator step. Mass retailers often say a product can be installed inside or outside mount, but that is generally compatibility copy rather than a selected join.

4. **Light filtration is mixed.** It is a true join in many specialist/custom flows, but at mass retailers it is often a product attribute, category filter, or separate product family rather than a same-PDP selector.

5. **No-drill is usually not a true join.** It is commonly a separate product family or product feature. SelectBlinds was counted because no-drill appears as a selectable headrail/installation upgrade in its custom assortment.

## Wayfair Implication

If Wayfair wants to align with **strict actual competitor joins**, the most defensible expansion beyond size and color is:

1. **Lift / Control Type**
2. **Mount Type**, for custom/configurable products
3. **Light Filtration / Opacity**, where variants truly exist on the same PDP
4. **Subtype-specific joins**, especially:
   - Cell size for cellular shades
   - Liner type for Roman/woven shades
   - Valance/headrail/cassette for roller/custom shades
   - Roll type for roller shades

If Wayfair wants these options surfaced broadly but does not have true variant support, some attributes should be treated as **filters, badges, specs, or product highlights** rather than joins.
