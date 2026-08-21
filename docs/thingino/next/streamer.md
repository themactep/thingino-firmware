# Streamer

As is should be

- Mainstream is mirrored in the substream.
- Substream uses the same image ratio as main stream recalculated for smaller size.
- Mainstream to substream size difference is a scale factor.
- Sizes of OSD elements, masks get normalized using the same scale factor.

## Positioning of elemens

Using percentage of width and height rather than hard units.

## Alignment of elements

Positive coordinates measured from the left and top edges of the frame.

```
  +------------------------------------
  |           .
  | . . . . . *
  |         (5, 2)
```
Negative coordinates measured from right and bottom edges of the frame.

```
                       (-5, -2)       |
                          * . . . . . |
                          .           |
  ------------------------------------+
```

Zero means center.

Element aligned to the left and top for positive coordinates, to the right
and bottom for negative coordinates. Center-alligned for zero.
