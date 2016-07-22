# Vector Paint

## What is this?
This is a quick-and-dirty, domain-specific vector drawing tool for making art
for some of my own personal PICO-8 games.  As such, it may not be very polished for
general usage; adjust your expectations accordingly :)

## What's the point of this?
PICO-8 cartridges have a very limited space in which to store raster graphics
(128x128 pixels) so I made this because I needed a way to store many screens
worth of art in a single cartridge.

Each drawing is made up of several shapes. Three different types of "shape" are supported:
* polygon
* line
* single point

Each shape has a color (one of the 16 PICO-8 colors).

The drawing is saved as a hex string, like this:

    05090a1c291830481c451e2f06080c2f26252a4012361c520c51

The format aims to be as small as possible, while remaining easy to parse.
These strings can be stored, parsed, and rendered from within a PICO-8 cart.

## How do I load/display the vector art in my PICO-8 cart?
This program produces hexadecimal strings that you can copy and paste as a
string into a PICO-8 program.  See the file sample-use.p8 for PICO-8 code which
parses and displays one of these strings.

## What are the details of the save format?
The painting is a series of shapes.  Each shape's data is laid out in the following manner:

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

## Why is the canvas so tall and skinny?
Like I said, I made this for a specific personal project...so I might add an
easy way to resize it, but for now this is open source so fix it yourself ;p

## How do I use it?
Read the lovely sections below and they will hopefully answer your every question:

### Running
This is a LÖVE program. If you don't know how LÖVE works, [look it
up](https://love2d.org/). The short answer is that you run `love .` inside this
directory.

### Keyboard Commands
#### Tool Selection
* P: Select Points (hold shift while clicking to select multiple points)
* S: Select Shapes (hold shift while clicking to select multiple shapes)
* M: Move tool (use cursor keys to move the selected point(s)/shape(s))
  * Note: When not in keyboard-friendly mode, the arrow keys can be used at any
    time to move the selected points/shapes
* C: Replace color of selected shapes

#### Other
* Tab: Select next shape/point
* Shift Tab: Select previous shape/point
* Ctrl + S: Save
* 1/2: Select the next/previous color in the palette
* \[: Move the selected shape(s) down in the layer ordering
* \]: Move the selected shape(s) up in the layer ordering
* F5: Force re-render the canvas
* U: Undo

#### Keyboard-Friendly Mode
* K: Toggle keyboard-friendly mode
 * Keyboard-friendly mode allows using the keyboard's arrow keys to move the
   cursor at any time just like the mouse does.
 * This disables use of the arrow keys as a dedicated move tool; i.e. you must first
   press M to enter move mode in order to move things

#### Saving
Since this is a LÖVE program, it is only allowed to write to a folder inside a
[specific LÖVE folder whose location differs based on which OS you are using](
https://love2d.org/wiki/love.filesystem).  Inside that folder you will find a
"vector-paint" folder which contains your drawings.

#### Loading
To load a previously saved drawing, drag and drop the file onto the window
using your OS's file manager UI.
