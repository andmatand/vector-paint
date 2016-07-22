# Vector Paint

## What is this?
This is a quick-and-dirty, domain-specific vector drawing tool for making art
for some of my own personal PICO-8 games.  As such, it may not be very polished for
general usage; adjust your expectations accordingly :)

It supports three shape types:
* polygon
* line
* single point

Each shape has a color (one of the 16 PICO-8 colors)

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

## How do I load/display the vector art in my PICO-8 cart?
This program produces hexadecimal strings that you can copy and paste as a
string into a PICO-8 program.  See the file sample-use.p8 for PICO-8 code which
parses and displays one of these strings.

