# Vector Paint

## What is this?
This is a quick-and-dirty, domain-specific vector drawing tool for making art
for some of my own personal PICO-8 games.  As such, it may not be very polished
for general usage; adjust your expectations accordingly :)

## What's the point of this?
PICO-8 cartridges have a very limited space (128x128 pixels) in which to store
raster graphics so I made this because I needed a way to store many screens
worth of art in a single cartridge.

Each drawing is made up of several shapes. Three different types of "shape" are
supported:
* polygon
* line
* single point

Each shape has a color (one of the 16 PICO-8 colors).

The drawing is saved as a hex string, like this:

```
05090a1c291830481c451e2f06080c2f26252a4012361c520c51
```

The format aims to be small, while still remaining easy to parse.  These
strings can be stored, parsed, and rendered from within a PICO-8 cart.

## How do I load/display the vector art in my PICO-8 cart?
This program produces hexadecimal strings that you can copy and paste as a
string into a PICO-8 program.  See the file sample-use.p8 for PICO-8 code which
parses and displays one of these strings.

## What are the details of the save format?
The painting is a series of shapes.  Each shape's data is laid out in the
following manner:

| #  of bytes | description  |
|-------------|--------------|
|           1 | point count  |
|           1 | color        |

Then for each point, this pair of bytes repeats:

| #  of bytes | description  | note                             |
|-------------|--------------|----------------------------------|
|           1 | x-coordinate |                                  |
|           1 | y-coordinate | saved 1 higher than actual value |

Note that 1 is added to the y-coordinate before it is saved, so when reading
it, 1 needs to be subtracted from the value.  This is done because the numbers
are stored in an unsigned format and we want to allow for saving the
y-coorindate as -1.  The reason we want to be able to position things at -1 on
the y-axis is that, because of the way the scanline rasterization algorithm
here works, in order to draw a polygon which appears to touch the very top of
the canvas, we actually have to position the top point(s) at -1 on the y-axis.

## How do I use it?
Read the lovely sections below and they will hopefully answer your every
question:

### Running
This is a LÖVE program. If you don't know how LÖVE works, [look it
up](https://love2d.org/). The short answer is that you run `love .` inside this
directory.

### Keyboard Commands
#### Tool Selection
* d: **D**raw
* p: Select **P**oints (hold shift while clicking to select multiple points)
* s: Select **S**hapes (hold shift while clicking to select multiple shapes)
* c: Replace **C**olor of selected shape(s)
* m: **M**ove tool (use cursor keys to move the selected point(s)/shape(s))
  * Note: When not in Keyboard-Friendly Mode, you don't need to use this mode;
    the arrow keys can be used at (almost) any time to move the selected
    point(s)/shape(s)
* b: Adjust **B**ackground Image

#### Other Global Keys
* Ctrl/Command + S: **S**ave
* Ctrl/Command + N: **N**ew Painting (clears all shapes, is undo-able)
* Ctrl/Command + Q: **Q**uit
* F11: Toggle fullscreen/windowed mode
* 1/2: Select the next/previous color in the palette
* \[: Move the selected shape(s) down in the layer ordering
* \]: Move the selected shape(s) up in the layer ordering
* F5: Force re-render the canvas (probably not necesary unless there's a bug)
* u: **U**ndo
* h: Toggle **h**ighlight of currently selected shape
* <: decrease opacity of background image
* >: increase opacity of background image
* -: decrease scale of background image (hold Ctrl for greater precision)
* +: increase scale of background image (hold Ctrl for greater precision)
* 0: reset background image scale to initial "best fit"
* Esc: Abort current drawing operation and deselect everything
* k: Toggle **K**eyboard-Friendly Mode
  * Keyboard-Friendly Mode allows using the keyboard's arrow keys to move the
    cursor at any time just like the mouse does.
  * Press Z or Space to do what Left-Click normally does
  * This disables use of the arrow keys as a dedicated move tool; i.e. you must
    first press M to enter move mode in order to move things
* K: Toggle Fine **K**eyboard-cursor movement (when in Keyboard-Friendly Mode)
  * Use this to disable the momentum-based movement that the normal keyboard
    cursor uses, and instead move the cursor 1 pixel per keypress

#### Buttons which all act as the "Action Button" for the current tool
* Left-Click
* Space
* z

#### "Draw" Tool
* Action Button: Place a point under the cursor
* Enter or Right-Click: Finalize drawing

#### "Select Shape(s)"/"Select Point(s)" Tool
* Action Button: Select the polygon under the cursor
* Tab: Select next shape/point
* Shift Tab: Select previous shape/point
* Delete or Backspace: Delete whatever is selected
##### Operation when any shapes are selected
* Ctrl/Command + C: Copy selected shape(s)
* Ctrl/Command + V: Paste shape(s)
  * The pasted shapes are positioned so that the top-left point is under the
    cursor (or at the top-left corner of the canvas if the cursor is not on the
    canvas)
##### Operation when exactly two points from the same polygon are selected
* i: Insert a point at the midpoint between the two selected points

#### "Adjust Background Image" Tool
* Up/Down/Left/Right: Move background image

#### Saving
Since this is a LÖVE program, it is only allowed to write to a folder inside a
[specific LÖVE folder whose location differs based on which OS you are using](
https://love2d.org/wiki/love.filesystem).  Inside that folder you will find a
"vector-paint" folder which contains your drawings, under the filenames you
typed in the "save" dialog.

#### Loading
To load a previously saved drawing, drag and drop the file onto the window
using your OS's file manager UI.

Alternately, you may run the program with a command-line argument which is
interpreted as a filename to load. The file must be inside the save directory,
and the path must be relative to that folder.

#### Importing a Background Image
To import a background image to use as a guide for your drawing, drag and drop
the image file onto the window using your OS's file manager UI.
